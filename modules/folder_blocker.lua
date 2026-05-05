-- folder_blocker.lua — Folder path enforcement and approval system.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- FolderBlocker monitors window titles (VS Code, Claude, editors) for folder paths.
-- When a new folder is detected during BLOCK mode and fullscreen, it shows a Y/N
-- prompt: "Is this folder related to work?"
--
-- YES → folder is added to allowed_folders list in the state file
-- NO  → the frontmost app is killed immediately (similar to AppBlocker)
--
-- Terminal cd commands are gated separately via terminal-command-guard.zsh,
-- which reads the allowed_folders state file.
--
-- STATE FILE FORMAT
-- -----------------
-- Each line is one allowed folder path. Written/read by both Hammerspoon and shell.
-- Example:
--   ~/projects/research
--   ~/work
--
-- WINDOW TITLE PARSING
-- --------------------
-- VS Code: "filename — /path/to/folder [VS Code]"
-- Claude:  "Claude" or may show project/folder in title
-- Editors: Varies by app; regex patterns can be extended in parsePathFromTitle()

local FolderBlocker = {}
FolderBlocker.__index = FolderBlocker

-- Shell-escape a string for safe use in shell commands
local function shellEscape(str)
    return "'" .. tostring(str):gsub("'", "'\\''") .. "'"
end

-- Count entries in a Lua table
local function tableCount(tbl)
    local count = 0
    for _, _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Load allowed folders from state file (one path per line)
local function loadAllowedFolders(statePath)
    local allowed = {}
    if not statePath then return allowed end

    local file = io.open(statePath, "r")
    if not file then return allowed end

    for line in file:lines() do
        line = line:gsub("^%s+|%s+$", "")  -- trim
        if line ~= "" then
            allowed[line] = true
        end
    end
    file:close()
    return allowed
end

-- Save allowed folders to state file (one path per line)
local function saveAllowedFolders(statePath, allowed)
    if not statePath then return false end

    local file = io.open(statePath, "w")
    if not file then return false end

    for path, _ in pairs(allowed) do
        file:write(path .. "\n")
    end
    file:close()
    return true
end

-- Normalize a path: expand ~, remove trailing slashes, resolve symlinks if possible
local function normalizePath(path)
    if not path or path == "" then return nil end

    -- Expand tilde
    if path:sub(1, 1) == "~" then
        path = os.getenv("HOME") .. path:sub(2)
    end

    -- Remove trailing slash
    path = path:gsub("/$", "")

    -- Resolve symlinks using readlink
    local success, resolved = hs.execute("readlink -f " .. shellEscape(path), true)
    if success and type(resolved) == "string" then
        resolved = resolved:gsub("\n$", "")  -- strip newline
        return resolved
    end

    return path
end

-- Check if a given path is within an allowed folder
local function isPathAllowed(pathToCheck, allowedFolders)
    if not pathToCheck then return false end

    local normalized = normalizePath(pathToCheck)
    if not normalized then return false end

    for allowedPath, _ in pairs(allowedFolders) do
        -- Direct match or path is under allowed folder
        if normalized == allowedPath or normalized:sub(1, #allowedPath + 1) == allowedPath .. "/" then
            return true
        end
    end
    return false
end

-- APPLESCRIPTS for querying app workspace paths
local APPLESCRIPTS = {
    ["Visual Studio Code"] = [[
        tell application "Visual Studio Code"
            if not running then return ""
            return ""
        end tell
    ]],
    ["Code"] = [[
        tell application "Code"
            if not running then return ""
            return ""
        end tell
    ]],
}

-- queryAppOpenedFolders uses `lsof` to find folders an app has open
local function queryAppOpenedFolders(appName)
    -- Get the bundle ID for the app
    local app = hs.application.get(appName)
    if not app then return {} end

    local bundleId = app:bundleID()
    if not bundleId then return {} end

    -- Use lsof to find open files/directories
    local cmd = string.format(
        "lsof -c '%s' 2>/dev/null | awk '$4 ~ /^[0-9]+[a-z]$/ && $9 ~ /^\\// {print $9}' | sort -u | grep -E '^/[^/]+' | head -20",
        appName:gsub("'", "'\\''")
    )

    local success, output = hs.execute(cmd, true)
    if not success or not output or type(output) ~= "string" then return {} end

    local folders = {}
    for line in output:gmatch("[^\n]+") do
        line = line:gsub("^%s+|%s+$", "")  -- trim
        if line ~= "" and line:sub(1, 1) == "/" then
            table.insert(folders, line)
        end
    end
    return folders
end

-- Extract folder path from window title based on app name
-- Patterns can be extended here for more apps
local function parsePathFromTitle(appName, windowTitle)
    if not windowTitle or windowTitle == "" then return nil end

    -- VS Code: Multiple formats:
    --   1. "filename — /path/to/folder [VS Code]"  (workspace)
    --   2. "filename — foldername"                  (single folder)
    --   3. "workspacename — /path"                  (workspace folder)
    if appName == "Visual Studio Code" or appName == "Code" then
        -- Try format 1: path with [VS Code] suffix
        local path = windowTitle:match("%s—%s(.-)%s%[VS")
        if path then return path end

        -- Try format 2: extract absolute path (starts with /)
        path = windowTitle:match("(/[^%s]+)")
        if path then return path:gsub("%s+$", "") end

        -- Try format 3: extract path after " — " if it looks like a path or folder
        path = windowTitle:match("%s—%s(.+)$")
        if path then
            path = path:gsub("%s+$", "")  -- trim trailing space
            -- If it starts with /, it's a full path
            if path:sub(1, 1) == "/" then
                return path
            end
            -- Otherwise, it's a folder name - try to find it in common locations
            -- This is a fallback; ideally we'd use the full path from VS Code
            local home = os.getenv("HOME")
            local candidates = {
                home .. "/projects/" .. path,
                home .. "/work/" .. path,
                home .. "/" .. path,
                "/" .. path,
            }
            for _, candidate in ipairs(candidates) do
                if hs.fs.attributes(candidate) then
                    return candidate
                end
            end
        end
    end

    -- Xcode: "ProjectName — /path/to/folder"
    if appName == "Xcode" then
        local path = windowTitle:match("%s—%s(.+)$")
        if path then return path:gsub("%s+$", "") end
    end

    -- PyCharm, IntelliJ, etc: "[ProjectName] — /path/to/folder"
    if appName:match("PyCharm") or appName:match("IntelliJ") then
        local path = windowTitle:match("%]%s—%s(.+)$")
        if path then return path:gsub("%s+$", "") end
    end

    return nil
end

function FolderBlocker.new(config, logger)
    local self = setmetatable({}, FolderBlocker)
    self.config = config
    self.logger = logger
    self.allowedFolders = {}
    self.lastSeenPath = nil
    self.lastPathCheckTime = 0
    self.statePath = (config.user and config.user.allowed_folders_state_path)
        or (os.getenv("HOME") .. "/.hammerspoon/allowed-folders.state")
    self:reloadAllowedFolders()
    return self
end

function FolderBlocker:title()
    return "Folder Blocker"
end

function FolderBlocker:description()
    return "Monitors folder opens and requires approval for non-work paths."
end

-- Reload allowed folders from state file (call after state file changes)
function FolderBlocker:reloadAllowedFolders()
    self.allowedFolders = loadAllowedFolders(self.statePath)
    self.logger:marker("folder_blocker reloaded allowed_folders count=" .. tostring(tableCount(self.allowedFolders)))
end

-- addAllowedFolder adds a folder to the allowed list and persists it
function FolderBlocker:addAllowedFolder(path)
    local normalized = normalizePath(path)
    if not normalized then return false end

    self.allowedFolders[normalized] = true
    local ok = saveAllowedFolders(self.statePath, self.allowedFolders)
    if ok then
        self.logger:marker("folder_blocker folder_approved path=" .. tostring(normalized))
    else
        self.logger:marker("folder_blocker folder_approval_save_failed path=" .. tostring(normalized))
    end
    return ok
end

-- removeAllowedFolder removes a folder from the allowed list
function FolderBlocker:removeAllowedFolder(path)
    local normalized = normalizePath(path)
    if not normalized then return false end

    self.allowedFolders[normalized] = nil
    local ok = saveAllowedFolders(self.statePath, self.allowedFolders)
    if ok then
        self.logger:marker("folder_blocker folder_revoked path=" .. tostring(normalized))
    else
        self.logger:marker("folder_blocker folder_revoke_save_failed path=" .. tostring(normalized))
    end
    return ok
end

-- detectNewFolder checks if the frontmost app has a new folder
-- Uses lsof to find actually open folders (most reliable)
-- Falls back to window title parsing
-- Returns the folder path if new and not yet seen, nil otherwise
function FolderBlocker:detectNewFolder()
    local app = hs.application.frontmostApplication()
    if not app then return nil end

    local appName = app:name()
    local focusedWindow = app:focusedWindow()
    if not focusedWindow then return nil end

    -- Try lsof first (most reliable - shows actual open folders)
    local openFolders = queryAppOpenedFolders(appName)
    local path = nil

    if #openFolders > 0 then
        -- Take the first "real" project folder (skip system paths)
        for _, folder in ipairs(openFolders) do
            if not folder:match("^/System") and not folder:match("^/Library") and not folder:match("^/var") then
                path = folder
                break
            end
        end
    end

    -- Fall back to window title parsing
    if not path then
        local windowTitle = focusedWindow:title()
        path = parsePathFromTitle(appName, windowTitle)
    end

    if not path then return nil end

    -- Normalize and check if we've seen this path before (debounce)
    local normalized = normalizePath(path)
    if not normalized then return nil end

    local now = hs.timer.secondsSinceEpoch()

    -- Debounce: don't re-trigger for the same path within 2 seconds
    if self.lastSeenPath == normalized and (now - self.lastPathCheckTime) < 2 then
        return nil
    end

    self.lastSeenPath = normalized
    self.lastPathCheckTime = now

    return normalized
end

-- isPathAllowed returns true if the given path is in the allowed folders list
function FolderBlocker:isPathAllowed(path)
    return isPathAllowed(path, self.allowedFolders)
end

-- scanOpenWindowPaths returns a list of all open windows with parsed paths
function FolderBlocker:scanOpenWindowPaths()
    local results = {}
    local apps = hs.application.runningApplications()

    for _, app in ipairs(apps) do
        local appName = app:name()
        local windows = app:allWindows()

        for _, window in ipairs(windows) do
            local title = window:title()
            if title and title ~= "" then
                local path = parsePathFromTitle(appName, title)
                table.insert(results, {
                    app = appName,
                    title = title,
                    path = path,
                    windowId = window:id(),
                    isAllowed = path and self:isPathAllowed(path) or nil,
                })
            end
        end
    end

    return results
end

-- printWindowPaths prints a human-readable report of open windows and paths
function FolderBlocker:printWindowPaths()
    local results = self:scanOpenWindowPaths()
    print("\n" .. string.rep("=", 80))
    print("OPEN WINDOWS WITH DETECTED PATHS")
    print(string.rep("=", 80) .. "\n")

    if #results == 0 then
        print("No windows found.\n")
        return
    end

    for i, item in ipairs(results) do
        print(string.format("[%d] %s", i, item.app))
        print(string.format("    Title: %s", item.title))
        if item.path then
            local status = item.isAllowed and "✓ ALLOWED" or "✗ BLOCKED"
            print(string.format("    Path: %s (%s)", item.path, status))
        else
            print("    Path: (not detected)")
        end
        print(string.format("    Window ID: %d\n", item.windowId))
    end

    -- Summary
    local withPaths = 0
    local allowed = 0
    local blocked = 0
    for _, item in ipairs(results) do
        if item.path then
            withPaths = withPaths + 1
            if item.isAllowed then
                allowed = allowed + 1
            else
                blocked = blocked + 1
            end
        end
    end

    print(string.rep("=", 80))
    print(string.format("Summary: %d windows | %d with paths | %d allowed | %d blocked",
        #results, withPaths, allowed, blocked))
    print(string.rep("=", 80) .. "\n")
end

-- statusSummary returns a brief status for the menu
function FolderBlocker:statusSummary()
    local count = tableCount(self.allowedFolders)
    return string.format("%d allowed folders", count)
end

return FolderBlocker
