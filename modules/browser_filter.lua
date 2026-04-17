-- Browser filtering is the context-aware web layer of enforcement.
-- It reads the frontmost browser tab, checks whether the current page is
-- research-safe or distracting, and hides the browser on clear violations.
local BrowserFilter = {}
BrowserFilter.__index = BrowserFilter

-- Each supported browser gets a tiny AppleScript snippet that returns
-- "title | url" for the active tab of the front window.
local APPLESCRIPTS = {
    ["Safari"] = [[
        tell application "Safari"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to name of current tab of front window
            set tabURL to URL of current tab of front window
            return tabTitle & " | " & tabURL
        end tell
    ]],
    ["Google Chrome"] = [[
        tell application "Google Chrome"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            return tabTitle & " | " & tabURL
        end tell
    ]],
    ["Brave Browser"] = [[
        tell application "Brave Browser"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            return tabTitle & " | " & tabURL
        end tell
    ]],
    ["Arc"] = [[
        tell application "Arc"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            return tabTitle & " | " & tabURL
        end tell
    ]],
    ["Microsoft Edge"] = [[
        tell application "Microsoft Edge"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            return tabTitle & " | " & tabURL
        end tell
    ]],
    ["Opera"] = [[
        tell application "Opera"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            return tabTitle & " | " & tabURL
        end tell
    ]],
    ["Vivaldi"] = [[
        tell application "Vivaldi"
            if not running or (count of windows) = 0 then return ""
            set tabTitle to title of active tab of front window
            set tabURL to URL of active tab of front window
            return tabTitle & " | " & tabURL
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

function BrowserFilter.new(config, logger)
    local self = setmetatable({}, BrowserFilter)
    self.config = config.browser or {}
    self.logger = logger
    return self
end

function BrowserFilter:frontmostContext()
    -- If the frontmost app is not a supported browser, the browser filter has
    -- no opinion and returns nil.
    local app = hs.application.frontmostApplication()
    if not app then
        return nil
    end

    local appName = app:name()
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
            title = app:focusedWindow() and app:focusedWindow():title() or nil,
            url = nil,
            host = nil,
        }
    end

    -- Build a compact context object that can be logged or classified later.
    local title, url = result:match("^(.*) | (https?://.+)$")
    local resolvedTitle = title or result
    return {
        app = appName,
        title = resolvedTitle,
        url = url,
        host = hostFromURL(url),
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
            reason = "Distracting tab title detected: " .. tostring(blockedTerm),
        }
    end

    return nil
end

function BrowserFilter:enforce(result)
    if not result then
        return
    end
    -- Hiding the app is a lighter response than force-killing the browser, and
    -- usually enough to break the distraction loop.
    local app = hs.application.get(result.app)
    if app then
        app:hide()
    end
    self.logger:marker("browser distraction app=" .. tostring(result.app) .. " url=" .. tostring(result.url or ""))
end

return BrowserFilter
