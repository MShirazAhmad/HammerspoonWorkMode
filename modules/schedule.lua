-- schedule.lua — Time-window gate for enforcement.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- Schedule is the simplest module in the system. init.lua calls
-- schedule:isActiveNow() inside strictModeActive(). If it returns false,
-- the entire enforcement system is suppressed, regardless of GPS state.
--
-- BLOCK mode requires BOTH schedule AND location to agree:
--   strictModeActive() = schedule:isActiveNow() AND NOT locationMode:isRelaxed()
--
-- When schedule.enabled = false in config, isActiveNow() always returns true,
-- effectively making time irrelevant (useful for testing or 24/7 enforcement).
--
-- WEEKDAY NUMBERING
-- -----------------
-- config.schedule.workdays uses Lua's os.date() weekday convention:
--   1 = Sunday, 2 = Monday, 3 = Tuesday, ..., 7 = Saturday
-- (Same as strftime %u but 1-indexed from Sunday, not Monday.)
-- The config file documents this explicitly to avoid confusion.
--
-- HOUR WINDOW
-- -----------
-- The window is [start_hour, end_hour) in local time using simple hour comparison.
-- No minute-level granularity — the window activates at the top of start_hour
-- and deactivates at the top of end_hour.

local Schedule = {}
Schedule.__index = Schedule

function Schedule.new(config)
    local self = setmetatable({}, Schedule)
    self.config = config.schedule or {}
    return self
end

function Schedule:title()
    return "Schedule"
end

function Schedule:description()
    return "Acts as the time gate so enforcement only runs during your configured work window."
end

-- isActiveNow returns true when the current local time falls inside the
-- configured work window. Called on every enforce() pass so transitions
-- at the hour boundary take effect within one scan_seconds tick.
function Schedule:isActiveNow()
    -- enabled = false means "always treat as inside the window."
    if self.config.enabled == false then
        return true
    end

    local now = os.date("*t")

    -- Weekday filtering runs first so weekend days are rejected before
    -- the hour check, avoiding misleading hour-range log entries.
    if self.config.workdays and self.config.workdays[now.wday] ~= true then
        return false
    end

    local startHour = self.config.start_hour or 0
    local endHour = self.config.end_hour or 24
    return now.hour >= startHour and now.hour < endHour
end

function Schedule:statusSummary()
    return self:isActiveNow() and "Inside work hours" or "Outside work hours"
end

return Schedule
