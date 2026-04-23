-- Overlay is the visible intervention layer.
-- It builds one reusable full-screen canvas and updates the countdown text
-- whenever a warning or lockout is active.
local Overlay = {}
Overlay.__index = Overlay

function Overlay.new(config, logger, messages)
    local self = setmetatable({}, Overlay)
    self.config = config
    self.logger = logger
    self.messages = messages
    self.canvas = nil
    self.timer = nil
    self.endsAt = 0
    self.strictMode = false
    self.terminalPromptTap = nil
    return self
end

function Overlay:message(key, fallback)
    if self.messages then
        return self.messages:get(key, fallback)
    end
    return fallback or ""
end

function Overlay:title()
    return "Overlay"
end

function Overlay:description()
    return "Shows the full-screen intervention and countdown after a detected violation."
end

local function fullFrame()
    -- Use the main screen's full frame so the overlay covers the desktop and
    -- fullscreen contexts consistently.
    return hs.screen.mainScreen():fullFrame()
end

local function countdownText(secondsLeft)
    -- Convert a raw second count into a human-friendly mm:ss label.
    local minutes = math.floor(secondsLeft / 60)
    local seconds = secondsLeft % 60
    return string.format("%02d:%02d", minutes, seconds)
end

function Overlay:ensureCanvas()
    -- Build the canvas once and reuse it for every future intervention.
    if self.canvas then
        return
    end

    local frame = fullFrame()
    self.canvas = hs.canvas.new(frame)
    self.canvas:level("screenSaver")
    self.canvas:behavior({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" })

    -- Element 1 is the dark background that takes over the screen.
    self.canvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = { red = 0, green = 0, blue = 0, alpha = self.config.overlay.background_alpha or 0.96 },
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
    }
    -- Element 2 is the fixed title banner.
    self.canvas[2] = {
        type = "text",
        text = self:message("overlay.title"),
        textSize = 68,
        textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "10%", y = "18%", w = "80%", h = "12%" },
    }
    -- Element 3 is the dynamic reason text for the current violation.
    self.canvas[3] = {
        type = "text",
        text = "",
        textSize = 34,
        textColor = { red = 1, green = 0.35, blue = 0.35, alpha = 1 },
        textAlignment = "center",
        frame = { x = "12%", y = "38%", w = "76%", h = "22%" },
    }
    -- Element 4 is the softer subtitle or guidance line.
    self.canvas[4] = {
        type = "text",
        text = "",
        textSize = 26,
        textColor = { white = 1, alpha = 0.92 },
        textAlignment = "center",
        frame = { x = "16%", y = "60%", w = "68%", h = "12%" },
    }
    -- Element 5 is the live countdown timer.
    self.canvas[5] = {
        type = "text",
        text = "",
        textSize = 44,
        textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "30%", y = "78%", w = "40%", h = "10%" },
    }
end

function Overlay:hide()
    -- Hiding the overlay also stops the countdown timer so there is no orphaned
    -- timer continuing to run in the background.
    if self.terminalPromptTap then
        self.terminalPromptTap:stop()
        self.terminalPromptTap = nil
    end
    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    if self.canvas then
        self.canvas:hide()
    end
    self.endsAt = 0
end

function Overlay:_refresh()
    -- Refresh the countdown every second and auto-hide once time runs out.
    if not self.canvas then
        return
    end
    local secondsLeft = math.max(0, math.ceil(self.endsAt - hs.timer.secondsSinceEpoch()))
    self.canvas[5].text = self:message("overlay.remaining_prefix") .. countdownText(secondsLeft)
    if secondsLeft <= 0 then
        self:hide()
    end
end

function Overlay:setStrictMode(active)
    -- Leaving strict/BLOCK mode should immediately clear any active overlay.
    self.strictMode = active == true
    if not self.strictMode then
        self:hide()
    end
end

function Overlay:show(message, durationSeconds)
    -- A generic display method used by specific intervention styles.
    self:ensureCanvas()
    self.canvas[2].text = self:message("overlay.title")
    self.canvas[3].text = tostring(message or self:message("overlay.fallback_message"))
    self.canvas[4].text = tostring(self:message("overlay.subtitle"))
    self.endsAt = hs.timer.secondsSinceEpoch() + math.max(1, durationSeconds or self.config.timers.overlay_default_seconds)
    self:_refresh()
    self.canvas:show()
    if self.timer then
        self.timer:stop()
    end
    self.timer = hs.timer.doEvery(1, function()
        self:_refresh()
    end)
end

function Overlay:showIntervention(kind, details, violationCount)
    -- Escalate duration once the same session shows repeated drift.
    local reason = (details and details.reason) or self:message("overlay.fallback_reason")
    local duration = self.config.timers.overlay_default_seconds
    if violationCount >= (self.config.thresholds.max_violations_before_long_lockout or 3) then
        duration = self.config.timers.lockout_base_seconds * violationCount
    end
    self:show(string.upper(kind) .. " " .. self:message("overlay.block_suffix") .. "\n\n" .. reason, duration)
    self.logger:marker("overlay kind=" .. tostring(kind) .. " duration=" .. tostring(duration))
end

function Overlay:showTerminalPrompt(callback)
    self:ensureCanvas()
    self.canvas[2].text = self:message("terminal_guard.prompt.title")
    self.canvas[3].text = self:message("terminal_guard.prompt.question")
    self.canvas[4].text = self:message("terminal_guard.prompt.instructions")
    self.canvas[5].text = self:message("terminal_guard.prompt.waiting")
    self.endsAt = hs.timer.secondsSinceEpoch() + 300
    self.canvas:show()

    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    if self.terminalPromptTap then
        self.terminalPromptTap:stop()
        self.terminalPromptTap = nil
    end

    self.terminalPromptTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
        local key = tostring(event:getCharactersIgnoringModifiers() or ""):lower()
        if key ~= "y" and key ~= "n" then
            return true
        end

        if self.terminalPromptTap then
            self.terminalPromptTap:stop()
            self.terminalPromptTap = nil
        end
        self:hide()

        if callback then
            callback(key == "y")
        end
        return true
    end)
    self.terminalPromptTap:start()
end

function Overlay:statusSummary()
    local active = self.canvas ~= nil and self.endsAt > hs.timer.secondsSinceEpoch()
    if not active then
        return self:message("overlay.idle")
    end
    local secondsLeft = math.max(0, math.ceil(self.endsAt - hs.timer.secondsSinceEpoch()))
    return self:message("overlay.active_countdown_prefix") .. countdownText(secondsLeft)
end

return Overlay
