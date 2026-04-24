-- Browser filtering is the context-aware web layer of enforcement.
-- It reads the frontmost browser tab, checks whether the current page is
-- research-safe or distracting, and reports clear violations.
local BrowserFilter = {}
BrowserFilter.__index = BrowserFilter

-- Each supported browser gets a tiny AppleScript snippet that returns the
-- active tab title, URL, and front-window id on separate lines.
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

local function hostFromURL(url)
    -- Extract the host so config rules can match domains cleanly.
    if type(url) ~= "string" then
        return nil
    end
    return url:match("^https?://([^/%?#]+)")
end

local function containsAny(value, needles)
    -- Shared substring matcher used for both domains and title keywords.
    local haystack = tostring(value or ""):lower()
    for _, needle in ipairs(needles or {}) do
        if haystack:find(tostring(needle):lower(), 1, true) then
            return needle
        end
    end
    return nil
end

local function appleScriptQuote(value)
    return '"' .. tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

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

local function contextFromTitleAndURL(appName, result)
    if type(result) ~= "string" or result == "" then
        return nil
    end

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

function BrowserFilter:frontmostContext()
    -- If the frontmost app is not a supported browser, the browser filter has
    -- no opinion and returns nil.
    local app = hs.application.frontmostApplication()
    if not app then
        return nil
    end

    local appName = app:name()
    local focusedWindow = app:focusedWindow()
    local script = APPLESCRIPTS[appName]
    if not script then
        return nil
    end

    -- If AppleScript fails, fall back to the window title so the rest of the
    -- pipeline still gets some context.
    local ok, result = hs.osascript.applescript(script)
    if not ok or type(result) ~= "string" or result == "" then
        return {
            app = appName,
            title = focusedWindow and focusedWindow:title() or nil,
            url = nil,
            host = nil,
            window_id = nil,
            hs_window_id = focusedWindow and focusedWindow:id() or nil,
            window_title = focusedWindow and focusedWindow:title() or nil,
        }
    end

    -- Build a compact context object that can be logged or classified later.
    local title, url, appleScriptWindowId = result:match("^(.-)\n(https?://.-)\n([^\n]+)$")
    if not title then
        title, url = result:match("^(.*) | (https?://.+)$")
    end
    local resolvedTitle = title or result
    return {
        app = appName,
        title = resolvedTitle,
        url = url,
        host = hostFromURL(url),
        window_id = appleScriptWindowId,
        hs_window_id = focusedWindow and focusedWindow:id() or nil,
        window_title = focusedWindow and focusedWindow:title() or nil,
    }
end

function BrowserFilter:detectDistraction()
    -- The rule order matters: allowed domains win first so research pages are
    -- not accidentally blocked by broad title keywords.
    local context = self:frontmostContext()
    if not context then
        return nil
    end

    local allowedMatch = containsAny(context.host, self.config.allowed_domains)
    if allowedMatch then
        return nil
    end

    -- A blocked domain is a direct and high-confidence browser violation.
    local blockedDomain = containsAny(context.host, self.config.blocked_domains)
    if blockedDomain then
        return {
            kind = "blocked_domain",
            app = context.app,
            title = context.title,
            url = context.url,
            window_id = context.window_id,
            hs_window_id = context.hs_window_id,
            window_title = context.window_title,
            reason = "Distracting domain detected: " .. tostring(blockedDomain),
        }
    end

    -- Title keywords catch distracting pages that live on mixed-use domains.
    local blockedTerm = containsAny(context.title, self.config.blocked_title_terms)
    if blockedTerm then
        return {
            kind = "blocked_title",
            app = context.app,
            title = context.title,
            url = context.url,
            window_id = context.window_id,
            hs_window_id = context.hs_window_id,
            window_title = context.window_title,
            reason = "Distracting tab title detected: " .. tostring(blockedTerm),
        }
    end

    return nil
end

function BrowserFilter:_contextIsDistracting(context, sourceKind)
    if not context then
        return false
    end

    local allowedMatch = containsAny(context.host, self.config.allowed_domains)
    if allowedMatch then
        return false
    end

    if sourceKind == "blocked_domain" then
        return containsAny(context.host, self.config.blocked_domains) ~= nil
    end
    if sourceKind == "blocked_title" then
        return containsAny(context.title, self.config.blocked_title_terms) ~= nil
    end

    return containsAny(context.host, self.config.blocked_domains) ~= nil
        or containsAny(context.title, self.config.blocked_title_terms) ~= nil
end

function BrowserFilter:isSourceWindowOpen(result)
    if not result or not result.app then
        return false
    end

    if result.window_id then
        local ok, isOpen = hs.osascript.applescript(sourceWindowCheckScript(result.app, result.window_id))
        if ok then
            return isOpen == true
        end
    end

    local app = hs.application.get(result.app)
    if not app then
        return false
    end

    local targetWindowId = result.hs_window_id
    local targetWindowTitle = result.window_title
    for _, window in ipairs(app:allWindows() or {}) do
        if targetWindowId and window:id() == targetWindowId then
            return true
        end
        if not targetWindowId and targetWindowTitle and window:title() == targetWindowTitle then
            return true
        end
    end

    return false
end

function BrowserFilter:isSourceStillDistracting(result)
    if not self:isSourceWindowOpen(result) then
        return false
    end

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

    return true
end

function BrowserFilter:enforce(result)
    if not result then
        return
    end
    -- Browser violations are handled by the red warning overlay. Keep the
    -- browser visible so the user can close the triggering tab/window.
    self.logger:marker("browser distraction app=" .. tostring(result.app) .. " url=" .. tostring(result.url or ""))
end

function BrowserFilter:statusSummary()
    local context = self:frontmostContext()
    if not context then
        return "No supported browser in front"
    end
    if context.host then
        return tostring(context.app) .. ": " .. tostring(context.host)
    end
    return tostring(context.app) .. ": tab info unavailable"
end

return BrowserFilter
