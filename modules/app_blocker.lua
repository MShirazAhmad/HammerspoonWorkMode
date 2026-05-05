-- app_blocker.lua — Second enforcement layer: close blocked apps that are frontmost.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- AppBlocker runs after BrowserFilter and before ActivityClassifier in enforce().
-- Its job is simple: if the frontmost application is on config.blocked_apps AND
-- it is not a terminal-guarded app (Terminal, iTerm2), kill it.
--
-- WHY kill9 INSTEAD OF quit?
-- --------------------------
-- kill() (SIGTERM) lets the app intercept the signal and show a "save changes?"
-- dialog, which the user can cancel. kill9() (SIGKILL) cannot be caught or
-- ignored, so it guarantees the app terminates immediately. This is intentional:
-- the blocked app list contains apps the user has explicitly decided to forbid
-- during BLOCK mode, and a cancellable quit dialog defeats the purpose.
--
-- TERMINAL GUARD EXEMPTION
-- ------------------------
-- Terminal and iTerm2 appear in BOTH blocked_apps and terminal_guard.apps.
-- isTerminalGuardedApp() returns true for these apps so detectBlockedApp() skips
-- them. Instead of being killed, terminal apps are handled by the separate
-- terminal guard Y/N prompt flow (URL event → showTerminalCheckPrompt).
-- This allows the user to keep a terminal open for legitimate research work
-- after answering Y.
--
-- The two lists (blocked_apps and terminal_guard.apps) are maintained separately
-- in config because in future a terminal might be removed from blocking entirely
-- without changing the guard behavior, or vice versa.
--
-- BUNDLE ID PREFERENCE
-- --------------------
-- enforce() prefers bundle-ID-based termination (applicationsForBundleID) over
-- name-based lookup because:
--   1. Multiple instances of the same app can run simultaneously (e.g. Chrome
--      and Chrome Helper share "Google Chrome" as a name prefix).
--   2. Some apps have localized names that differ from their bundle display name.
--   3. Bundle IDs are stable across renames.
-- Falls back to name-based lookup when no bundle ID was captured.

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

-- terminalGuardedApps returns the list of apps that should be handled by the
-- terminal guard prompt rather than immediately killed. Falls back to a default
-- list in case the config key is absent.
local function terminalGuardedApps(config)
    return (config.terminal_guard and config.terminal_guard.apps) or { "Terminal", "iTerm2" }
end

local function isTerminalGuardedApp(config, appName)
    for _, guarded in ipairs(terminalGuardedApps(config)) do
        if appName == guarded then return true end
    end
    return false
end

-- detectBlockedApp returns a violation table if the frontmost app is on the
-- blocked list and is not terminal-guarded, or nil otherwise.
-- Only the FRONTMOST app is checked because blocking background apps would be
-- disruptive (the user may need them for legitimate work in another window).
function AppBlocker:detectBlockedApp()
    local app = hs.application.frontmostApplication()
    if not app then return nil end

    local appName = app:name()

    -- Terminal-guarded apps are handled by the Y/N prompt, not killed outright.
    if isTerminalGuardedApp(self.config, appName) then
        return nil
    end

    for _, blocked in ipairs(self.config.blocked_apps or {}) do
        if appName == blocked then
            return {
                app = appName,
                bundle_id = app:bundleID(),
                reason = "Blocked non-research app active: " .. appName,
            }
        end
    end

    return nil
end

-- enforce() kills the app identified in the result table. Prefers bundle-ID
-- termination for robustness; falls back to name-based lookup.
function AppBlocker:enforce(result)
    if not result then return end
    local killedAny = false
    if result.bundle_id then
        for _, app in ipairs(hs.application.applicationsForBundleID(result.bundle_id) or {}) do
            app:kill9()
            killedAny = true
        end
    end
    if not killedAny then
        local app = hs.application.get(result.app)
        if app then app:kill9() end
    end
    self.logger:marker("blocked app closed=" .. tostring(result.app))
end

function AppBlocker:statusSummary()
    return string.format("%d blocked apps configured", #(self.config.blocked_apps or {}))
end

return AppBlocker
