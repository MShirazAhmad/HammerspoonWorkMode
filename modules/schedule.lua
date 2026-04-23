-- Schedule is the time gate for enforcement.
-- If the schedule says "not active now", the rest of the blocker does not
-- intervene even if GPS would otherwise imply BLOCK mode.
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

function Schedule:isActiveNow()
    -- When scheduling is disabled, the caller should treat time as always valid.
    if self.config.enabled == false then
        return true
    end

    local now = os.date("*t")
    -- Weekday filtering comes first so weekends can be ignored entirely.
    if self.config.workdays and self.config.workdays[now.wday] ~= true then
        return false
    end

    -- Then apply the simple hour window.
    local startHour = self.config.start_hour or 0
    local endHour = self.config.end_hour or 24
    return now.hour >= startHour and now.hour < endHour
end

function Schedule:statusSummary()
    return self:isActiveNow() and "Inside work hours" or "Outside work hours"
end

return Schedule
