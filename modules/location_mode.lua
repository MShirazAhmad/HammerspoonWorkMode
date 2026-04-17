-- GPS mode is the first branch in the whole system.
-- This module determines whether the machine is inside the approved geofence
-- and translates that into an ALLOW/BLOCK-style runtime state.
local LocationMode = {}
LocationMode.__index = LocationMode

function LocationMode.new(config, logger)
    local self = setmetatable({}, LocationMode)
    self.config = config.location or {}
    self.logger = logger
    self.lastState = {
        -- "unknown" is used until the first successful poll.
        mode = "unknown",
        relaxed = false,
        distance = nil,
        reason = "not_started",
    }
    self.statusItem = nil
    self.timer = nil
    return self
end

local function writeStateFile(path, state)
    -- The state file lets external tools or shell scripts read the last known
    -- GPS decision without embedding Hammerspoon logic themselves.
    local file = io.open(path, "w")
    if not file then
        return
    end
    for _, key in ipairs({ "mode", "relaxed", "distance_meters", "reason", "updated_at" }) do
        if state[key] ~= nil then
            file:write(key .. "=" .. tostring(state[key]) .. "\n")
        end
    end
    file:close()
end

function LocationMode:_updateMenubar()
    -- The menubar gives a quick ambient signal of whether the machine currently
    -- thinks it is in the approved area.
    if not self.statusItem then
        self.statusItem = hs.menubar.new()
    end
    if not self.statusItem then
        return
    end

    local title = "LOC ?"
    if self.lastState.mode == "lab" then
        title = "LAB"
    elseif self.lastState.mode == "home" then
        title = "HOME"
    end
    self.statusItem:setTitle(title)
    self.statusItem:setTooltip("Location mode: " .. tostring(self.lastState.mode))
end

function LocationMode:_setState(nextState)
    -- Centralize state writes so the in-memory state, menubar, and state file
    -- all stay consistent.
    self.lastState = nextState
    self:_updateMenubar()
    writeStateFile((self.config.state_path or (os.getenv("HOME") .. "/.hammerspoon/manage-py-geofence.state")), {
        mode = nextState.mode,
        relaxed = nextState.relaxed and 1 or 0,
        distance_meters = nextState.distance and string.format("%.2f", nextState.distance) or nil,
        reason = nextState.reason,
        updated_at = os.time(),
    })
end

function LocationMode:poll()
    -- Each early return below explains why GPS could not produce a normal
    -- inside/outside answer.
    if self.config.enabled == false then
        self:_setState({
            mode = "unknown",
            relaxed = false,
            distance = nil,
            reason = "disabled",
        })
        return
    end

    if not hs.location.servicesEnabled() then
        self:_setState({
            mode = "unknown",
            relaxed = false,
            distance = nil,
            reason = "location_services_disabled",
        })
        return
    end

    local auth = hs.location.authorizationStatus()
    if auth ~= "authorized" then
        self:_setState({
            mode = "unknown",
            relaxed = false,
            distance = nil,
            reason = "location_auth_" .. tostring(auth),
        })
        return
    end

    local location = hs.location.get()
    if not location or type(location.latitude) ~= "number" or type(location.longitude) ~= "number" then
        self:_setState({
            mode = "unknown",
            relaxed = false,
            distance = nil,
            reason = "location_unavailable",
        })
        return
    end

    -- Once a valid location exists, compare it with the configured geofence.
    local geofence = self.config.lab_geofence or {}
    local distance = hs.location.distance(location, geofence)
    local inside = distance <= (geofence.radius or 0)
    local nextState = {
        mode = inside and "lab" or "home",
        relaxed = inside and self.config.lab_relaxes_blocks == true,
        distance = distance,
        reason = inside and "inside_lab_geofence" or "outside_lab_geofence",
    }

    -- Only write a marker when the mode actually changes, so the log stays
    -- informative without becoming noisy.
    if self.lastState.mode ~= nextState.mode then
        self.logger:marker("location mode=" .. nextState.mode .. " distance=" .. string.format("%.2f", distance))
    end

    self:_setState(nextState)
end

function LocationMode:start()
    -- Poll immediately on startup so the rest of the system can begin with a
    -- real mode instead of waiting for the first timer tick.
    self:poll()
    if self.timer then
        self.timer:stop()
    end
    self.timer = hs.timer.doEvery(self.config.poll_seconds or 5, function()
        local ok, err = pcall(function()
            self:poll()
        end)
        if not ok then
            self.logger:marker("location poll error=" .. tostring(err))
        end
    end)
end

function LocationMode:mode()
    -- Expose the current human-readable location mode to the caller.
    return self.lastState.mode
end

function LocationMode:isRelaxed()
    -- "relaxed" is what init.lua actually cares about when deciding whether
    -- BLOCK enforcement should be active.
    return self.lastState.relaxed == true
end

return LocationMode
