-- init.lua — Main entry point for the research work-mode system.
--
-- SYSTEM OVERVIEW
-- ---------------
-- This file is the orchestrator. It wires together eight modules into a single
-- enforcement loop that runs on macOS via Hammerspoon.
--
-- MODE DECISION (strictModeActive):
--   BLOCK = schedule.isActiveNow() AND NOT locationMode.isRelaxed()
--   ALLOW = anything else (outside work hours, or outside the geofence)
--
-- ENFORCEMENT PIPELINE (enforce, called every 2 s and on every app activation):
--   1. BrowserFilter  — check the frontmost browser tab (fastest, most precise)
--   2. AppBlocker     — kill blocked apps that are frontmost
--   3. ActivityClassifier — keyword/domain heuristic on the visible context
--   Each layer returns early so at most one violation fires per pass.
--
-- TERMINAL GUARD FLOW:
--   Shell zle hook fires on Enter → sends hammerspoon://terminal-check-prompt
--   → showTerminalCheckPrompt() shows the full-screen Y/N overlay
--   → user clicks Y or N → writeTerminalGuardState() writes a state file
--   → shell reads state file to decide whether to run or block the command.
--   The state file is the only IPC channel between Hammerspoon and the shell.
--
-- KEY INVARIANTS:
--   • state.terminalPromptOpen prevents a second prompt while one is active.
--   • state.violationCount only resets when transitioning OUT of strict mode.
--   • enforce() returns at the first violation; it does not stack interventions.
--   • In ALLOW mode enforce() still clears terminalPromptOpen to unblock the
--     shell in case the user switched locations or the schedule ended while a
--     prompt was pending.
--
-- MODULE WIRING (all singletons created once and shared for the process lifetime):
--   config        → plain Lua table from config/default.lua
--   logger        → dual-channel log (marker lines + JSONL snapshots)
--   messages      → YAML key/value store, used by overlay and shell messages
--   overlay       → routes to RedWarningOverlay or BlockScreenOverlay
--   schedule      → time-window gate (workdays × hours)
--   locationMode  → GPS geofence → ALLOW/BLOCK; also owns the menu bar badge
--   browserFilter → AppleScript tab inspection (requires allowAppleScript = true)
--   filePathBlocker → kills apps with disallowed AXDocument/AXFilename paths
--   classifier    → keyword/domain heuristic classifier on the current snapshot
--   appBlocker    → kill9 on blocked apps that become frontmost
--   folderBlocker → monitors folder opens, prompts for approval, blocks non-work paths

local config = require("config.default")
local Logger = require("modules.logger")
local Messages = require("modules.messages")
local Overlay = require("modules.overlay")
local Schedule = require("modules.schedule")
local LocationMode = require("modules.location_mode")
local BrowserFilter = require("modules.browser_filter")
local HTTPBlocker = require("modules.http_blocker")
local FilePathBlocker = require("modules.file_path_blocker")
local ActivityClassifier = require("modules.activity_classifier")
local AppBlocker = require("modules.app_blocker")
local FolderBlocker = require("modules.folder_blocker")

-- allowAppleScript is required for BrowserFilter to read browser tab URLs/titles.
-- hs.ipc enables the `hs` CLI tool to send commands to this running instance.
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
local httpBlocker = HTTPBlocker.new(config, logger)
local filePathBlocker = FilePathBlocker.new(config, logger)
local classifier = ActivityClassifier.new(config)
local appBlocker = AppBlocker.new(config, logger)
local folderBlocker = FolderBlocker.new(config, logger)

-- Expose modules globally for console access
_G.folderBlocker = folderBlocker
_G.filePathBlocker = filePathBlocker

-- Cleanup old firewall rules from previous Hammerspoon sessions before starting fresh
httpBlocker:cleanup()

-- state is the only mutable runtime table; all persistent config lives in config.
-- It is intentionally flat so any function can read or write it without OOP ceremony.
local state = {
    -- strictMode is the effective "BLOCK mode is active right now" flag.
    -- Recomputed on every enforce() pass from schedule + location.
    strictMode = false,
    -- violationCount drives overlay escalation. Incremented on each enforce()
    -- call that finds a violation; reset when leaving strict mode.
    violationCount = 0,
    -- Watchers and timers are stored here so they stay referenced for the
    -- lifetime of the Hammerspoon config (Lua GC would stop them otherwise).
    appWatcher = nil,
    scanTimer = nil,
    logTimer = nil,
    reloadWatcher = nil,
    reloadDebounce = nil,
    -- lastClassification caches the most recent classifier result so the menu
    -- can show it without re-running the classifier on every menu open.
    lastClassification = nil,
    -- terminalPromptOpen prevents a second overlay from being shown while one
    -- Y/N terminal check is already waiting for a response.
    terminalPromptOpen = false,
    filePathPromptOpen = false,
}

-- These three are read-only after init and used across multiple functions.
local configFilePath = (hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")) .. "/config/default.lua"
local terminalGuardStatePath = (config.user and config.user.terminal_guard_state_path)
    or (os.getenv("HOME") .. "/.hammerspoon/terminal-command-guard.state")
-- How long a Y or N terminal decision is valid. Default 30 min (1800 s).
local terminalGuardDecisionSeconds = (config.timers and config.timers.terminal_guard_decision_seconds) or 1800

local function timeLabel(hour)
    return string.format("%02d:00", tonumber(hour) or 0)
end

-- Safe single-quote wrapper for shell arguments passed to hs.execute().
local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Strip newlines from values written to the key=value state file so the shell
-- reader (IFS='=' read loop) can parse it line-by-line without corruption.
local function stateFileValue(value)
    return tostring(value or ""):gsub("[\r\n]", " ")
end

-- writeTerminalGuardState writes the IPC state file that the shell-side
-- terminal-command-guard.zsh reads to decide whether to allow a command.
-- Format is a simple key=value file (one pair per line) so the zsh reader
-- only needs a plain while/IFS read loop — no JSON parser needed.
--   mode         — "allow" | "block" | "none"
--   until_epoch  — Unix timestamp after which this decision expires
--   reason       — human-readable explanation shown in the shell
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

-- showTerminalCheckPrompt is the Hammerspoon side of the terminal guard IPC.
-- It is called by the URL event handler (hammerspoon://terminal-check-prompt)
-- and by nothing else. The state.terminalPromptOpen guard ensures at most one
-- overlay is open at a time regardless of how quickly the shell re-triggers.
local function showTerminalCheckPrompt()
    if state.terminalPromptOpen then
        return
    end
    state.terminalPromptOpen = true

    -- The callback fires when the user clicks Y or N on the overlay.
    -- It writes the state file immediately so the shell poll loop unblocks.
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

-- editMenuItem produces a menu entry that opens the config file in the default
-- editor. sectionLabel is purely decorative in the log; it does not scroll to
-- a specific section (the file is small enough to browse).
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

-- workdayLabel converts the boolean workdays table into a readable string for
-- the menu. config.schedule.workdays uses Lua/strftime numbering (1=Sun…7=Sat).
local function workdayLabel()
    local names = {
        [1] = "Sun", [2] = "Mon", [3] = "Tue", [4] = "Wed",
        [5] = "Thu", [6] = "Fri", [7] = "Sat",
    }
    local labels = {}
    for wday = 1, 7 do
        if config.schedule.workdays and config.schedule.workdays[wday] == true then
            table.insert(labels, names[wday])
        end
    end
    return #labels > 0 and table.concat(labels, ", ") or "Every day"
end

-- appendRuleGroup adds a submenu item whose children are the raw values from a
-- config list (e.g. blocked_apps, allowed_domains). Each child also offers a
-- direct "Edit …" link to the config file so the user can tune lists in place.
local function appendRuleGroup(items, heading, values)
    if not values or #values == 0 then
        return
    end
    local submenu = {
        editMenuItem(heading),
        { title = "-" },
    }
    for _, value in ipairs(values) do
        table.insert(submenu, { title = tostring(value), disabled = true })
    end
    table.insert(items, { title = heading, disabled = false, menu = submenu })
end

-- appendSection adds a submenu item whose children are plain informational
-- strings (status lines, descriptions). Unlike appendRuleGroup, these are not
-- editable lists; they are read-only status snapshots.
local function appendSection(items, heading, lines)
    if not lines or #lines == 0 then
        return
    end
    local submenu = {
        editMenuItem(heading),
        { title = "-" },
    }
    for _, line in ipairs(lines) do
        table.insert(submenu, { title = tostring(line), disabled = true })
    end
    table.insert(items, { title = heading, disabled = false, menu = submenu })
end

-- strictModeActive is the single authoritative answer to "should we enforce now?"
-- Both the enforce loop and the terminal-check URL handler call this directly
-- rather than reading state.strictMode, so they always have a fresh answer.
-- BLOCK requires BOTH the schedule to be active AND the location to be non-relaxed.
local function strictModeActive()
    if not schedule:isActiveNow() then
        return false
    end
    if locationMode:isRelaxed() then
        return false
    end
    return true
end

-- handleViolation is the single call site for recording and displaying any
-- enforcement action. By centralizing it here, all three enforcement layers
-- (browser, app, classifier) share identical escalation and logging behavior.
-- activePredicate is optional; when supplied the overlay hides itself as soon
-- as the predicate returns false (e.g. once the distracting tab is closed).
local function handleViolation(kind, details, activePredicate)
    state.violationCount = state.violationCount + 1
    if activePredicate then
        overlay:showInterventionWhile(kind, details, state.violationCount, activePredicate)
    else
        overlay:showIntervention(kind, details, state.violationCount)
    end
    logger:marker("violation kind=" .. tostring(kind) .. " details=" .. tostring(details and details.reason or ""))
end

local function handleFixedViolation(kind, details, durationSeconds)
    state.violationCount = state.violationCount + 1
    local reason = (details and details.reason) or messages:get("overlay.fallback_reason")
    overlay:show(string.upper(kind) .. " " .. messages:get("overlay.block_suffix") .. "\n\n" .. reason, durationSeconds)
    logger:marker("violation kind=" .. tostring(kind) .. " details=" .. tostring(reason))
end

-- currentSnapshot gathers the full observable context at this instant.
-- It is called by enforce(), logSnapshot(), and activeRulesMenu(), so the
-- shape of the returned table is the common "event record" format across the
-- whole system. The classifier result is embedded so callers do not need to
-- re-run it separately.
local function currentSnapshot()
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

-- activeRulesMenu builds the full menu tree that LocationMode renders in the
-- menu bar. It is called lazily on every menu open so the data is always fresh.
-- It returns a structured table rather than a flat list so LocationMode can
-- inject its own header rows before the shared items.
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
    appendSection(items, httpBlocker:title(), {
        httpBlocker:description(),
        httpBlocker:statusSummary(),
    })
    appendSection(items, filePathBlocker:title(), {
        filePathBlocker:description(),
        filePathBlocker:statusSummary(),
    })
    appendRuleGroup(items, "  Allowed folder paths", config.file_path_blocker and config.file_path_blocker.allowed_paths)
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
        actions = { { title = "Test red warning", fn = testRedWarningOverlay } },
        items = items,
    }
end

-- enforce() is the central enforcement function. It is called:
--   • every config.timers.scan_seconds (currently 2 s) via scanTimer
--   • every time any app is activated (appWatcher)
--   • once at startup
--
-- The function recomputes strictMode on every call so GPS and schedule
-- transitions take effect immediately without needing a separate watcher.
-- It returns after the FIRST violation found so enforcement layers do not
-- stack (e.g. a browser violation does not also trigger the classifier).
local function enforce()
    local wasStrict = state.strictMode
    state.strictMode = strictModeActive()
    overlay:setStrictMode(state.strictMode)

    -- Reset escalation counter when transitioning out of BLOCK mode so
    -- violations from a previous session don't carry forward.
    if wasStrict and not state.strictMode then
        state.violationCount = 0
    end

    -- Layer 1.5: http firewall — update firewall rules when mode changes.
    -- Must happen before the ALLOW mode check so firewall is disabled when exiting BLOCK.
    -- HTTPBlocker uses system-level firewall (pfctl) to block all HTTP traffic.
    httpBlocker:updateForStrictMode(wasStrict, state.strictMode)

    -- In ALLOW mode we still log activity but do not intervene.
    -- Also clear terminalPromptOpen so a stale pending-prompt flag from a
    -- previous BLOCK session does not block the shell after mode changes.
    if not state.strictMode then
        state.terminalPromptOpen = false
        return
    end

    -- Layer 1: browser — fastest and most precise because it has the actual URL.
    local browserResult = browserFilter:detectDistraction()
    if browserResult then
        browserFilter:enforce(browserResult)
        handleViolation("browser", browserResult, function()
            return browserFilter:isSourceStillDistracting(browserResult)
        end)
        return
    end

    -- Layer 2: app — if a known blocked app is frontmost, kill it immediately.
    local blockedApp = appBlocker:detectBlockedApp()
    if blockedApp then
        appBlocker:enforce(blockedApp)
        handleViolation("app", blockedApp)
        return
    end

    -- Layer 2.25: folder paths — kill any app with open document folders outside
    -- the configured blocked roots. Unknown paths prompt once for a persistent
    -- allow/block decision before enforcement continues.
    local blockedFilePath = filePathBlocker:detectViolation()
    if blockedFilePath then
        filePathBlocker:enforce(blockedFilePath)
        handleFixedViolation(
            "folder path",
            blockedFilePath,
            (config.file_path_blocker and config.file_path_blocker.violation_overlay_seconds) or 5
        )
        return
    end

    if not state.filePathPromptOpen then
        local unknownFilePath = filePathBlocker:detectUnknownPath()
        if unknownFilePath then
            state.filePathPromptOpen = true
            overlay:showFolderApprovalPrompt(unknownFilePath.path, function(approved)
                state.filePathPromptOpen = false
                if approved then
                    filePathBlocker:approvePath(unknownFilePath.path)
                    hs.alert.show("Path allowed: " .. tostring(unknownFilePath.path), 2)
                    logger:marker("file_path_blocker folder_approved_by_user path=" .. tostring(unknownFilePath.path))
                else
                    filePathBlocker:blockPath(unknownFilePath.path)
                    filePathBlocker:enforce(unknownFilePath)
                    handleFixedViolation(
                        "folder path",
                        {
                            reason = "Blocked path after user decision:\n" .. tostring(unknownFilePath.path),
                        },
                        (config.file_path_blocker and config.file_path_blocker.violation_overlay_seconds) or 5
                    )
                end
            end)
            return
        end
    end

    -- Layer 2.5: folder — detect new folder opens and prompt for approval.
    -- If approved, add to allowed list; if rejected, kill the app.
    local newFolder = folderBlocker:detectNewFolder()
    if newFolder then
        if folderBlocker:isPathAllowed(newFolder) then
            -- Already in allowed list (shouldn't happen but handle gracefully)
            folderBlocker:addAllowedFolder(newFolder)
        else
            -- New folder: show Y/N prompt
            overlay:showFolderApprovalPrompt(newFolder, function(approved)
                if approved then
                    folderBlocker:addAllowedFolder(newFolder)
                    hs.alert.show("Folder approved: " .. newFolder, 2)
                    logger:marker("folder_blocker folder_approved_by_user path=" .. tostring(newFolder))
                else
                    -- Kill the frontmost app for accessing non-work path
                    local app = hs.application.frontmostApplication()
                    if app then
                        app:kill9()
                        logger:marker("folder_blocker app_killed_for_unapproved_path app=" .. tostring(app:name()) .. " path=" .. tostring(newFolder))
                    end
                    hs.alert.show("App closed: Non-work folder blocked", 2)
                end
            end)
            return
        end
    end

    -- Layer 3: classifier — slower heuristic, only triggers at high confidence
    -- (config.thresholds.off_task_lockout_confidence, default 0.9).
    local snapshot = currentSnapshot()
    local classification = snapshot.classification or {}
    if classification.status == "off_task" and classification.confidence >= config.thresholds.off_task_lockout_confidence then
        handleViolation("activity", classification)
    end
end

local function logSnapshot(force)
    local snapshot = currentSnapshot()
    logger:activity(snapshot, force == true)
end

-- startReloadWatcher triggers hs.reload() 250 ms after any .lua file in
-- ~/.hammerspoon changes. The debounce prevents rapid re-loads when editors
-- write multiple files in quick succession (e.g. save + format).
local function startReloadWatcher()
    local configDir = hs.configdir or (os.getenv("HOME") .. "/.hammerspoon")
    state.reloadWatcher = hs.pathwatcher.new(configDir, function(paths)
        local shouldReload = false
        for _, path in ipairs(paths or {}) do
            if type(path) == "string" and path:lower():match("%.lua$") then
                shouldReload = true
                break
            end
        end
        if not shouldReload then return end
        if state.reloadDebounce then state.reloadDebounce:stop() end
        state.reloadDebounce = hs.timer.doAfter(0.25, function()
            hs.reload()
        end)
    end)
    state.reloadWatcher:start()
end

-- URL event: hammerspoon://terminal-check-prompt
-- Sent by shell/terminal-command-guard.zsh when the user runs a command while
-- a Y/N terminal decision is required. In ALLOW mode we skip the prompt and
-- just auto-approve so the shell is not blocked outside work hours.
hs.urlevent.bind("terminal-check-prompt", function()
    if strictModeActive() then
        showTerminalCheckPrompt()
        return
    end
    -- Outside BLOCK mode: auto-approve so the shell guard does not block commands.
    writeTerminalGuardState("allow", terminalGuardDecisionSeconds, messages:get("terminal_guard.state_reason.inactive_allow"))
end)

hs.urlevent.bind("test-red-warning", function()
    testRedWarningOverlay()
end)

-- Startup sequence: GPS first so the initial mode is correct before enforce() runs.
locationMode:start()
locationMode:setMenuProvider(activeRulesMenu)
startReloadWatcher()

-- appWatcher fires on every app activation so enforcement is immediate when
-- the user switches to a blocked app, rather than waiting up to scan_seconds.
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

-- scanTimer is the catch-all for situations where no app event fires but the
-- state still needs checking (e.g. a blocked browser tab is already open).
state.scanTimer = hs.timer.doEvery(config.timers.scan_seconds, enforce)
-- logTimer writes activity snapshots at a lower cadence to build a timeline
-- without duplicating records on every scan tick.
state.logTimer = hs.timer.doEvery(config.timers.activity_log_seconds, function()
    logSnapshot(false)
end)

-- Run one immediate pass at startup so config takes effect instantly.
logger:marker("Research work mode loaded")
logSnapshot(true)
enforce()
hs.alert.show("Research work mode loaded", 2)
