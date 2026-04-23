-- Logger keeps two kinds of evidence:
-- 1. marker messages for humans
-- 2. structured JSON snapshots/events for later processing
local Logger = {}
Logger.__index = Logger

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isArrayTable(tbl)
    local maxIndex = 0
    local count = 0
    for key, _ in pairs(tbl) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        if key > maxIndex then
            maxIndex = key
        end
        count = count + 1
    end
    return maxIndex == count
end

local function sanitizeForJSON(value, seen)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" then
        return value
    end
    if valueType == "number" then
        return isFiniteNumber(value) and value or tostring(value)
    end
    if valueType == "string" then
        return value
    end
    if valueType ~= "table" then
        return tostring(value)
    end

    if seen[value] then
        return "<cycle>"
    end
    seen[value] = true

    local out = nil
    if isArrayTable(value) then
        out = {}
        for index = 1, #value do
            out[index] = sanitizeForJSON(value[index], seen)
        end
    else
        out = {}
        for key, nested in pairs(value) do
            out[tostring(key)] = sanitizeForJSON(nested, seen)
        end
    end
    seen[value] = nil
    return out
end

function Logger.new(config)
    local self = setmetatable({}, Logger)
    self.config = config
    self.lastSnapshot = nil
    self.lastMarkerMessage = nil
    return self
end

function Logger:title()
    return "Logger"
end

function Logger:description()
    return "Records marker events and activity snapshots so status can explain recent blocker decisions."
end

function Logger:isoTimestamp()
    -- Emit timestamps with an explicit UTC offset so log records remain useful
    -- even when reviewed outside the original timezone.
    local now = os.time()
    local utc = os.date("!*t", now)
    local localTime = os.date("*t", now)
    local offsetSeconds = os.difftime(os.time(localTime), os.time(utc))
    local sign = offsetSeconds >= 0 and "+" or "-"
    local offsetAbs = math.abs(offsetSeconds)
    local hours = math.floor(offsetAbs / 3600)
    local minutes = math.floor((offsetAbs % 3600) / 60)
    return os.date("%Y-%m-%dT%H:%M:%S", now) .. string.format("%s%02d:%02d", sign, hours, minutes)
end

function Logger:_appendLine(path, line)
    -- Tiny shared file append helper used by both marker and activity logs.
    local file = io.open(path, "a")
    if not file then
        return false
    end
    file:write(line .. "\n")
    file:close()
    return true
end

function Logger:marker(message)
    -- Marker logs are meant to be skimmed by a person trying to understand
    -- what the blocker did and why.
    self.lastMarkerMessage = tostring(message)
    self:_appendLine(
        self.config.user.marker_log_path,
        os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(message)
    )
    hs.printf("[research-mode] %s", tostring(message))
end

function Logger:lastMarker()
    return self.lastMarkerMessage
end

function Logger:_encode(record)
    -- Use Hammerspoon's JSON encoder so snapshots stay valid and machine-friendly.
    local ok, encoded = pcall(hs.json.encode, record, true, true)
    if ok and type(encoded) == "string" then
        return encoded
    end

    local sanitized = sanitizeForJSON(record, {})
    local safeOk, safeEncoded = pcall(hs.json.encode, sanitized, true, true)
    if safeOk and type(safeEncoded) == "string" then
        hs.printf("[research-mode] logger sanitized non-JSON-safe record: %s", tostring(encoded))
        return safeEncoded
    end

    return '{"type":"logger_error","reason":"json_encode_failed"}'
end

function Logger:activity(record, force)
    -- Avoid writing duplicate snapshots unless the caller explicitly forces it.
    local encoded = self:_encode(record)
    if not force and encoded == self.lastSnapshot then
        return
    end
    self.lastSnapshot = encoded
    self:_appendLine(self.config.user.activity_log_path, encoded)
end

function Logger:event(eventName, extra)
    -- Events capture app lifecycle changes such as activation and termination.
    local record = {
        ts = self:isoTimestamp(),
        type = "event",
        event = eventName,
    }
    for key, value in pairs(extra or {}) do
        record[key] = value
    end
    self:_appendLine(self.config.user.activity_log_path, self:_encode(record))
end

return Logger
