-- file_path_blocker.lua — Strict document path enforcement during BLOCK mode.
--
-- This module scans Accessibility document attributes for open windows across
-- running apps. Known allowed paths pass, known blocked paths are killed, and
-- unknown paths can be routed through a one-time approval prompt in init.lua.

local FilePathBlocker = {}
FilePathBlocker.__index = FilePathBlocker

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function tableCount(tbl)
    local count = 0
    for _, _ in pairs(tbl or {}) do
        count = count + 1
    end
    return count
end

local function decodeFileURL(value)
    if type(value) ~= "string" or value == "" then return nil end
    if not value:match("^file://") then return value end
    local path = value:gsub("^file://localhost", "")
    path = path:gsub("^file://", "")
    path = path:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return path
end

local function expandPath(path)
    if type(path) ~= "string" or path == "" then return nil end
    if path:sub(1, 1) == "~" then
        return (os.getenv("HOME") or "") .. path:sub(2)
    end
    return path
end

local function normalizePath(path)
    path = expandPath(trim(path))
    if not path or path == "" then return nil end
    path = path:gsub("/+$", "")
    if path == "" then return "/" end
    return path
end

local function loadPathSet(path)
    local values = {}
    local file = path and io.open(path, "r") or nil
    if not file then return values end
    for line in file:lines() do
        local normalized = normalizePath(line)
        if normalized then
            values[normalized] = true
        end
    end
    file:close()
    return values
end

local function displayPath(path)
    local home = os.getenv("HOME") or ""
    if home ~= "" and path == home then
        return "~"
    end
    if home ~= "" and path:sub(1, #home + 1) == home .. "/" then
        return "~" .. path:sub(#home + 1)
    end
    return path
end

local function savePathSet(path, values)
    if not path then return false end
    local file = io.open(path, "w")
    if not file then return false end
    local sorted = {}
    for value, _ in pairs(values or {}) do
        table.insert(sorted, value)
    end
    table.sort(sorted)
    for _, value in ipairs(sorted) do
        file:write(displayPath(value) .. "\n")
    end
    file:close()
    return true
end

local function listContains(list, value)
    for _, item in ipairs(list or {}) do
        if value == item then return true end
    end
    return false
end

local function pathIsUnder(path, root)
    if not path or not root then return false end
    if path == root then return true end
    if root == "/" then return true end
    return path:sub(1, #root + 1) == root .. "/"
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function commandOutputLines(command)
    local output, ok = hs.execute(command, true)
    if not ok or type(output) ~= "string" then return {} end
    local lines = {}
    for line in output:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    return lines
end

function FilePathBlocker.new(config, logger)
    local self = setmetatable({}, FilePathBlocker)
    self.config = config
    self.logger = logger
    self.ax = require("hs.axuielement")
    self.allowedPaths = {}
    self.exactAllowedPaths = {}
    self.blockedPaths = {}
    self.exactBlockedPaths = {}
    self.lastViolationKey = nil
    self.lastViolationAt = 0
    self.lastUnknownKey = nil
    self.lastUnknownAt = 0
    self:reloadAllowedPaths()
    return self
end

function FilePathBlocker:title()
    return "File Path Blocker"
end

function FilePathBlocker:description()
    return "Asks about unknown opened paths, allows approved paths, and kills apps that access denied paths during BLOCK mode."
end

function FilePathBlocker:_settings()
    return self.config.file_path_blocker or {}
end

function FilePathBlocker:reloadAllowedPaths()
    local settings = self:_settings()
    local allowed = {}
    local exactAllowed = {}
    local blocked = {}
    local exactBlocked = {}

    for _, path in ipairs(settings.allowed_paths or {}) do
        local normalized = normalizePath(path)
        if normalized then
            allowed[normalized] = true
        end
    end

    for _, path in ipairs(settings.exact_allowed_paths or {}) do
        local normalized = normalizePath(path)
        if normalized then
            exactAllowed[normalized] = true
        end
    end

    for _, path in ipairs(settings.blocked_paths or {}) do
        local normalized = normalizePath(path)
        if normalized then
            blocked[normalized] = true
        end
    end

    for _, path in ipairs(settings.exact_blocked_paths or {}) do
        local normalized = normalizePath(path)
        if normalized then
            exactBlocked[normalized] = true
        end
    end

    if settings.include_allowed_folders_state ~= false then
        local statePath = (self.config.user and self.config.user.allowed_folders_state_path)
            or ((os.getenv("HOME") or "") .. "/.hammerspoon/allowed-folders.state")
        for path, _ in pairs(loadPathSet(statePath)) do
            allowed[path] = true
        end
    end

    if settings.include_exact_allowed_paths_state ~= false then
        local statePath = (self.config.user and self.config.user.exact_allowed_paths_state_path)
            or ((os.getenv("HOME") or "") .. "/.hammerspoon/exact-allowed-paths.state")
        for path, _ in pairs(loadPathSet(statePath)) do
            exactAllowed[path] = true
        end
    end

    if settings.include_blocked_paths_state ~= false then
        local statePath = (self.config.user and self.config.user.blocked_paths_state_path)
            or ((os.getenv("HOME") or "") .. "/.hammerspoon/blocked-paths.state")
        for path, _ in pairs(loadPathSet(statePath)) do
            blocked[path] = true
        end
    end

    if settings.include_exact_blocked_paths_state ~= false then
        local statePath = (self.config.user and self.config.user.exact_blocked_paths_state_path)
            or ((os.getenv("HOME") or "") .. "/.hammerspoon/exact-blocked-paths.state")
        for path, _ in pairs(loadPathSet(statePath)) do
            exactBlocked[path] = true
        end
    end

    self.allowedPaths = allowed
    self.exactAllowedPaths = exactAllowed
    self.blockedPaths = blocked
    self.exactBlockedPaths = exactBlocked
    self.logger:marker(
        "file_path_blocker reloaded allowed_paths count=" .. tostring(tableCount(self.allowedPaths))
        .. " exact_allowed_paths count=" .. tostring(tableCount(self.exactAllowedPaths))
        .. " blocked_paths count=" .. tostring(tableCount(self.blockedPaths))
        .. " exact_blocked_paths count=" .. tostring(tableCount(self.exactBlockedPaths))
    )
end

function FilePathBlocker:isEnabled()
    return self:_settings().enabled ~= false
end

function FilePathBlocker:isAppIgnored(appName, bundleID)
    local settings = self:_settings()
    return listContains(settings.ignored_apps, appName) or listContains(settings.ignored_bundle_ids, bundleID)
end

function FilePathBlocker:isAppMonitored(appName, bundleID)
    local settings = self:_settings()
    local apps = settings.monitored_apps or {}
    local bundleIDs = settings.monitored_bundle_ids or {}
    if #apps == 0 and #bundleIDs == 0 then
        return true
    end
    return listContains(apps, appName) or listContains(bundleIDs, bundleID)
end

function FilePathBlocker:isPathAllowed(path)
    local normalized = normalizePath(path)
    if not normalized then return true end
    if self.exactAllowedPaths and self.exactAllowedPaths[normalized] then
        return true
    end
    for allowedPath, _ in pairs(self.allowedPaths or {}) do
        if pathIsUnder(normalized, allowedPath) then
            return true
        end
    end
    return false
end

function FilePathBlocker:isPathBlocked(path)
    local normalized = normalizePath(path)
    if not normalized then return false end
    if self.exactBlockedPaths and self.exactBlockedPaths[normalized] then
        return true
    end
    for blockedPath, _ in pairs(self.blockedPaths or {}) do
        if pathIsUnder(normalized, blockedPath) then
            return true
        end
    end
    return false
end

function FilePathBlocker:pathStatus(path)
    if self:isPathAllowed(path) then return "allowed" end
    if self:isPathBlocked(path) then return "blocked" end
    return "unknown"
end

function FilePathBlocker:_pathResult(appName, bundleID, pid, title, path, source)
    local status = self:pathStatus(path)
    return {
        app = appName,
        bundle_id = bundleID,
        pid = pid,
        title = title,
        path = path,
        source = source,
        status = status,
        allowed = status == "allowed",
        blocked = status == "blocked",
        unknown = status == "unknown",
    }
end

function FilePathBlocker:_documentPathForWindow(windowElement)
    for _, attr in ipairs({ "AXDocument", "AXFilename", "AXURL" }) do
        local ok, value = pcall(function()
            return windowElement:attributeValue(attr)
        end)
        local path = ok and normalizePath(decodeFileURL(value)) or nil
        if path and path:sub(1, 1) == "/" then
            return path
        end
    end
    return nil
end

function FilePathBlocker:_finderWindowPaths()
    local script = [[
        tell application "Finder"
            set output to ""
            repeat with w in Finder windows
                try
                    set output to output & POSIX path of (target of w as alias) & linefeed
                end try
            end repeat
            return output
        end tell
    ]]
    return commandOutputLines("osascript -e " .. shellQuote(script))
end

function FilePathBlocker:_terminalWindowPath(appName, window)
    local title = window and window:title()
    local path = self:_documentPathForWindow(self.ax.windowElement(window))
    if path then return path end
    if title and title:match("%s—%s~%s—") then
        return os.getenv("HOME")
    end
    return nil
end

function FilePathBlocker:scanOpenFilePaths()
    local results = {}
    if not self:isEnabled() then return results end

    for _, app in ipairs(hs.application.runningApplications()) do
        local appName = app:name()
        local bundleID = app:bundleID()
        if appName and not self:isAppIgnored(appName, bundleID) and self:isAppMonitored(appName, bundleID) then
            if appName == "Finder" then
                for _, path in ipairs(self:_finderWindowPaths()) do
                    local normalized = normalizePath(path)
                    if normalized then
                        table.insert(results, self:_pathResult(appName, bundleID, app:pid(), "Finder window", normalized, "finder"))
                    end
                end
            end
            for _, window in ipairs(app:allWindows() or {}) do
                local windowElement = self.ax.windowElement(window)
                if windowElement then
                    local title = window:title()
                    if not title or title == "" then
                        pcall(function()
                            title = windowElement:attributeValue("AXTitle")
                        end)
                    end
                    local path = nil
                    if appName == "Terminal" or appName == "iTerm2" then
                        path = self:_terminalWindowPath(appName, window)
                    else
                        path = self:_documentPathForWindow(windowElement)
                    end
                    if path then
                        table.insert(results, self:_pathResult(appName, bundleID, app:pid(), title, path, "window"))
                    end
                end
            end
        end
    end

    return results
end

function FilePathBlocker:_processMatches(settings, command)
    local lower = tostring(command or ""):lower()
    for _, pattern in ipairs(settings.monitored_process_patterns or {}) do
        if lower:find(tostring(pattern):lower(), 1, true) then
            return true
        end
    end
    return false
end

function FilePathBlocker:_pathMatchesPrefixList(path, prefixes)
    if not prefixes or #prefixes == 0 then
        return true
    end
    for _, prefix in ipairs(prefixes) do
        local normalized = normalizePath(prefix)
        if normalized and pathIsUnder(path, normalized) then
            return true
        end
    end
    return false
end

function FilePathBlocker:_processOpenPaths(pid)
    local settings = self:_settings()
    local paths = {}
    for _, line in ipairs(commandOutputLines("lsof -Fn -p " .. tostring(pid) .. " 2>/dev/null")) do
        local path = line:match("^n(.+)$")
        path = normalizePath(path)
        if path and path:sub(1, 1) == "/" and self:_pathMatchesPrefixList(path, settings.process_path_prefixes) then
            paths[path] = true
        end
    end
    return paths
end

function FilePathBlocker:scanHeadlessProcessPaths()
    local settings = self:_settings()
    local results = {}
    if not self:isEnabled() or #(settings.monitored_process_patterns or {}) == 0 then
        return results
    end

    local selfPid = tostring(hs.processInfo.processID)
    for _, line in ipairs(commandOutputLines("ps -axo pid=,args= 2>/dev/null")) do
        local pid, command = line:match("^%s*(%d+)%s+(.+)$")
        if pid and pid ~= selfPid and self:_processMatches(settings, command) then
            for path, _ in pairs(self:_processOpenPaths(pid)) do
                table.insert(results, {
                    app = command:match("([^/ ]+)$") or "process",
                    pid = tonumber(pid),
                    title = command,
                    path = path,
                    source = "process",
                    status = self:pathStatus(path),
                })
                results[#results].allowed = results[#results].status == "allowed"
                results[#results].blocked = results[#results].status == "blocked"
                results[#results].unknown = results[#results].status == "unknown"
            end
        end
    end

    return results
end

function FilePathBlocker:detectViolation()
    for _, item in ipairs(self:scanOpenFilePaths()) do
        if item.blocked == true then
            local key = tostring(item.bundle_id or item.app) .. "|" .. tostring(item.path)
            local now = hs.timer.secondsSinceEpoch()
            if self.lastViolationKey ~= key or (now - self.lastViolationAt) > 2 then
                self.lastViolationKey = key
                self.lastViolationAt = now
                item.reason = string.format(
                    "Disallowed file path opened by %s:\n%s",
                    tostring(item.app or "unknown app"),
                    tostring(item.path)
                )
                return item
            end
        end
    end
    for _, item in ipairs(self:scanHeadlessProcessPaths()) do
        if item.blocked == true then
            local key = "pid:" .. tostring(item.pid) .. "|" .. tostring(item.path)
            local now = hs.timer.secondsSinceEpoch()
            if self.lastViolationKey ~= key or (now - self.lastViolationAt) > 2 then
                self.lastViolationKey = key
                self.lastViolationAt = now
                item.reason = string.format(
                    "Disallowed file path accessed by %s:\n%s",
                    tostring(item.app or ("pid " .. tostring(item.pid))),
                    tostring(item.path)
                )
                return item
            end
        end
    end
    return nil
end

function FilePathBlocker:detectUnknownPath()
    for _, item in ipairs(self:scanOpenFilePaths()) do
        if item.unknown == true then
            local key = tostring(item.bundle_id or item.app) .. "|" .. tostring(item.path)
            local now = hs.timer.secondsSinceEpoch()
            if self.lastUnknownKey ~= key or (now - self.lastUnknownAt) > 10 then
                self.lastUnknownKey = key
                self.lastUnknownAt = now
                item.reason = string.format(
                    "New file path opened by %s:\n%s",
                    tostring(item.app or "unknown app"),
                    tostring(item.path)
                )
                return item
            end
        end
    end
    for _, item in ipairs(self:scanHeadlessProcessPaths()) do
        if item.unknown == true then
            local key = "pid:" .. tostring(item.pid) .. "|" .. tostring(item.path)
            local now = hs.timer.secondsSinceEpoch()
            if self.lastUnknownKey ~= key or (now - self.lastUnknownAt) > 10 then
                self.lastUnknownKey = key
                self.lastUnknownAt = now
                item.reason = string.format(
                    "New file path accessed by %s:\n%s",
                    tostring(item.app or ("pid " .. tostring(item.pid))),
                    tostring(item.path)
                )
                return item
            end
        end
    end
    return nil
end

function FilePathBlocker:_decisionIsRecursive(path)
    local mode = hs.fs.attributes(path, "mode")
    return mode == "directory"
end

function FilePathBlocker:_statePath(kind)
    local user = self.config.user or {}
    local home = os.getenv("HOME") or ""
    if kind == "allowed" then
        return user.allowed_folders_state_path or (home .. "/.hammerspoon/allowed-folders.state")
    elseif kind == "exactAllowed" then
        return user.exact_allowed_paths_state_path or (home .. "/.hammerspoon/exact-allowed-paths.state")
    elseif kind == "blocked" then
        return user.blocked_paths_state_path or (home .. "/.hammerspoon/blocked-paths.state")
    elseif kind == "exactBlocked" then
        return user.exact_blocked_paths_state_path or (home .. "/.hammerspoon/exact-blocked-paths.state")
    end
    return nil
end

function FilePathBlocker:approvePath(path)
    local normalized = normalizePath(path)
    if not normalized then return false end
    if self:_decisionIsRecursive(normalized) then
        self.allowedPaths[normalized] = true
        self.blockedPaths[normalized] = nil
        savePathSet(self:_statePath("allowed"), self.allowedPaths)
        savePathSet(self:_statePath("blocked"), self.blockedPaths)
    else
        self.exactAllowedPaths[normalized] = true
        self.exactBlockedPaths[normalized] = nil
        savePathSet(self:_statePath("exactAllowed"), self.exactAllowedPaths)
        savePathSet(self:_statePath("exactBlocked"), self.exactBlockedPaths)
    end
    self.logger:marker("file_path_blocker path_approved path=" .. tostring(normalized))
    return true
end

function FilePathBlocker:blockPath(path)
    local normalized = normalizePath(path)
    if not normalized then return false end
    if self:_decisionIsRecursive(normalized) then
        self.blockedPaths[normalized] = true
        self.allowedPaths[normalized] = nil
        savePathSet(self:_statePath("blocked"), self.blockedPaths)
        savePathSet(self:_statePath("allowed"), self.allowedPaths)
    else
        self.exactBlockedPaths[normalized] = true
        self.exactAllowedPaths[normalized] = nil
        savePathSet(self:_statePath("exactBlocked"), self.exactBlockedPaths)
        savePathSet(self:_statePath("exactAllowed"), self.exactAllowedPaths)
    end
    self.logger:marker("file_path_blocker path_blocked path=" .. tostring(normalized))
    return true
end

function FilePathBlocker:enforce(result)
    if not result then return end
    local killedAny = false
    if result.bundle_id then
        for _, app in ipairs(hs.application.applicationsForBundleID(result.bundle_id) or {}) do
            app:kill9()
            killedAny = true
        end
    end
    if not killedAny and result.app then
        local app = hs.application.get(result.app)
        if app then app:kill9() end
    end
    if not killedAny and result.pid then
        hs.execute("kill -9 " .. tostring(result.pid) .. " 2>/dev/null", true)
    end
    self.logger:marker(
        "file_path_blocker killed app=" .. tostring(result.app)
        .. " path=" .. tostring(result.path)
    )
end

function FilePathBlocker:statusSummary()
    if not self:isEnabled() then
        return "disabled"
    end
    return string.format(
        "%d allowed roots, %d exact allowed, %d blocked roots, %d exact blocked",
        tableCount(self.allowedPaths),
        tableCount(self.exactAllowedPaths),
        tableCount(self.blockedPaths),
        tableCount(self.exactBlockedPaths)
    )
end

return FilePathBlocker
