-- Main entry point for the research work-mode system.
-- This file wires together the modules, keeps a small runtime state table,
-- decides whether the system is currently enforcing BLOCK behavior, and
-- starts the timers/watchers that keep the automation alive.
local config = require("config.default")
local Logger = require("modules.logger")
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
local overlay = Overlay.new(config, logger)
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
}

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

local function handleViolation(kind, details)
    -- Every violation increments the escalation counter, shows the overlay,
    -- and writes a marker entry that explains what triggered enforcement.
    state.violationCount = state.violationCount + 1
    overlay:showIntervention(kind, details, state.violationCount)
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
    return snapshot
end

local function enforce()
    -- Recompute the current enforcement mode on every pass because GPS and
    -- schedule can both change over time.
    state.strictMode = strictModeActive()
    overlay:setStrictMode(state.strictMode)

    -- In ALLOW mode we still log activity, but we do not actively intervene.
    if not state.strictMode then
        return
    end

    -- Browser filtering runs first because a distracting tab is often the
    -- clearest and fastest thing to correct.
    local browserResult = browserFilter:detectDistraction()
    if browserResult then
        browserFilter:enforce(browserResult)
        handleViolation("browser", browserResult)
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

-- Start GPS polling immediately so the script knows whether it should begin in
-- ALLOW or BLOCK mode.
locationMode:start()
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
