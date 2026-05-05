-- browser_filter.lua — Browser tab enforcement layer.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- BrowserFilter is the FIRST enforcement layer in enforce(). It runs before
-- AppBlocker and ActivityClassifier because it has the most precise signal:
-- the actual URL and tab title from the frontmost browser window.
--
-- Called from two places in init.lua:
--   enforce()        → detectDistraction() + enforce() + isSourceStillDistracting()
--   currentSnapshot() → frontmostContext() (for logging and classifier input)
--
-- HOW IT READS BROWSER TABS (AppleScript)
-- ----------------------------------------
-- hs.allowAppleScript(true) is set in init.lua. Each supported browser has a
-- small AppleScript snippet in APPLESCRIPTS that returns:
--   line 1: tab title
--   line 2: tab URL (must start with http:// or https://)
--   line 3: AppleScript window id (used later for window tracking)
-- If AppleScript fails (browser is unresponsive, permissions denied, etc.)
-- frontmostContext() falls back to the Hammerspoon window title alone.
--
-- VIOLATION DETECTION RULE ORDER (detectDistraction):
--   1. Allowed domain match → nil (no violation; research page wins outright)
--   2. Blocked domain match → violation with kind="blocked_domain"
--   3. Blocked title term   → violation with kind="blocked_title"
-- Allowed domains are checked first so a research site with a title containing
-- "news" (e.g. "Latest Nature news") is never incorrectly flagged.
--
-- CONDITIONAL OVERLAY (isSourceStillDistracting)
-- -----------------------------------------------
-- Browser violations use showInterventionWhile() in init.lua, which re-checks
-- an activePredicate every second. The predicate calls isSourceStillDistracting()
-- to determine whether the original window is still open AND still distracting.
-- When the user closes or navigates away from the bad tab, the overlay dismisses
-- itself automatically.
--
-- WINDOW IDENTITY
-- ---------------
-- A violation result carries both an AppleScript window id (string, from
-- AppleScript "id of front window") and a Hammerspoon window id (integer, from
-- hs.window:id()). The AppleScript id is used to re-query the exact window via
-- sourceWindowContextScript(); the Hammerspoon id is used as a fallback when
-- the browser is the focused app but AppleScript can't query by id.
--
-- enforce() (in init.lua) does NOT close the browser — it calls
-- browserFilter:enforce(result) which only logs the event. The visible
-- overlay serves as the deterrent.

local BrowserFilter = {}
BrowserFilter.__index = BrowserFilter

-- APPLESCRIPTS returns title, URL, and window id (linefeed-separated) for each
-- supported browser. Safari uses "name of current tab" (not "title") because
-- the AppleScript dictionary differs from Chromium-based browsers.
local APPLESCRIPTS = {
    ["Safari"] = [[
        tell application "Safari"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to name of current tab of front window
            set tabURL to URL of current tab of front window
            set windowId to id of front window as text
            return tabTitle & linefeed & tabURL & linefeed & windowId
        end tell
    ]],
    ["Google Chrome"] = [[
        tell application "Google Chrome"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            set windowId to id of front window as text
            return tabTitle & linefeed & tabURL & linefeed & windowId
        end tell
    ]],
    ["Brave Browser"] = [[
        tell application "Brave Browser"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            set windowId to id of front window as text
            return tabTitle & linefeed & tabURL & linefeed & windowId
        end tell
    ]],
    ["Arc"] = [[
        tell application "Arc"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            set windowId to id of front window as text
            return tabTitle & linefeed & tabURL & linefeed & windowId
        end tell
    ]],
    ["Microsoft Edge"] = [[
        tell application "Microsoft Edge"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            set windowId to id of front window as text
            return tabTitle & linefeed & tabURL & linefeed & windowId
        end tell
    ]],
    ["Opera"] = [[
        tell application "Opera"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            set windowId to id of front window as text
            return tabTitle & linefeed & tabURL & linefeed & windowId
        end tell
    ]],
    ["Vivaldi"] = [[
        tell application "Vivaldi"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            set windowId to id of front window as text
            return tabTitle & linefeed & tabURL & linefeed & windowId
        end tell
    ]],
}

-- hostFromURL extracts the bare hostname from an http(s) URL.
-- Returns nil for non-HTTP URLs (file://, about:, etc.) so domain rules
-- are never accidentally applied to local files.
local function hostFromURL(url)
    if type(url) ~= "string" then return nil end
    return url:match("^https?://([^/%?#]+)")
end

-- containsAny does case-insensitive substring search of value against needles.
-- Returns the first matching needle string (for use in reason messages).
local function containsAny(value, needles)
    local haystack = tostring(value or ""):lower()
    for _, needle in ipairs(needles or {}) do
        if haystack:find(tostring(needle):lower(), 1, true) then
            return needle
        end
    end
    return nil
end

-- appleScriptQuote wraps a Lua string in AppleScript double-quotes, escaping
-- backslashes and double-quotes. Used to safely inject app names and window ids
-- into dynamically constructed AppleScript strings.
local function appleScriptQuote(value)
    return '"' .. tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

-- sourceWindowCheckScript returns an AppleScript that tests whether the window
-- with the given AppleScript id still exists in the given app. Used by
-- isSourceWindowOpen() as the primary check before re-querying tab content.
local function sourceWindowCheckScript(appName, windowId)
    return [[
        tell application ]] .. appleScriptQuote(appName) .. [[
            if not running or (count of windows) = 0 then return false
            repeat with browserWindow in windows
                if (id of browserWindow as text) = ]] .. appleScriptQuote(windowId) .. [[ then return true
            end repeat
            return false
        end tell
    ]]
end

-- sourceWindowContextScript re-reads the title and URL of a specific window
-- (identified by its AppleScript id) so isSourceStillDistracting() can check
-- whether the user has navigated away from the offending page.
-- Safari requires a different property ("name of current tab") from Chromium browsers.
local function sourceWindowContextScript(appName, windowId)
    local quotedWindowId = appleScriptQuote(windowId)
    if appName == "Safari" then
        return [[
            tell application "Safari"
                if not running or (count of windows) = 0 then return ""
                repeat with browserWindow in windows
                    if (id of browserWindow as text) = ]] .. quotedWindowId .. [[ then
                        set tabTitle to name of current tab of browserWindow
                        set tabURL to URL of current tab of browserWindow
                        return tabTitle & linefeed & tabURL
                    end if
                end repeat
                return ""
            end tell
        ]]
    end

    return [[
        tell application ]] .. appleScriptQuote(appName) .. [[
            if not running or (count of windows) = 0 then return ""
            repeat with browserWindow in windows
                if (id of browserWindow as text) = ]] .. quotedWindowId .. [[ then
                    set tabTitle to title of active tab of browserWindow
                    set tabURL to URL of active tab of browserWindow
                    return tabTitle & linefeed & tabURL
                end if
            end repeat
            return ""
        end tell
    ]]
end

-- contextFromTitleAndURL parses the two-field (title\nurl) response from
-- sourceWindowContextScript into a context table. The fallback regex handles
-- a rare browser that returns "title | url" on a single line.
local function contextFromTitleAndURL(appName, result)
    if type(result) ~= "string" or result == "" then return nil end
    local title, url = result:match("^(.-)\n(https?://.-)$")
    if not title then
        title, url = result:match("^(.*) | (https?://.+)$")
    end
    return {
        app = appName,
        title = title or result,
        url = url,
        host = hostFromURL(url),
    }
end

function BrowserFilter.new(config, logger)
    local self = setmetatable({}, BrowserFilter)
    -- Store only config.browser so this module never accidentally reads unrelated config.
    self.config = config.browser or {}
    self.logger = logger
    return self
end

function BrowserFilter:title()
    return "Browser Filter"
end

function BrowserFilter:description()
    return "Checks the active browser tab, lets research-safe pages pass, and warns on distracting pages."
end

-- frontmostContext returns a context table for the active tab of the frontmost
-- browser, or nil if the frontmost app is not a supported browser.
-- The context table shape is:
--   { app, title, url, host, window_id, hs_window_id, window_title }
-- Both window_id (AppleScript string) and hs_window_id (Hammerspoon integer)
-- are stored so later calls can use whichever is available.
function BrowserFilter:frontmostContext()
    local app = hs.application.frontmostApplication()
    if not app then return nil end

    local appName = app:name()
    local focusedWindow = app:focusedWindow()
    local script = APPLESCRIPTS[appName]
    if not script then return nil end

    local ok, result = hs.osascript.applescript(script)
    if not ok or type(result) ~= "string" or result == "" then
        -- AppleScript failed; return a partial context so the classifier
        -- still gets the app name and window title.
        return {
            app = appName,
            title = focusedWindow and focusedWindow:title() or nil,
            url = nil, host = nil, window_id = nil,
            hs_window_id = focusedWindow and focusedWindow:id() or nil,
            window_title = focusedWindow and focusedWindow:title() or nil,
        }
    end

    local title, url, appleScriptWindowId = result:match("^(.-)\n(https?://.-)\n([^\n]+)$")
    if not title then
        title, url = result:match("^(.*) | (https?://.+)$")
    end
    return {
        app = appName,
        title = title or result,
        url = url,
        host = hostFromURL(url),
        window_id = appleScriptWindowId,
        hs_window_id = focusedWindow and focusedWindow:id() or nil,
        window_title = focusedWindow and focusedWindow:title() or nil,
    }
end

-- detectDistraction returns a violation table if the frontmost browser tab
-- is distracting, or nil if it is safe or no browser is frontmost.
-- Allowed domains win unconditionally (checked first) so research sites with
-- titles containing distraction keywords are never flagged.
function BrowserFilter:detectDistraction()
    local context = self:frontmostContext()
    if not context then return nil end

    if containsAny(context.host, self.config.allowed_domains) then
        return nil
    end

    local blockedDomain = containsAny(context.host, self.config.blocked_domains)
    if blockedDomain then
        return {
            kind = "blocked_domain",
            app = context.app, title = context.title, url = context.url,
            window_id = context.window_id, hs_window_id = context.hs_window_id,
            window_title = context.window_title,
            reason = "Distracting domain detected: " .. tostring(blockedDomain),
        }
    end

    local blockedTerm = containsAny(context.title, self.config.blocked_title_terms)
    if blockedTerm then
        return {
            kind = "blocked_title",
            app = context.app, title = context.title, url = context.url,
            window_id = context.window_id, hs_window_id = context.hs_window_id,
            window_title = context.window_title,
            reason = "Distracting tab title detected: " .. tostring(blockedTerm),
        }
    end

    return nil
end

-- _contextIsDistracting tests whether a context table (from sourceWindowContextScript
-- or frontmostContext) still counts as distracting, using the same violation
-- kind as the original detection (so a title-only violation isn't later
-- re-evaluated against domain rules alone).
function BrowserFilter:_contextIsDistracting(context, sourceKind)
    if not context then return false end
    if containsAny(context.host, self.config.allowed_domains) then return false end
    if sourceKind == "blocked_domain" then
        return containsAny(context.host, self.config.blocked_domains) ~= nil
    end
    if sourceKind == "blocked_title" then
        return containsAny(context.title, self.config.blocked_title_terms) ~= nil
    end
    return containsAny(context.host, self.config.blocked_domains) ~= nil
        or containsAny(context.title, self.config.blocked_title_terms) ~= nil
end

-- isSourceWindowOpen returns true if the window that triggered the original
-- violation still exists. Tries AppleScript window-id lookup first (most
-- reliable), then falls back to Hammerspoon window enumeration.
function BrowserFilter:isSourceWindowOpen(result)
    if not result or not result.app then return false end

    if result.window_id then
        local ok, isOpen = hs.osascript.applescript(sourceWindowCheckScript(result.app, result.window_id))
        if ok then return isOpen == true end
    end

    local app = hs.application.get(result.app)
    if not app then return false end

    local targetWindowId = result.hs_window_id
    local targetWindowTitle = result.window_title
    for _, window in ipairs(app:allWindows() or {}) do
        if targetWindowId and window:id() == targetWindowId then return true end
        if not targetWindowId and targetWindowTitle and window:title() == targetWindowTitle then return true end
    end

    return false
end

-- isSourceStillDistracting is the activePredicate used by showInterventionWhile().
-- It is called once per second by Overlay:_refresh(). Returns false as soon as
-- the original window is closed or the user navigates to a non-distracting page,
-- which causes the overlay to auto-dismiss.
-- If the window is open but AppleScript cannot re-query it, the function
-- conservatively returns true to keep the overlay visible.
function BrowserFilter:isSourceStillDistracting(result)
    if not self:isSourceWindowOpen(result) then return false end

    if result.window_id then
        local ok, sourceContext = hs.osascript.applescript(sourceWindowContextScript(result.app, result.window_id))
        if ok then
            return self:_contextIsDistracting(contextFromTitleAndURL(result.app, sourceContext), result.kind)
        end
    end

    local currentContext = self:frontmostContext()
    if currentContext and result.hs_window_id and currentContext.hs_window_id == result.hs_window_id then
        return self:_contextIsDistracting(currentContext, result.kind)
    end

    -- Cannot determine current state — assume still distracting (conservative).
    return true
end

-- enforce() logs the browser violation. The browser is intentionally NOT closed
-- here because the user needs to see and close the distracting tab themselves.
-- The red warning overlay (shown by handleViolation in init.lua) provides the
-- visual deterrent.
function BrowserFilter:enforce(result)
    if not result then return end
    self.logger:marker("browser distraction app=" .. tostring(result.app) .. " url=" .. tostring(result.url or ""))
end

function BrowserFilter:statusSummary()
    local context = self:frontmostContext()
    if not context then return "No supported browser in front" end
    if context.host then return tostring(context.app) .. ": " .. tostring(context.host) end
    return tostring(context.app) .. ": tab info unavailable"
end

return BrowserFilter
