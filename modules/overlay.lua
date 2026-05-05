-- overlay.lua — Unified gateway between init.lua enforcement logic and the two
-- concrete overlay implementations (RedWarningOverlay and BlockScreenOverlay).
--
-- ROLE IN THE SYSTEM
-- ------------------
-- init.lua never talks to RedWarningOverlay or BlockScreenOverlay directly.
-- All overlay decisions flow through this module, which selects the right
-- visual surface and manages the shared countdown timer and eventtap lifecycle.
--
-- TWO OVERLAY TYPES
-- -----------------
--   RedWarningOverlay  — Pulsing red full-screen awareness overlay. Used for
--                        browser/app/classifier violations. The user CAN still
--                        see and close the offending app behind it. The overlay
--                        hides automatically when the countdown expires or the
--                        activePredicate returns false.
--
--   BlockScreenOverlay — Near-opaque black full-screen blocking prompt. Used
--                        only for the terminal guard Y/N question. The user
--                        CANNOT interact with anything behind it. It hides only
--                        when the user clicks Y/N (or after the 300 s timeout).
--                        Shows clickable green/red buttons on EVERY connected
--                        display so the user can respond from any screen.
--
-- COUNTDOWN TIMER
-- ---------------
-- A single hs.timer.doEvery(1, _refresh) drives countdowns for both overlay
-- types. _refresh() reads self.endsAt and calls hide() when time runs out.
-- For terminal prompts the timer also serves as the 300 s safety net in case
-- mouse/keyboard input never arrives.
--
-- TERMINAL PROMPT DISMISSAL (two independent paths, one fires first)
-- ------------------------------------------------------------------
--   Path A — Mouse click on Y/N button canvas (no Accessibility needed).
--             Implemented via hs.canvas mouseCallback in BlockScreenOverlay.
--   Path B — Keyboard Y or N via hs.eventtap (requires Accessibility permission
--             in System Settings → Privacy & Security → Accessibility).
--   Both paths call the same `fire()` closure. A `fired` boolean guard inside
--   fire() ensures the callback executes exactly once regardless of which path
--   wins. Stopping the eventtap from within its own callback is safe in
--   Hammerspoon (the stop is deferred until after the callback returns).

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
    -- activeOverlay points to whichever of the two is currently shown (or nil).
    self.activeOverlay = nil
    -- timer drives the one-second _refresh() countdown tick.
    self.timer = nil
    -- endsAt is a Unix epoch float set when an overlay is shown.
    self.endsAt = 0
    -- testModeUntil keeps the overlay alive during manual tests even after
    -- strictMode is cleared by setStrictMode(false).
    self.testModeUntil = 0
    -- activePredicate, when set, lets the overlay dismiss itself early if the
    -- triggering condition (e.g. a distracting tab) is no longer true.
    self.activePredicate = nil
    -- strictMode mirrors the global BLOCK/ALLOW state so hide() knows whether
    -- to actually hide when setStrictMode(false) is called.
    self.strictMode = false
    -- terminalPromptTap is the keyboard Y/N eventtap (nil when not prompting).
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
    local minutes = math.floor(secondsLeft / 60)
    local seconds = secondsLeft % 60
    return string.format("%02d:%02d", minutes, seconds)
end

-- hide() is the single teardown path for both overlay types. It stops the
-- countdown timer, stops the terminal eventtap (if running), hides both
-- overlay surfaces, and resets all tracking fields to their idle state.
function Overlay:hide()
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

-- _refresh() is called once per second by the countdown timer. It updates the
-- footer countdown text and calls hide() when time runs out. If an
-- activePredicate was supplied and now returns false (e.g. the browser tab was
-- closed), the overlay dismisses itself early.
function Overlay:_refresh()
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

-- setStrictMode is called by enforce() on every pass. Leaving strict/BLOCK mode
-- hides any active overlay immediately unless a test is running (testModeUntil).
function Overlay:setStrictMode(active)
    self.strictMode = active == true
    if not self.strictMode and self.testModeUntil <= hs.timer.secondsSinceEpoch() then
        self:hide()
    end
end

-- show() is the internal method for red warning overlays (violations).
-- It sets endsAt, shows RedWarningOverlay, and starts the countdown timer.
-- options.preserveTestMode prevents testModeUntil from being cleared when the
-- test itself calls show() as part of its display sequence.
function Overlay:show(message, durationSeconds, options)
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
    if self.timer then self.timer:stop() end
    self.timer = hs.timer.doEvery(1, function()
        self:_refresh()
    end)
end

-- showRedWarningTest is triggered from the menu bar "Test red warning" action.
-- It sets testModeUntil so setStrictMode(false) won't dismiss the test overlay
-- before the user can see it, even if they are currently in ALLOW mode.
function Overlay:showRedWarningTest(durationSeconds)
    durationSeconds = durationSeconds or 10
    self.testModeUntil = hs.timer.secondsSinceEpoch() + durationSeconds
    self:show(
        "RED WARNING TEST\n\nYou are going out of track.",
        durationSeconds,
        { preserveTestMode = true }
    )
end

-- showWhile is like show() but accepts an activePredicate. The overlay will
-- dismiss itself early if the predicate returns false on the next timer tick.
-- Used for browser violations where the overlay should vanish once the tab is
-- closed, without waiting for the full countdown.
function Overlay:showWhile(message, durationSeconds, activePredicate)
    self:show(message, durationSeconds)
    self.activePredicate = activePredicate
    self:_refresh()
end

-- showIntervention maps an enforcement result (kind + details) to a timed
-- red warning overlay. Duration escalates after max_violations_before_long_lockout
-- repeated violations in the same BLOCK session.
function Overlay:showIntervention(kind, details, violationCount)
    local reason = (details and details.reason) or self:message("overlay.fallback_reason")
    local duration = self.config.timers.overlay_default_seconds
    if violationCount >= (self.config.thresholds.max_violations_before_long_lockout or 3) then
        duration = self.config.timers.lockout_base_seconds * violationCount
    end
    self:show(string.upper(kind) .. " " .. self:message("overlay.block_suffix") .. "\n\n" .. reason, duration)
    self.logger:marker("overlay kind=" .. tostring(kind) .. " duration=" .. tostring(duration))
end

-- showInterventionWhile is showIntervention + activePredicate. Used for browser
-- violations so the overlay disappears as soon as the offending tab is gone.
function Overlay:showInterventionWhile(kind, details, violationCount, activePredicate)
    local reason = (details and details.reason) or self:message("overlay.fallback_reason")
    local duration = self.config.timers.overlay_default_seconds
    if violationCount >= (self.config.thresholds.max_violations_before_long_lockout or 3) then
        duration = self.config.timers.lockout_base_seconds * violationCount
    end
    self:showWhile(string.upper(kind) .. " " .. self:message("overlay.block_suffix") .. "\n\n" .. reason, duration, activePredicate)
    self.logger:marker("overlay kind=" .. tostring(kind) .. " duration=" .. tostring(duration) .. " conditional=true")
end

-- showTerminalPrompt shows the full-screen Y/N terminal guard prompt.
-- It differs from show() in three ways:
--   1. Uses BlockScreenOverlay (opaque black) instead of RedWarningOverlay (red).
--   2. Shows clickable Y/N buttons on every connected display (no Accessibility
--      needed for the mouse path).
--   3. Also installs a keyDown eventtap for keyboard Y/N (requires Accessibility).
--
-- DISMISSAL: either the mouse path (BlockScreenOverlay.buttonCanvas mouseCallback)
-- or the keyboard path (terminalPromptTap) calls fire(). The `fired` guard
-- ensures callback executes exactly once. After fire() runs, hide() tears down
-- both the overlay and the eventtap.
--
-- TIMEOUT: a 300 s countdown timer auto-dismisses via _refresh() if neither
-- input path fires (safety net only — the user should click or type Y/N).
function Overlay:showTerminalPrompt(callback)
    self.endsAt = hs.timer.secondsSinceEpoch() + 300
    self.activePredicate = nil
    self.redWarningOverlay:hide()
    self.activeOverlay = self.blockScreenOverlay

    -- `fired` prevents double-invocation if mouse and keyboard both fire
    -- within the same Hammerspoon run loop iteration.
    local fired = false
    local function fire(allowed)
        if fired then return end
        fired = true
        if self.terminalPromptTap then
            self.terminalPromptTap:stop()
            self.terminalPromptTap = nil
        end
        self:hide()
        if callback then
            callback(allowed)
        end
    end

    -- Pass `fire` to the block screen overlay as the mouse-click handler.
    -- This path works even without Accessibility permissions because canvas
    -- mouseCallback uses AppKit NSTrackingArea, not CGEvent taps.
    self.activeOverlay:show(
        self:message("terminal_guard.prompt.title"),
        self:message("terminal_guard.prompt.question"),
        self:message("terminal_guard.prompt.instructions"),
        self:message("terminal_guard.prompt.waiting"),
        fire
    )

    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    if self.terminalPromptTap then
        self.terminalPromptTap:stop()
        self.terminalPromptTap = nil
    end

    -- Keyboard path: requires Accessibility. Checks both character and keyCode
    -- so the detection works even if getCharactersIgnoringModifiers() returns
    -- something unexpected (e.g. on non-QWERTY layouts, keyCode 16=Y, 45=N).
    self.terminalPromptTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
        local key = tostring(event:getCharactersIgnoringModifiers() or ""):lower()
        local keyCode = event:getKeyCode()
        local isY = key == "y" or keyCode == 16
        local isN = key == "n" or keyCode == 45
        if not isY and not isN then
            return true  -- swallow all other keys while the prompt is shown
        end
        fire(isY)
        return true
    end)
    self.terminalPromptTap:start()

    -- 300 s safety-net countdown. Also updates the footer text each second
    -- via _refresh() → activeOverlay:setFooter(), though BlockScreenOverlay
    -- suppresses setFooter when confirm buttons are shown.
    self.timer = hs.timer.doEvery(1, function()
        self:_refresh()
    end)
end

-- showFolderApprovalPrompt shows the full-screen Y/N prompt for path approval.
-- Similar to showTerminalPrompt but with a path-specific message.
function Overlay:showFolderApprovalPrompt(folderPath, callback)
    self.endsAt = hs.timer.secondsSinceEpoch() + 300
    self.activePredicate = nil
    self.redWarningOverlay:hide()
    self.activeOverlay = self.blockScreenOverlay

    -- `fired` prevents double-invocation if mouse and keyboard both fire
    local fired = false
    local function fire(approved)
        if fired then return end
        fired = true
        if self.terminalPromptTap then
            self.terminalPromptTap:stop()
            self.terminalPromptTap = nil
        end
        self:hide()
        if callback then
            callback(approved)
        end
    end

    -- Truncate very long paths for display
    local displayPath = folderPath
    if #displayPath > 60 then
        displayPath = "…" .. displayPath:sub(-57)
    end

    -- Show the folder approval prompt with custom message
    self.activeOverlay:show(
        self:message("folder_blocker.prompt.title", "IS THIS WORK?"),
        self:message("folder_blocker.prompt.question", "Allow this path during work mode?\n" .. displayPath),
        self:message("folder_blocker.prompt.instructions", "Y = Allow  |  N = Block"),
        self:message("folder_blocker.prompt.waiting", "Waiting for your response..."),
        fire
    )

    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    if self.terminalPromptTap then
        self.terminalPromptTap:stop()
        self.terminalPromptTap = nil
    end

    -- Keyboard path for Y/N
    self.terminalPromptTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
        local key = tostring(event:getCharactersIgnoringModifiers() or ""):lower()
        local keyCode = event:getKeyCode()
        local isY = key == "y" or keyCode == 16
        local isN = key == "n" or keyCode == 45
        if not isY and not isN then
            return true  -- swallow all other keys
        end
        fire(isY)
        return true
    end)
    self.terminalPromptTap:start()

    -- 300 s safety-net countdown
    self.timer = hs.timer.doEvery(1, function()
        self:_refresh()
    end)
end

-- statusSummary is called by init.lua to populate the menu bar dashboard.
-- It returns a human-readable string describing the current overlay state.
function Overlay:statusSummary()
    local active = self.activeOverlay ~= nil and self.activeOverlay:isCreated() and self.endsAt > hs.timer.secondsSinceEpoch()
    if not active then
        return self:message("overlay.idle")
    end
    local secondsLeft = math.max(0, math.ceil(self.endsAt - hs.timer.secondsSinceEpoch()))
    return self:message("overlay.active_countdown_prefix") .. countdownText(secondsLeft)
end

return Overlay
