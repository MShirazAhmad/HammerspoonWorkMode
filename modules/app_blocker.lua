-- This module handles the simplest enforcement rule: if a frontmost app is on
-- the blocked list during BLOCK mode, close it.
local AppBlocker = {}
AppBlocker.__index = AppBlocker

function AppBlocker.new(config, logger)
    local self = setmetatable({}, AppBlocker)
    self.config = config
    self.logger = logger
    return self
end

function AppBlocker:title()
    return "App Blocker"
end

function AppBlocker:description()
    return "Closes the frontmost app when it matches the blocked apps list during BLOCK mode."
end

local function terminalGuardedApps(config)
    return (config.terminal_guard and config.terminal_guard.apps) or {
        "Terminal",
        "iTerm2",
    }
end

local function isTerminalGuardedApp(config, appName)
    for _, guarded in ipairs(terminalGuardedApps(config)) do
        if appName == guarded then
            return true
        end
    end
    return false
end

function AppBlocker:detectBlockedApp()
    -- Only the frontmost app matters here because that is the app actively
    -- consuming the user's attention right now.
    local app = hs.application.frontmostApplication()
    if not app then
        return nil
    end

    local appName = app:name()
    if isTerminalGuardedApp(self.config, appName) then
        return nil
    end

    for _, blocked in ipairs(self.config.blocked_apps or {}) do
        if appName == blocked then
            -- Return structured details so the caller can both enforce and
            -- explain exactly why intervention happened.
            return {
                app = appName,
                bundle_id = app:bundleID(),
                reason = "Blocked non-research app active: " .. appName,
            }
        end
    end

    return nil
end

function AppBlocker:enforce(result)
    if not result then
        return
    end
    local killedAny = false
    -- Prefer bundle-ID-based termination because it is more reliable than name
    -- matching when multiple instances or aliases are involved.
    if result.bundle_id then
        for _, app in ipairs(hs.application.applicationsForBundleID(result.bundle_id) or {}) do
            app:kill9()
            killedAny = true
        end
    end
    -- Fall back to a name lookup when a bundle-specific kill did not happen.
    if not killedAny then
        local app = hs.application.get(result.app)
        if app then
            app:kill9()
        end
    end
    self.logger:marker("blocked app closed=" .. tostring(result.app))
end

function AppBlocker:statusSummary()
    return string.format("%d blocked apps configured", #(self.config.blocked_apps or {}))
end

return AppBlocker
