-- Logger keeps two kinds of evidence:
-- 1. marker messages for humans
-- 2. structured JSON snapshots/events for later processing
local Logger = {}
Logger.__index = Logger

function Logger.new(config)
    local self = setmetatable({}, Logger)
    self.config = config
    self.lastSnapshot = nil
    return self
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
    self:_appendLine(
        self.config.user.marker_log_path,
        os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(message)
    )
    hs.printf("[research-mode] %s", tostring(message))
end

function Logger:_encode(record)
    -- Use Hammerspoon's JSON encoder so snapshots stay valid and machine-friendly.
    return hs.json.encode(record, true, true)
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
