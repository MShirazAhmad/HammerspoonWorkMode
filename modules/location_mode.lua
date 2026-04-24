-- GPS mode is the first branch in the whole system.
-- This module determines whether the machine is inside the approved geofence
-- and translates that into an ALLOW/BLOCK-style runtime state.
local LocationMode = {}
LocationMode.__index = LocationMode

local function statusImage(title, fillColor, textColor)
    -- Render a compact high-contrast badge that stays readable in the menu bar.
    local canvas = hs.canvas.new({ x = 0, y = 0, w = 54, h = 18 })
    canvas[1] = {
        type = "rectangle",
        action = "fill",
        roundedRectRadii = { xRadius = 9, yRadius = 9 },
        fillColor = fillColor,
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
    }
    canvas[2] = {
        type = "text",
        text = title,
        textSize = 9,
        textFont = ".AppleSystemUIFont",
        textColor = textColor,
        textAlignment = "center",
        frame = { x = 0, y = 3, w = "100%", h = 12 },
    }
    local image = canvas:imageFromCanvas()
    if image and image.setTemplate then
        image:setTemplate(false)
    end
    return image
end

function LocationMode.new(config, logger)
    local self = setmetatable({}, LocationMode)
    self.rootConfig = config or {}
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
    self.menuProvider = nil
    self.lastMenuSignature = nil
    return self
end

function LocationMode:title()
    return "Location Mode"
end

function LocationMode:description()
    return "Reads GPS state and decides whether the system should stay relaxed or enforce BLOCK."
end

local function menuText(value, fallback)
    if value == nil or value == "" then
        return fallback or "unknown"
    end
    return tostring(value)
end

local function normalizedMenuItem(item)
    if type(item) == "table" then
        return item
    end
    return {
        title = tostring(item),
        disabled = true,
    }
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

local function stateEquals(left, right)
    if left == right then
        return true
    end
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end
    return left.mode == right.mode
        and left.relaxed == right.relaxed
        and left.reason == right.reason
end

function LocationMode:_updateMenubar()
    -- Keep a real menu bar item on the top-right and give it a pill-like icon.
    if not self.statusItem then
        self.statusItem = hs.menubar.new()
    end
    if not self.statusItem then
        return
    end
    local title = "LOC ?"
    local fillColor = { red = 0.15, green = 0.15, blue = 0.15, alpha = 1 }
    local color = { red = 1, green = 1, blue = 1, alpha = 1 }
    if self.lastState.mode ~= "unknown" then
        if self.lastState.relaxed == true then
            title = "ALLOW"
            fillColor = { red = 0.12, green = 0.62, blue = 0.28, alpha = 1 }
        else
            title = "BLOCK"
            fillColor = { red = 0.72, green = 0.12, blue = 0.12, alpha = 1 }
        end
    end
    local tooltip = "Location mode: " .. tostring(self.lastState.mode) .. " (" .. title .. ")"
    local signature = table.concat({
        title,
        tostring(self.lastState.mode),
        tostring(self.lastState.reason),
        tostring(self.lastState.relaxed),
    }, "|")
    if self.lastMenuSignature ~= signature then
        self.statusItem:setTitle("")
        self.statusItem:setIcon(statusImage(title, fillColor, color), false)
        self.statusItem:setTooltip(tooltip)
        self.lastMenuSignature = signature
    end
    if not self.menuInstalled then
        self.statusItem:setMenu(function()
            return self:_buildMenu()
        end)
        self.menuInstalled = true
    end
end

function LocationMode:_buildMenu()
    local summary = nil
    if type(self.menuProvider) == "function" then
        local ok, result = pcall(self.menuProvider, self)
        if ok and type(result) == "table" then
            summary = result
        elseif not ok and self.logger then
            self.logger:marker("menubar menu error=" .. tostring(result))
        end
    end

    local menu = {
        {
            title = menuText(summary and summary.title, "Location Rules"),
            disabled = true,
        },
        {
            title = "Mode: " .. menuText(summary and summary.mode, self.lastState.relaxed and "ALLOW" or "BLOCK"),
            disabled = true,
        },
        {
            title = "Location: " .. menuText(self.lastState.reason, "unknown"),
            disabled = true,
        },
    }

    local actions = summary and summary.actions or {}
    if #actions > 0 then
        table.insert(menu, { title = "-" })
        for _, item in ipairs(actions) do
            table.insert(menu, normalizedMenuItem(item))
        end
    end

    local items = summary and summary.items or {}
    if #items > 0 then
        table.insert(menu, { title = "-" })
        for _, item in ipairs(items) do
            table.insert(menu, normalizedMenuItem(item))
        end
    end

    return menu
end

function LocationMode:setMenuProvider(provider)
    self.menuProvider = provider
    self:_updateMenubar()
end

function LocationMode:_setState(nextState)
    -- Centralize state writes so the in-memory state, menubar, and state file
    -- all stay consistent.
    local changed = not stateEquals(self.lastState, nextState)
    self.lastState = nextState
    if changed or not self.statusItem then
        self:_updateMenubar()
    end
    local statePath = self.config.state_path
        or (self.rootConfig.user and self.rootConfig.user.geofence_state_path)
        or (os.getenv("HOME") .. "/.hammerspoon/manage-py-geofence.state")
    writeStateFile(statePath, {
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
    local authText = tostring(auth):lower()
    local denied = auth == false
        or authText == "denied"
        or authText == "restricted"
        or authText == "not_determined"
        or authText == "not determined"
    if denied then
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
    local blockInside = self.config.block_inside_geofence == true
    local relaxed = nil
    local reason = nil
    if blockInside then
        -- In flipped mode, only the configured geofence is strict/BLOCK.
        relaxed = not inside
        reason = inside and "inside_block_geofence" or "outside_block_geofence"
    else
        relaxed = inside and self.config.lab_relaxes_blocks == true
        reason = inside and "inside_lab_geofence" or "outside_lab_geofence"
    end

    local nextState = {
        mode = inside and "lab" or "home",
        relaxed = relaxed,
        distance = distance,
        reason = reason,
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
    local pollSeconds = self.config.poll_seconds
        or (self.rootConfig.timers and self.rootConfig.timers.location_poll_seconds)
        or 5
    self.timer = hs.timer.doEvery(pollSeconds, function()
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

function LocationMode:statusSummary()
    local mode = self.lastState.relaxed and "ALLOW" or "BLOCK"
    return mode .. " via " .. tostring(self.lastState.reason or "unknown")
end

return LocationMode
