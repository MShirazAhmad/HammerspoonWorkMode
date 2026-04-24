-- Overlay is the visible intervention layer.
-- It decides which visual surface to use and when that surface should hide.
local RedWarningOverlay = require("modules.red_warning_overlay")
local BlockScreenOverlay = require("modules.block_screen_overlay")

local Overlay = {}
Overlay.__index = Overlay

function Overlay.new(config, logger, messages)
    local self = setmetatable({}, Overlay)
    self.config = config
    self.logger = logger
    self.messages = messages
    self.redWarningOverlay = RedWarningOverlay.new(config, messages)
    self.blockScreenOverlay = BlockScreenOverlay.new(config, messages)
    self.activeOverlay = nil
    self.timer = nil
    self.endsAt = 0
    self.testModeUntil = 0
    self.activePredicate = nil
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

local function countdownText(secondsLeft)
    -- Convert a raw second count into a human-friendly mm:ss label.
    local minutes = math.floor(secondsLeft / 60)
    local seconds = secondsLeft % 60
    return string.format("%02d:%02d", minutes, seconds)
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
    self.redWarningOverlay:hide()
    self.blockScreenOverlay:hide()
    self.activeOverlay = nil
    self.endsAt = 0
    self.testModeUntil = 0
    self.activePredicate = nil
end

function Overlay:_refresh()
    -- Refresh the countdown every second and auto-hide once time runs out.
    if not self.activeOverlay or not self.activeOverlay:isCreated() then
        return
    end
    if self.activePredicate and not self.activePredicate() then
        self:hide()
        return
    end
    local secondsLeft = math.max(0, math.ceil(self.endsAt - hs.timer.secondsSinceEpoch()))
    self.activeOverlay:setFooter(self:message("overlay.remaining_prefix") .. countdownText(secondsLeft))
    if secondsLeft <= 0 then
        self:hide()
    end
end

function Overlay:setStrictMode(active)
    -- Leaving strict/BLOCK mode should immediately clear any active overlay.
    self.strictMode = active == true
    if not self.strictMode and self.testModeUntil <= hs.timer.secondsSinceEpoch() then
        self:hide()
    end
end

function Overlay:show(message, durationSeconds, options)
    -- A generic display method used by specific intervention styles.
    options = options or {}
    if options.preserveTestMode ~= true then
        self.testModeUntil = 0
    end
    self.endsAt = hs.timer.secondsSinceEpoch() + math.max(1, durationSeconds or self.config.timers.overlay_default_seconds)
    self.activePredicate = nil
    self.blockScreenOverlay:hide()
    self.activeOverlay = self.redWarningOverlay
    self.activeOverlay:show(
        self:message("overlay.title"),
        tostring(message or self:message("overlay.fallback_message")),
        tostring(self:message("overlay.subtitle")),
        ""
    )
    self:_refresh()
    if self.timer then
        self.timer:stop()
    end
    self.timer = hs.timer.doEvery(1, function()
        self:_refresh()
    end)
end

function Overlay:showRedWarningTest(durationSeconds)
    durationSeconds = durationSeconds or 10
    self.testModeUntil = hs.timer.secondsSinceEpoch() + durationSeconds
    self:show(
        "RED WARNING TEST\n\nYou are going out of track.",
        durationSeconds,
        { preserveTestMode = true }
    )
end

function Overlay:showWhile(message, durationSeconds, activePredicate)
    self:show(message, durationSeconds)
    self.activePredicate = activePredicate
    self:_refresh()
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

function Overlay:showInterventionWhile(kind, details, violationCount, activePredicate)
    local reason = (details and details.reason) or self:message("overlay.fallback_reason")
    local duration = self.config.timers.overlay_default_seconds
    if violationCount >= (self.config.thresholds.max_violations_before_long_lockout or 3) then
        duration = self.config.timers.lockout_base_seconds * violationCount
    end
    self:showWhile(string.upper(kind) .. " " .. self:message("overlay.block_suffix") .. "\n\n" .. reason, duration, activePredicate)
    self.logger:marker("overlay kind=" .. tostring(kind) .. " duration=" .. tostring(duration) .. " conditional=true")
end

function Overlay:showTerminalPrompt(callback)
    self.endsAt = hs.timer.secondsSinceEpoch() + 300
    self.activePredicate = nil
    self.redWarningOverlay:hide()
    self.activeOverlay = self.blockScreenOverlay
    self.activeOverlay:show(
        self:message("terminal_guard.prompt.title"),
        self:message("terminal_guard.prompt.question"),
        self:message("terminal_guard.prompt.instructions"),
        self:message("terminal_guard.prompt.waiting")
    )

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
    local active = self.activeOverlay ~= nil and self.activeOverlay:isCreated() and self.endsAt > hs.timer.secondsSinceEpoch()
    if not active then
        return self:message("overlay.idle")
    end
    local secondsLeft = math.max(0, math.ceil(self.endsAt - hs.timer.secondsSinceEpoch()))
    return self:message("overlay.active_countdown_prefix") .. countdownText(secondsLeft)
end

return Overlay
