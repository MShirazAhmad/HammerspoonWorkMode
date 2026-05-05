-- messages.lua — Editable user-facing string store.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- Messages provides a single source of truth for every string shown to the
-- user: overlay titles, button labels, shell terminal messages, and alert text.
-- All strings live in config/messages.yaml rather than being hardcoded across
-- modules, so the user can retranslate or rephrase without touching Lua code.
--
-- LOOKUP KEY FORMAT
-- -----------------
-- Keys use dot-separated notation that mirrors the YAML hierarchy:
--   terminal_guard.prompt.title  →  terminal_guard: { prompt: { title: "..." } }
-- The same key format is used in both Lua (messages:get("key")) and the shell
-- script (awk-based parser in terminal-command-guard.zsh) so both sides stay
-- in sync when messages.yaml is edited.
--
-- YAML SUPPORT
-- ------------
-- This module implements a minimal hand-rolled YAML reader (readMessagesYaml).
-- It supports only the subset used by this project:
--   • Nested scalar mappings (key: value)
--   • Inline comments (# text)
--   • Single- and double-quoted string values
--   • \n escape sequences inside values (expanded to real newlines)
-- It does NOT support lists, multi-line blocks, anchors, or other YAML features.
-- If the YAML file is missing or cannot be parsed, the module falls back to the
-- hardcoded `defaults` table below, so the system stays functional.
--
-- LOAD ORDER
-- ----------
-- Messages.new() first populates self.values from `defaults`, then overlays
-- values from the YAML file. This means:
--   1. All keys in `defaults` always have a value (YAML file is optional).
--   2. YAML values silently override defaults for matching keys.
--   3. Unknown YAML keys are stored but never looked up (harmless).
--
-- CONSUMERS
-- ---------
-- Hammerspoon side: overlay.lua, init.lua (alert text, log reasons)
-- Shell side: terminal-command-guard.zsh (reads the same YAML directly via awk)

local Messages = {}
Messages.__index = Messages

-- defaults provides fallback values for every key the system uses.
-- Edit config/messages.yaml to override any of these at runtime.
local defaults = {
    ["overlay.title"]                          = "RESEARCH MODE",
    ["overlay.subtitle"]                       = "Return to writing, reading, coding, or analysis.",
    ["overlay.remaining_prefix"]               = "Remaining: ",
    ["overlay.idle"]                           = "Idle",
    ["overlay.active_countdown_prefix"]        = "Active countdown: ",
    ["overlay.fallback_message"]               = "Return to research work.",
    ["overlay.fallback_reason"]                = "Off-task behavior detected.",
    ["overlay.block_suffix"]                   = "BLOCK",
    ["terminal_guard.prompt.title"]            = "TERMINAL CHECK",
    ["terminal_guard.prompt.question"]         = "Is this Terminal command related to your research work?",
    ["terminal_guard.prompt.instructions"]     = "Press Y to allow Terminal for 30 minutes.\nPress N to block Terminal commands for 30 minutes.",
    ["terminal_guard.prompt.waiting"]          = "Waiting for Y or N",
    ["terminal_guard.state_reason.allow"]      = "Terminal allowed for research work.",
    ["terminal_guard.state_reason.block"]      = "Terminal blocked after non-research confirmation.",
    ["terminal_guard.state_reason.inactive_allow"] = "Terminal allowed because BLOCK mode is inactive.",
    ["terminal_guard.alert.allow"]             = "Terminal allowed for 30 minutes",
    ["terminal_guard.alert.block"]             = "Terminal blocked for 30 minutes",
    ["shell.awaiting_confirmation"]            = "Awaiting BLOCK mode terminal confirmation.",
    ["shell.blocked_default"]                  = "Blocked by BLOCK mode terminal check",
    ["shell.decision_required"]               = "Decision required before terminal commands are allowed.",
    ["shell.decision_expired"]                = "Decision window expired. Please answer the BLOCK mode prompt.",
    ["shell.command_blocked.title"]            = "Command blocked",
    -- {detail} and {remaining} are template placeholders expanded by the shell script.
    ["shell.command_blocked.detail"]           = "{detail} (remaining: {remaining})",
    ["shell.allowed_status"]                   = "Terminal allowed by Y selection (remaining: {remaining})",
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

-- decodeScalar strips surrounding quotes and expands escape sequences.
-- Handles both single-quoted and double-quoted YAML scalar values.
local function decodeScalar(value)
    value = trim(value)
    local first = value:sub(1, 1)
    local last = value:sub(-1)
    if (first == '"' and last == '"') or (first == "'" and last == "'") then
        value = value:sub(2, -2)
    end
    value = value:gsub("\\n", "\n")
    value = value:gsub('\\"', '"')
    value = value:gsub("\\'", "'")
    return value
end

-- dottedKey constructs the dotted lookup key for a YAML value at the given
-- depth within the nesting stack. stack[0..depth-1] contains parent keys.
local function dottedKey(stack, depth, key)
    local parts = {}
    for index = 0, depth - 1 do
        if stack[index] then table.insert(parts, stack[index]) end
    end
    table.insert(parts, key)
    return table.concat(parts, ".")
end

-- readMessagesYaml parses a YAML file into a flat dotted-key → value table.
-- Indentation depth is computed from leading spaces (2 spaces = 1 level).
-- Lines with no value (key:) set a nesting context for subsequent lines.
-- Lines with a value (key: value) are stored immediately.
-- Comments after content (# …) are stripped before parsing.
local function readMessagesYaml(path)
    local values = {}
    local file = io.open(path, "r")
    if not file then return values end

    local stack = {}
    for line in file:lines() do
        local withoutComment = line:gsub("%s+#.*$", "")
        local indent, key, value = withoutComment:match("^(%s*)([%w%._-]+)%s*:%s*(.-)%s*$")
        if key then
            local depth = math.floor(#indent / 2)
            if value == "" then
                -- Context-only line: update the nesting stack and clear deeper levels.
                stack[depth] = key
                for index = depth + 1, #stack do
                    stack[index] = nil
                end
            else
                values[dottedKey(stack, depth, key)] = decodeScalar(value)
            end
        end
    end
    file:close()
    return values
end

-- Messages.new loads defaults first, then overlays YAML values so the file
-- can selectively override any subset of messages without specifying all of them.
function Messages.new(path)
    local self = setmetatable({}, Messages)
    self.path = path
    self.values = {}
    for key, value in pairs(defaults) do
        self.values[key] = value
    end
    for key, value in pairs(readMessagesYaml(path)) do
        self.values[key] = value
    end
    return self
end

-- get returns the message for key, falling back first to the runtime `fallback`
-- argument, then to the hardcoded default, then to "". This three-level fallback
-- means a partially written YAML file never causes nil errors in callers.
function Messages:get(key, fallback)
    local value = self.values[key]
    if value == nil then
        return fallback or defaults[key] or ""
    end
    return value
end

return Messages
