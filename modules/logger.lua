-- logger.lua — Dual-channel logging: human-readable markers + JSONL snapshots.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- Logger is the observability layer. It is shared across all modules via
-- dependency injection (Logger.new(config) is created once in init.lua and
-- passed to every module that needs it).
--
-- TWO LOG CHANNELS
-- ----------------
-- 1. Marker log (config.user.marker_log_path, default ~/hard-blocker.marker.log)
--    Plain-text, one event per line, human-readable. Written by marker().
--    Format: "YYYY-MM-DD HH:MM:SS <message>"
--    Contents: violations, GPS transitions, terminal guard decisions, startup.
--    Intended for a person reviewing "why did the blocker fire?" after the fact.
--    Also available in the Hammerspoon console via hs.printf.
--
-- 2. Activity log (config.user.activity_log_path, default ~/web-activity.log)
--    JSONL (one JSON object per line). Written by activity() and event().
--    Each record is a snapshot of the visible context at a point in time:
--    app, window title, browser URL/host, schedule state, GPS mode, classifier
--    result. Intended for automated analysis or training data.
--    Duplicate suppression: activity() skips writing if the encoded JSON
--    equals the previous record, unless force=true is passed. This prevents
--    identical idle records from filling the log on every scan_seconds tick.
--
-- JSON ENCODING
-- -------------
-- sanitizeForJSON() converts Lua values into JSON-safe forms before encoding.
-- It handles: nil, booleans, finite numbers, strings, arrays, and nested tables.
-- Non-finite numbers (inf, nan) are converted to strings. Tables that would
-- cause circular reference panics are detected via a `seen` table and replaced
-- with "<cycle>". The primary encoder is hs.json.encode; sanitizeForJSON is
-- only invoked as a fallback when the primary encoder throws.
--
-- TIMESTAMP FORMAT
-- ----------------
-- isoTimestamp() emits ISO 8601 with explicit UTC offset (e.g. "2026-04-29T13:00:00+05:00")
-- so log records stay interpretable when reviewed across timezone boundaries.
-- os.date() is called twice: once as UTC (*t) and once as local time (*t),
-- and the difference gives the offset in seconds.

local Logger = {}
Logger.__index = Logger

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- isArrayTable returns true if the table is a pure integer-keyed sequence
-- starting at 1 with no gaps. Used to decide whether to encode as JSON array
-- or JSON object.
local function isArrayTable(tbl)
    local maxIndex = 0
    local count = 0
    for key, _ in pairs(tbl) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        if key > maxIndex then maxIndex = key end
        count = count + 1
    end
    return maxIndex == count
end

-- sanitizeForJSON recursively converts a Lua value into a form that
-- hs.json.encode can always handle. The `seen` table detects circular
-- references; the function writes "<cycle>" rather than crashing.
local function sanitizeForJSON(value, seen)
    local valueType = type(value)
    if valueType == "nil" or valueType == "boolean" then return value end
    if valueType == "number" then return isFiniteNumber(value) and value or tostring(value) end
    if valueType == "string" then return value end
    if valueType ~= "table" then return tostring(value) end

    if seen[value] then return "<cycle>" end
    seen[value] = true

    local out
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
    -- lastSnapshot caches the most recent JSONL record to enable duplicate suppression.
    self.lastSnapshot = nil
    -- lastMarkerMessage is exposed via lastMarker() so the menu can show the
    -- most recent event without reading the log file.
    self.lastMarkerMessage = nil
    return self
end

function Logger:title()
    return "Logger"
end

function Logger:description()
    return "Records marker events and activity snapshots so status can explain recent blocker decisions."
end

-- isoTimestamp returns the current local time as ISO 8601 with explicit UTC offset.
-- The offset is derived by comparing os.time() interpreted as UTC vs local time.
function Logger:isoTimestamp()
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

-- _appendLine is the shared file-append helper. Both channels use it so file
-- open/close semantics are consistent. Files are opened in append mode ("a")
-- so existing records are never overwritten across Hammerspoon reloads.
function Logger:_appendLine(path, line)
    local file = io.open(path, "a")
    if not file then return false end
    file:write(line .. "\n")
    file:close()
    return true
end

-- marker() writes to the human-readable marker log. Also calls hs.printf so
-- the Hammerspoon console shows enforcement events in real time during development.
-- message should be a short key=value string (e.g. "violation kind=browser").
function Logger:marker(message)
    self.lastMarkerMessage = tostring(message)
    self:_appendLine(
        self.config.user.marker_log_path,
        os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(message)
    )
    hs.printf("[research-mode] %s", tostring(message))
end

-- lastMarker returns the most recent marker message for display in the menu bar
-- dashboard. Returns nil if no marker has been written yet in this session.
function Logger:lastMarker()
    return self.lastMarkerMessage
end

-- _encode converts a Lua table to a JSON string. Attempts hs.json.encode first
-- (fast path). If that fails (non-JSON-safe values), sanitizeForJSON is applied
-- and encoding is retried. If both fail, a minimal error sentinel is returned
-- so the log file never contains a malformed line.
function Logger:_encode(record)
    local ok, encoded = pcall(hs.json.encode, record, true, true)
    if ok and type(encoded) == "string" then return encoded end

    local sanitized = sanitizeForJSON(record, {})
    local safeOk, safeEncoded = pcall(hs.json.encode, sanitized, true, true)
    if safeOk and type(safeEncoded) == "string" then
        hs.printf("[research-mode] logger sanitized non-JSON-safe record: %s", tostring(encoded))
        return safeEncoded
    end

    return '{"type":"logger_error","reason":"json_encode_failed"}'
end

-- activity() writes a snapshot record to the JSONL activity log.
-- Duplicate suppression: if the encoded record is identical to the previous one
-- AND force is false, the write is skipped. force=true is used when the caller
-- knows the context changed (e.g. on app activation or startup).
function Logger:activity(record, force)
    local encoded = self:_encode(record)
    if not force and encoded == self.lastSnapshot then return end
    self.lastSnapshot = encoded
    self:_appendLine(self.config.user.activity_log_path, encoded)
end

-- event() writes a named event record to the JSONL activity log. Used for
-- app lifecycle events (activated, launched, terminated) that are distinct
-- from periodic snapshots but should appear in the same timeline.
function Logger:event(eventName, extra)
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
