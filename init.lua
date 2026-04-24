-- Main entry point for the research work-mode system.
-- This file wires together the modules, keeps a small runtime state table,
-- decides whether the system is currently enforcing BLOCK behavior, and
-- starts the timers/watchers that keep the automation alive.
local config = require("config.default")
local Logger = require("modules.logger")
local Messages = require("modules.messages")
local Overlay = require("modules.overlay")
local Schedule = require("modules.schedule")
local LocationMode = require("modules.location_mode")
local BrowserFilter = require("modules.browser_filter")
local ActivityClassifier = require("modules.activity_classifier")
local AppBlocker = require("modules.app_blocker")

require("hs.ipc")
hs.allowAppleScript(true)
hs.autoLaunch(false)
hs.dockIcon(false)
hs.menuIcon(false)

-- Create one shared instance of each module so the app behaves like a single
-- coordinated system instead of a pile of independent scripts.
local logger = Logger.new(config)
local messages = Messages.new((config.user and config.user.messages_path)
    or ((hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")) .. "/config/messages.yaml"))
local overlay = Overlay.new(config, logger, messages)
local schedule = Schedule.new(config)
local locationMode = LocationMode.new(config, logger)
local browserFilter = BrowserFilter.new(config, logger)
local classifier = ActivityClassifier.new(config)
local appBlocker = AppBlocker.new(config, logger)

local state = {
    -- strictMode is the effective "BLOCK mode is active right now" flag.
    strictMode = false,
    -- violationCount lets overlays escalate when the user repeatedly drifts.
    violationCount = 0,
    -- Watchers and timers are stored here so they stay referenced for the
    -- lifetime of the Hammerspoon config.
    appWatcher = nil,
    scanTimer = nil,
    logTimer = nil,
    reloadWatcher = nil,
    reloadDebounce = nil,
    lastClassification = nil,
    terminalPromptOpen = false,
}

local configFilePath = (hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")) .. "/config/default.lua"
local terminalGuardStatePath = (config.user and config.user.terminal_guard_state_path)
    or (os.getenv("HOME") .. "/.hammerspoon/terminal-command-guard.state")
local terminalGuardDecisionSeconds = (config.timers and config.timers.terminal_guard_decision_seconds) or 1800

local function timeLabel(hour)
    return string.format("%02d:00", tonumber(hour) or 0)
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function stateFileValue(value)
    return tostring(value or ""):gsub("[\r\n]", " ")
end

local function writeTerminalGuardState(mode, durationSeconds, reason)
    local file = io.open(terminalGuardStatePath, "w")
    if not file then
        logger:marker("terminal guard state write failed path=" .. tostring(terminalGuardStatePath))
        return false
    end

    local untilEpoch = os.time() + math.max(1, durationSeconds or terminalGuardDecisionSeconds)
    file:write("mode=" .. stateFileValue(mode) .. "\n")
    file:write("until_epoch=" .. tostring(untilEpoch) .. "\n")
    file:write("reason=" .. stateFileValue(reason) .. "\n")
    file:close()
    return true
end

local function showTerminalCheckPrompt()
    if state.terminalPromptOpen then
        return
    end
    state.terminalPromptOpen = true

    overlay:showTerminalPrompt(function(allowed)
        state.terminalPromptOpen = false
        if allowed then
            writeTerminalGuardState("allow", terminalGuardDecisionSeconds, messages:get("terminal_guard.state_reason.allow"))
            hs.alert.show(messages:get("terminal_guard.alert.allow"), 2)
            logger:marker("terminal guard decision=allow duration=" .. tostring(terminalGuardDecisionSeconds))
        else
            writeTerminalGuardState("block", terminalGuardDecisionSeconds, messages:get("terminal_guard.state_reason.block"))
            hs.alert.show(messages:get("terminal_guard.alert.block"), 2)
            logger:marker("terminal guard decision=block duration=" .. tostring(terminalGuardDecisionSeconds))
        end
    end)
end

local function openConfigEditor(sectionLabel)
    local _, ok = hs.execute("open " .. shellQuote(configFilePath), true)
    if ok then
        logger:marker("open config editor section=" .. tostring(sectionLabel or "config"))
    else
        hs.alert.show("Could not open config file", 2)
    end
end

local function editMenuItem(label)
    return {
        title = "Edit " .. tostring(label),
        fn = function()
            openConfigEditor(label)
        end,
    }
end

local function testRedWarningOverlay()
    overlay:showRedWarningTest(10)
    logger:marker("red warning overlay test duration=10")
end

local function workdayLabel()
    local names = {
        [1] = "Sun",
        [2] = "Mon",
        [3] = "Tue",
        [4] = "Wed",
        [5] = "Thu",
        [6] = "Fri",
        [7] = "Sat",
    }
    local labels = {}
    for wday = 1, 7 do
        if config.schedule.workdays and config.schedule.workdays[wday] == true then
            table.insert(labels, names[wday])
        end
    end
    return #labels > 0 and table.concat(labels, ", ") or "Every day"
end

local function appendRuleGroup(items, heading, values)
    if not values or #values == 0 then
        return
    end
    local submenu = {
        editMenuItem(heading),
        { title = "-" },
    }
    for _, value in ipairs(values) do
        table.insert(submenu, {
            title = tostring(value),
            disabled = true,
        })
    end
    table.insert(items, {
        title = heading,
        disabled = false,
        menu = submenu,
    })
end

local function appendSection(items, heading, lines)
    if not lines or #lines == 0 then
        return
    end
    local submenu = {
        editMenuItem(heading),
        { title = "-" },
    }
    for _, line in ipairs(lines) do
        table.insert(submenu, {
            title = tostring(line),
            disabled = true,
        })
    end
    table.insert(items, {
        title = heading,
        disabled = false,
        menu = submenu,
    })
end

local function strictModeActive()
    -- BLOCK mode only applies when the schedule is active and the current
    -- location is not in the relaxed/allowed zone.
    if not schedule:isActiveNow() then
        return false
    end

    if locationMode:isRelaxed() then
        return false
    end

    return true
end

local function handleViolation(kind, details, activePredicate)
    -- Every violation increments the escalation counter, shows the overlay,
    -- and writes a marker entry that explains what triggered enforcement.
    state.violationCount = state.violationCount + 1
    if activePredicate then
        overlay:showInterventionWhile(kind, details, state.violationCount, activePredicate)
    else
        overlay:showIntervention(kind, details, state.violationCount)
    end
    logger:marker("violation kind=" .. tostring(kind) .. " details=" .. tostring(details and details.reason or ""))
end

local function currentSnapshot()
    -- A snapshot captures the visible work context right now so it can be
    -- logged and classified as research, neutral, or off-task.
    local browserContext = browserFilter:frontmostContext()
    local frontmostApp = hs.application.frontmostApplication()
    local snapshot = {
        ts = logger:isoTimestamp(),
        work_mode = state.strictMode,
        schedule_active = schedule:isActiveNow(),
        location_mode = locationMode:mode(),
        app = frontmostApp and frontmostApp:name() or nil,
        bundle_id = frontmostApp and frontmostApp:bundleID() or nil,
        window_title = frontmostApp and frontmostApp:focusedWindow() and frontmostApp:focusedWindow():title() or nil,
        browser = browserContext,
    }
    snapshot.classification = classifier:classify(snapshot)
    state.lastClassification = snapshot.classification
    return snapshot
end

local function activeRulesMenu()
    local scheduleConfig = config.schedule or {}
    local locationState = locationMode.lastState or {}
    local strict = strictModeActive()
    local modeLabel = strict and "BLOCK" or "ALLOW"
    local snapshot = currentSnapshot()
    local browser = snapshot.browser or {}
    local frontmostLabel = snapshot.app or "No frontmost app"
    if browser.host then
        frontmostLabel = tostring(frontmostLabel) .. " - " .. tostring(browser.host)
    elseif snapshot.window_title then
        frontmostLabel = tostring(frontmostLabel) .. " - " .. tostring(snapshot.window_title)
    end

    local items = {}
    appendSection(items, "System", {
        "Current mode: " .. modeLabel,
        strict and "Enforcement: active now" or "Enforcement: paused right now",
        "Frontmost: " .. frontmostLabel,
        "Classifier: " .. classifier:statusSummary(snapshot),
        "Last event: " .. tostring(logger:lastMarker() or "none"),
        "Overlay: " .. overlay:statusSummary(),
    })
    appendSection(items, schedule:title(), {
        schedule:description(),
        schedule:statusSummary(),
        string.format("Window: %s-%s on %s", timeLabel(scheduleConfig.start_hour), timeLabel(scheduleConfig.end_hour), workdayLabel()),
    })
    appendSection(items, locationMode:title(), {
        locationMode:description(),
        locationMode:statusSummary(),
        "Raw state: " .. tostring(locationState.mode or "unknown"),
    })
    appendSection(items, appBlocker:title(), {
        appBlocker:description(),
        appBlocker:statusSummary(),
    })
    appendRuleGroup(items, "  Blocked apps", config.blocked_apps)
    appendSection(items, browserFilter:title(), {
        browserFilter:description(),
        browserFilter:statusSummary(),
    })
    appendRuleGroup(items, "  Allowed domains", config.browser and config.browser.allowed_domains)
    appendRuleGroup(items, "  Blocked domains", config.browser and config.browser.blocked_domains)
    appendRuleGroup(items, "  Blocked title terms", config.browser and config.browser.blocked_title_terms)
    appendSection(items, classifier:title(), {
        classifier:description(),
        classifier:statusSummary(snapshot),
    })
    appendRuleGroup(items, "  Research apps", config.categories and config.categories.research_apps)
    appendRuleGroup(items, "  Research keywords", config.categories and config.categories.research_keywords)
    appendRuleGroup(items, "  Distraction keywords", config.categories and config.categories.distraction_keywords)

    return {
        title = "Research Mode Dashboard",
        mode = modeLabel,
        actions = {
            {
                title = "Test red warning",
                fn = testRedWarningOverlay,
            },
        },
        items = items,
    }
end

local function enforce()
    -- Recompute the current enforcement mode on every pass because GPS and
    -- schedule can both change over time.
    local wasStrict = state.strictMode
    state.strictMode = strictModeActive()
    overlay:setStrictMode(state.strictMode)

    -- Reset escalation counter when transitioning out of BLOCK mode so
    -- violations from a previous session don't carry forward.
    if wasStrict and not state.strictMode then
        state.violationCount = 0
    end

    -- In ALLOW mode we still log activity, but we do not actively intervene.
    if not state.strictMode then
        state.terminalPromptOpen = false
        return
    end

    -- Browser filtering runs first because a distracting tab is often the
    -- clearest and fastest thing to correct.
    local browserResult = browserFilter:detectDistraction()
    if browserResult then
        browserFilter:enforce(browserResult)
        handleViolation("browser", browserResult, function()
            return browserFilter:isSourceStillDistracting(browserResult)
        end)
        return
    end

    -- App blocking is the next layer: if a known blocked app is frontmost,
    -- close it and record the violation.
    local blockedApp = appBlocker:detectBlockedApp()
    if blockedApp then
        appBlocker:enforce(blockedApp)
        handleViolation("app", blockedApp)
        return
    end

    -- If neither a blocked app nor a blocked tab was found, use the broader
    -- activity classifier to decide whether the current context still looks
    -- meaningfully off-task.
    local snapshot = currentSnapshot()
    local classification = snapshot.classification or {}
    if classification.status == "off_task" and classification.confidence >= config.thresholds.off_task_lockout_confidence then
        handleViolation("activity", classification)
    end
end

local function logSnapshot(force)
    -- Periodic snapshots create a lightweight history of what was on screen.
    local snapshot = currentSnapshot()
    logger:activity(snapshot, force == true)
end

local function startReloadWatcher()
    -- Auto-reload makes development easier: editing a Lua file inside
    -- ~/.hammerspoon triggers a config reload after a short debounce.
    local configDir = hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")
    state.reloadWatcher = hs.pathwatcher.new(configDir, function(paths)
        local shouldReload = false
        for _, path in ipairs(paths or {}) do
            if type(path) == "string" and path:lower():match("%.lua$") then
                shouldReload = true
                break
            end
        end

        if not shouldReload then
            return
        end

        if state.reloadDebounce then
            state.reloadDebounce:stop()
        end

        state.reloadDebounce = hs.timer.doAfter(0.25, function()
            hs.reload()
        end)
    end)
    state.reloadWatcher:start()
end

hs.urlevent.bind("terminal-check-prompt", function()
    if strictModeActive() then
        showTerminalCheckPrompt()
        return
    end

    writeTerminalGuardState("allow", terminalGuardDecisionSeconds, messages:get("terminal_guard.state_reason.inactive_allow"))
end)

hs.urlevent.bind("test-red-warning", function()
    testRedWarningOverlay()
end)

-- Start GPS polling immediately so the script knows whether it should begin in
-- ALLOW or BLOCK mode.
locationMode:start()
locationMode:setMenuProvider(activeRulesMenu)
startReloadWatcher()

-- App activation events give the script fast feedback when the user switches
-- context, instead of waiting for the next periodic scan.
state.appWatcher = hs.application.watcher.new(function(appName, eventType)
    if eventType == hs.application.watcher.activated then
        logger:event("activated", { app = appName, work_mode = strictModeActive() })
        logSnapshot(true)
        enforce()
    elseif eventType == hs.application.watcher.launched then
        logger:event("launched", { app = appName, work_mode = strictModeActive() })
    elseif eventType == hs.application.watcher.terminated then
        logger:event("terminated", { app = appName, work_mode = strictModeActive() })
    end
end)
state.appWatcher:start()

-- The scan timer periodically re-enforces rules in case nothing triggers an
-- app event but the current state still needs checking.
state.scanTimer = hs.timer.doEvery(config.timers.scan_seconds, enforce)
-- The log timer writes snapshots at a lower cadence so later review has a
-- timeline of work without writing duplicate records constantly.
state.logTimer = hs.timer.doEvery(config.timers.activity_log_seconds, function()
    logSnapshot(false)
end)

-- Record startup, log the first visible context, and run one immediate
-- enforcement pass so the config takes effect as soon as it loads.
logger:marker("Research work mode loaded")
logSnapshot(true)
enforce()
hs.alert.show("Research work mode loaded", 2)
