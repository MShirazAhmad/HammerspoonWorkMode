-- Tiny reader for config/messages.yaml. It supports the simple nested
-- key/value YAML shape used by the project and returns dotted lookup keys.
local Messages = {}
Messages.__index = Messages

local defaults = {
    ["overlay.title"] = "RESEARCH MODE",
    ["overlay.subtitle"] = "Return to writing, reading, coding, or analysis.",
    ["overlay.remaining_prefix"] = "Remaining: ",
    ["overlay.idle"] = "Idle",
    ["overlay.active_countdown_prefix"] = "Active countdown: ",
    ["overlay.fallback_message"] = "Return to research work.",
    ["overlay.fallback_reason"] = "Off-task behavior detected.",
    ["overlay.block_suffix"] = "BLOCK",
    ["terminal_guard.prompt.title"] = "TERMINAL CHECK",
    ["terminal_guard.prompt.question"] = "Is this Terminal command related to your research work?",
    ["terminal_guard.prompt.instructions"] = "Press Y to allow Terminal for 30 minutes.\nPress N to block Terminal commands for 30 minutes.",
    ["terminal_guard.prompt.waiting"] = "Waiting for Y or N",
    ["terminal_guard.state_reason.allow"] = "Terminal allowed for research work.",
    ["terminal_guard.state_reason.block"] = "Terminal blocked after non-research confirmation.",
    ["terminal_guard.state_reason.inactive_allow"] = "Terminal allowed because BLOCK mode is inactive.",
    ["terminal_guard.alert.allow"] = "Terminal allowed for 30 minutes",
    ["terminal_guard.alert.block"] = "Terminal blocked for 30 minutes",
    ["shell.awaiting_confirmation"] = "Awaiting BLOCK mode terminal confirmation.",
    ["shell.blocked_default"] = "Blocked by BLOCK mode terminal check",
    ["shell.decision_required"] = "Decision required before terminal commands are allowed.",
    ["shell.decision_expired"] = "Decision window expired. Please answer the BLOCK mode prompt.",
    ["shell.command_blocked.title"] = "Command blocked",
    ["shell.command_blocked.detail"] = "{detail} (remaining: {remaining})",
    ["shell.allowed_status"] = "Terminal allowed by Y selection (remaining: {remaining})",
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

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

local function dottedKey(stack, depth, key)
    local parts = {}
    for index = 0, depth - 1 do
        if stack[index] then
            table.insert(parts, stack[index])
        end
    end
    table.insert(parts, key)
    return table.concat(parts, ".")
end

local function readMessagesYaml(path)
    local values = {}
    local file = io.open(path, "r")
    if not file then
        return values
    end

    local stack = {}
    for line in file:lines() do
        local withoutComment = line:gsub("%s+#.*$", "")
        local indent, key, value = withoutComment:match("^(%s*)([%w%._-]+)%s*:%s*(.-)%s*$")
        if key then
            local depth = math.floor(#indent / 2)
            if value == "" then
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

function Messages:get(key, fallback)
    local value = self.values[key]
    if value == nil then
        return fallback or defaults[key] or ""
    end
    return value
end

return Messages
