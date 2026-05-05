-- location_mode.lua — GPS geofence → ALLOW/BLOCK mode decision.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- LocationMode is the geographic gate for BLOCK mode. init.lua calls
-- locationMode:isRelaxed() inside strictModeActive(); if it returns true, the
-- whole enforcement system is suppressed regardless of the schedule.
--
-- TWO OPERATING MODES (config.location.block_inside_geofence)
-- -----------------------------------------------------------
--   block_inside_geofence = true  (default, this install's setting):
--     Inside geofence  → BLOCK (strictMode can be active)
--     Outside geofence → ALLOW (relaxed = true)
--     Interpretation: the lab/office IS the enforced work zone.
--
--   block_inside_geofence = false (alternate mode):
--     Inside geofence  → ALLOW if lab_relaxes_blocks = true
--     Outside geofence → BLOCK
--     Interpretation: the lab is the safe zone where work is assumed.
--
-- STATE FILE IPC
-- --------------
-- After every GPS poll _setState() writes a key=value file to
-- config.user.geofence_state_path. This file is read by the shell-side
-- terminal-command-guard.zsh via _research_geofence_is_relaxed() to decide
-- whether to auto-approve terminal commands without showing the Hammerspoon
-- overlay. The file format is intentionally simple (IFS='=' read loop).
-- Fields: mode, relaxed, distance_meters, reason, updated_at.
--
-- MENU BAR BADGE
-- --------------
-- LocationMode owns the sole menu bar item. It shows a pill-shaped badge:
--   Green "ALLOW"  — relaxed=true
--   Red   "BLOCK"  — relaxed=false (enforcement active or unknown)
--   Grey  "LOC ?"  — GPS not yet polled or in error state
-- The badge is a small hs.canvas rendered to an NSImage so it can be full
-- color (template images would be monochrome).
--
-- The menu content (the dropdown) is provided by init.lua via setMenuProvider().
-- LocationMode calls the provider function lazily on every menu open so the
-- data is always fresh without LocationMode needing to know about the other modules.
--
-- POLL RATE
-- ---------
-- Location is polled every config.timers.location_poll_seconds (default 5 s).
-- A marker log entry is written only when the mode changes (inside→outside or
-- vice versa) to keep the log readable.

local LocationMode = {}
LocationMode.__index = LocationMode

-- statusImage renders a small rounded-rectangle badge as an NSImage for the
-- menu bar. The image is non-template so it retains its fill colour in both
-- light and dark menu bar modes.
local function statusImage(title, fillColor, textColor)
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
        -- "unknown" is used until the first successful GPS poll.
        mode = "unknown",
        relaxed = false,
        distance = nil,
        reason = "not_started",
    }
    self.statusItem = nil
    self.timer = nil
    self.menuProvider = nil
    -- lastMenuSignature prevents redundant badge redraws on polls where nothing changed.
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
    if value == nil or value == "" then return fallback or "unknown" end
    return tostring(value)
end

local function normalizedMenuItem(item)
    if type(item) == "table" then return item end
    return { title = tostring(item), disabled = true }
end

-- writeStateFile writes the GPS decision to disk in key=value format so the
-- shell-side guard script can read it with a plain while/IFS read loop.
-- Fields match exactly what terminal-command-guard.zsh expects; do not rename them.
local function writeStateFile(path, state)
    local file = io.open(path, "w")
    if not file then return end
    for _, key in ipairs({ "mode", "relaxed", "distance_meters", "reason", "updated_at" }) do
        if state[key] ~= nil then
            file:write(key .. "=" .. tostring(state[key]) .. "\n")
        end
    end
    file:close()
end

-- stateEquals compares only the fields that matter for the badge and log.
-- distance is NOT compared so minor GPS drift does not trigger constant redraws.
local function stateEquals(left, right)
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    return left.mode == right.mode
        and left.relaxed == right.relaxed
        and left.reason == right.reason
end

-- _updateMenubar redraws the menu bar badge when the state or badge image
-- changes. Uses a signature string to avoid redundant setIcon calls on polls
-- where nothing changed.
function LocationMode:_updateMenubar()
    if not self.statusItem then
        self.statusItem = hs.menubar.new()
    end
    if not self.statusItem then return end

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
        title, tostring(self.lastState.mode),
        tostring(self.lastState.reason), tostring(self.lastState.relaxed),
    }, "|")
    if self.lastMenuSignature ~= signature then
        self.statusItem:setTitle("")
        self.statusItem:setIcon(statusImage(title, fillColor, color), false)
        self.statusItem:setTooltip(tooltip)
        self.lastMenuSignature = signature
    end
    -- Install the menu callback only once. The callback is a lazy function that
    -- calls menuProvider on every open so the content is always fresh.
    if not self.menuInstalled then
        self.statusItem:setMenu(function()
            return self:_buildMenu()
        end)
        self.menuInstalled = true
    end
end

-- _buildMenu calls the menuProvider function (supplied by init.lua via
-- setMenuProvider) to get the full dashboard data, then wraps it in a menu
-- table that hs.menubar understands. pcall protects against errors in the
-- provider function crashing the menu bar.
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
        { title = menuText(summary and summary.title, "Location Rules"), disabled = true },
        { title = "Mode: " .. menuText(summary and summary.mode, self.lastState.relaxed and "ALLOW" or "BLOCK"), disabled = true },
        { title = "Location: " .. menuText(self.lastState.reason, "unknown"), disabled = true },
    }

    local actions = summary and summary.actions or {}
    if #actions > 0 then
        table.insert(menu, { title = "-" })
        for _, item in ipairs(actions) do table.insert(menu, normalizedMenuItem(item)) end
    end

    local items = summary and summary.items or {}
    if #items > 0 then
        table.insert(menu, { title = "-" })
        for _, item in ipairs(items) do table.insert(menu, normalizedMenuItem(item)) end
    end

    return menu
end

function LocationMode:setMenuProvider(provider)
    self.menuProvider = provider
    self:_updateMenubar()
end

-- _setState is the single write path for location state. It ensures the
-- in-memory state, the menu bar badge, and the on-disk state file are always
-- consistent after every GPS poll.
function LocationMode:_setState(nextState)
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

-- poll() is the GPS evaluation function called every location_poll_seconds.
-- Each early return explains a specific reason GPS cannot answer (disabled,
-- location services off, authorization denied, location unavailable).
-- When a valid location is obtained, it is compared against lab_geofence and
-- the result is stored via _setState().
function LocationMode:poll()
    if self.config.enabled == false then
        self:_setState({ mode = "unknown", relaxed = false, distance = nil, reason = "disabled" })
        return
    end

    if not hs.location.servicesEnabled() then
        self:_setState({ mode = "unknown", relaxed = false, distance = nil, reason = "location_services_disabled" })
        return
    end

    local auth = hs.location.authorizationStatus()
    local authText = tostring(auth):lower()
    local denied = auth == false or authText == "denied" or authText == "restricted"
        or authText == "not_determined" or authText == "not determined"
    if denied then
        self:_setState({ mode = "unknown", relaxed = false, distance = nil, reason = "location_auth_" .. tostring(auth) })
        return
    end

    local location = hs.location.get()
    if not location or type(location.latitude) ~= "number" or type(location.longitude) ~= "number" then
        self:_setState({ mode = "unknown", relaxed = false, distance = nil, reason = "location_unavailable" })
        return
    end

    local geofence = self.config.lab_geofence or {}
    local distance = hs.location.distance(location, geofence)
    local inside = distance <= (geofence.radius or 0)
    local blockInside = self.config.block_inside_geofence == true
    local relaxed, reason

    if blockInside then
        -- block_inside_geofence = true: the geofence IS the enforcement zone.
        -- Inside → not relaxed (BLOCK applies); outside → relaxed (ALLOW).
        relaxed = not inside
        reason = inside and "inside_block_geofence" or "outside_block_geofence"
    else
        -- block_inside_geofence = false: the geofence is the safe/lab zone.
        -- Inside AND lab_relaxes_blocks → relaxed (ALLOW).
        relaxed = inside and self.config.lab_relaxes_blocks == true
        reason = inside and "inside_lab_geofence" or "outside_lab_geofence"
    end

    local nextState = {
        mode = inside and "lab" or "home",
        relaxed = relaxed,
        distance = distance,
        reason = reason,
    }

    -- Log only when mode changes (lab↔home) to keep the marker log concise.
    if self.lastState.mode ~= nextState.mode then
        self.logger:marker("location mode=" .. nextState.mode .. " distance=" .. string.format("%.2f", distance))
    end

    self:_setState(nextState)
end

-- start() begins GPS polling. An immediate poll on startup ensures the rest of
-- the system has a real mode value before the first enforce() call. Each
-- subsequent poll is wrapped in pcall so a GPS API error does not crash the timer.
function LocationMode:start()
    self:poll()
    if self.timer then self.timer:stop() end
    local pollSeconds = self.config.poll_seconds
        or (self.rootConfig.timers and self.rootConfig.timers.location_poll_seconds)
        or 5
    self.timer = hs.timer.doEvery(pollSeconds, function()
        local ok, err = pcall(function() self:poll() end)
        if not ok then
            self.logger:marker("location poll error=" .. tostring(err))
        end
    end)
end

-- mode() returns the human-readable current location mode ("lab", "home",
-- or "unknown"). Used by currentSnapshot() in init.lua for activity logging.
function LocationMode:mode()
    return self.lastState.mode
end

-- isRelaxed() is the single method init.lua cares about for enforcement decisions.
-- Returns true only when the GPS poll explicitly confirmed a relaxed state.
-- "unknown" maps to false (BLOCK-side) so GPS failures are fail-safe.
function LocationMode:isRelaxed()
    return self.lastState.relaxed == true
end

function LocationMode:statusSummary()
    local mode = self.lastState.relaxed and "ALLOW" or "BLOCK"
    return mode .. " via " .. tostring(self.lastState.reason or "unknown")
end

return LocationMode
