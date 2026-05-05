-- block_screen_overlay.lua — Hard-block / terminal-guard confirmation overlay.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- This overlay is used ONLY for the terminal guard Y/N prompt. It is distinct
-- from RedWarningOverlay (awareness) by design: the opaque black background
-- makes it impossible to interact with anything behind it, which forces the
-- user to make a conscious Y/N decision before continuing with terminal work.
--
-- MULTI-SCREEN SUPPORT
-- --------------------
-- _syncScreens() creates one canvas pair per connected display, mirrors the
-- text content across all of them, and shows the Y/N buttons on every screen.
-- This matches the approach in RedWarningOverlay and means the overlay covers
-- all displays — the user can respond from whichever screen they are looking at.
-- Screen changes (plug/unplug) are handled on the next show() call because
-- _syncScreens() is called at the start of every show().
--
-- TWO-CANVAS DESIGN PER SCREEN
-- ----------------------------
-- Each display has TWO canvases stacked at the same "screenSaver" level:
--
--   mainCanvas   — full-screen near-opaque black rectangle plus five text
--                  elements (title, body, instructions, footer/status).
--                  Created first, so it sits below the buttonCanvas in z-order.
--
--   buttonCanvas — transparent except for the two clickable buttons.
--                  Created second, so it sits above mainCanvas in z-order.
--                  Only shown when onConfirm is set (i.e. during a Y/N prompt).
--
-- Why two canvases instead of toggling elements on one?
--   Hammerspoon canvas elements do not support a "hidden" attribute (raises
--   "attribute name hidden unrecognized"). Showing/hiding a whole canvas with
--   canvas:show() / canvas:hide() is the supported alternative.
--
-- MOUSE INTERACTION (works without Accessibility permissions)
-- -----------------------------------------------------------
-- buttonCanvas uses trackMouseUp = true on all four button elements and a
-- canvas-level mouseCallback that checks the element id ("y_button",
-- "y_label", "n_button", "n_label"). The callback calls onConfirm(true/false)
-- and clears onConfirm so subsequent clicks are no-ops.
--
-- The `fire` closure passed from Overlay:showTerminalPrompt() is stored as
-- onConfirm. The `fired` guard inside fire() prevents double-invocation if
-- the keyboard eventtap (in overlay.lua) and a mouse click fire concurrently.
--
-- setFooter() is a no-op while buttons are shown because the button canvas
-- occupies the same screen region as element [5] (the footer text area).

local BlockScreenOverlay = {}
BlockScreenOverlay.__index = BlockScreenOverlay

function BlockScreenOverlay.new(config, messages)
    local self = setmetatable({}, BlockScreenOverlay)
    self.config = config
    self.messages = messages
    -- Parallel arrays: canvases[i] is the main canvas for screen i,
    -- buttonCanvases[i] is the transparent button overlay for screen i.
    self.canvases = {}
    self.buttonCanvases = {}
    -- onConfirm holds the fire() closure from Overlay:showTerminalPrompt().
    -- Cleared by hide() or immediately after the first click.
    self.onConfirm = nil
    return self
end

function BlockScreenOverlay:_settings()
    return self.config.block_screen_overlay or {}
end

-- allFrames returns one fullFrame per connected display. Falls back to the
-- main screen if hs.screen.allScreens() returns an empty list (e.g. display
-- enumeration has not completed yet at startup).
local function allFrames()
    local frames = {}
    for _, screen in ipairs(hs.screen.allScreens() or {}) do
        table.insert(frames, screen:fullFrame())
    end
    if #frames == 0 then
        table.insert(frames, hs.screen.mainScreen():fullFrame())
    end
    return frames
end

-- newMainCanvas creates the near-opaque black background with five text
-- elements. Element indices are fixed ([1]=bg, [2]=title, [3]=body,
-- [4]=instructions, [5]=footer/status) so show() and setFooter() can index
-- them directly without searching.
local function newMainCanvas(frame, settings)
    local c = hs.canvas.new(frame)
    c:level("screenSaver")
    c:behavior({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" })
    c[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = settings.background_color or { red = 0, green = 0, blue = 0, alpha = 0.96 },
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
    }
    c[2] = {
        type = "text", text = "",
        textSize = 64, textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "10%", y = "18%", w = "80%", h = "12%" },
    }
    c[3] = {
        type = "text", text = "",
        textSize = 34, textColor = { white = 1, alpha = 0.96 },
        textAlignment = "center",
        frame = { x = "12%", y = "38%", w = "76%", h = "22%" },
    }
    c[4] = {
        type = "text", text = "",
        textSize = 26, textColor = { white = 1, alpha = 0.86 },
        textAlignment = "center",
        frame = { x = "16%", y = "60%", w = "68%", h = "12%" },
    }
    -- Element [5] is the footer/status text. It is cleared (text = "") while
    -- buttons are shown because the buttonCanvas occupies the same vertical band.
    c[5] = {
        type = "text", text = "",
        textSize = 44, textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "30%", y = "78%", w = "40%", h = "10%" },
    }
    return c
end

-- newButtonCanvas creates a transparent canvas with two clickable buttons:
--   Green "Y — Allow" button on the left (x=15–43%, y=78–89%)
--   Red   "N — Block" button on the right (x=57–85%, y=78–89%)
-- trackMouseUp = true on all four elements ensures mouseCallback receives the
-- event regardless of whether the user clicks the rectangle or the text label.
-- onClickFn is the shared fire() closure; it is the same function on every
-- screen so one click on any display dismisses all overlays.
local function newButtonCanvas(frame, onClickFn)
    local c = hs.canvas.new(frame)
    c:level("screenSaver")
    c:behavior({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" })
    c[1] = {
        type = "rectangle", action = "fill",
        fillColor = { red = 0.05, green = 0.52, blue = 0.05, alpha = 0.92 },
        roundedRectRadii = { xRadius = 14, yRadius = 14 },
        frame = { x = "15%", y = "78%", w = "28%", h = "11%" },
        trackMouseUp = true, id = "y_button",
    }
    c[2] = {
        type = "rectangle", action = "fill",
        fillColor = { red = 0.62, green = 0.08, blue = 0.08, alpha = 0.92 },
        roundedRectRadii = { xRadius = 14, yRadius = 14 },
        frame = { x = "57%", y = "78%", w = "28%", h = "11%" },
        trackMouseUp = true, id = "n_button",
    }
    c[3] = {
        type = "text", text = "Y  —  Allow",
        textSize = 38, textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "15%", y = "79%", w = "28%", h = "9%" },
        trackMouseUp = true, id = "y_label",
    }
    c[4] = {
        type = "text", text = "N  —  Block",
        textSize = 38, textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "57%", y = "79%", w = "28%", h = "9%" },
        trackMouseUp = true, id = "n_label",
    }
    -- id-based dispatch: the element id tells us which button was clicked
    -- without needing coordinate math. onConfirm is cleared before calling
    -- onClickFn so a second click from the same or another screen is a no-op.
    c:mouseCallback(function(canvas, message, id, x, y)
        if message ~= "mouseUp" then return end
        if id == "y_button" or id == "y_label" then
            onClickFn(true)
        elseif id == "n_button" or id == "n_label" then
            onClickFn(false)
        end
    end)
    return c
end

-- _syncScreens reconciles self.canvases / self.buttonCanvases with the current
-- set of connected displays. Called at the start of every show() so changes
-- (display connected/disconnected since last show) are handled automatically.
-- Canvases for removed screens are deleted; canvases for new screens are
-- created; existing canvases are resized if their frame changed.
function BlockScreenOverlay:_syncScreens()
    local frames = allFrames()
    local settings = self:_settings()

    while #self.canvases < #frames do
        local idx = #self.canvases + 1
        table.insert(self.canvases, newMainCanvas(frames[idx], settings))
        -- Each buttonCanvas captures a reference to self.onConfirm via a closure
        -- over the shared onClickFn. The outer `if self.onConfirm then` guard
        -- means only the first click (from any screen) triggers the callback.
        table.insert(self.buttonCanvases, newButtonCanvas(frames[idx], function(allowed)
            if self.onConfirm then
                local cb = self.onConfirm
                self.onConfirm = nil
                cb(allowed)
            end
        end))
    end

    while #self.canvases > #frames do
        local mc = table.remove(self.canvases)
        mc:delete()
        local bc = table.remove(self.buttonCanvases)
        bc:delete()
    end

    for i, frame in ipairs(frames) do
        self.canvases[i]:frame(frame)
        self.buttonCanvases[i]:frame(frame)
    end
end

-- show() is called by Overlay:showTerminalPrompt(). The optional `onConfirm`
-- parameter (5th arg) activates the Y/N button canvases. When nil the overlay
-- behaves as a plain countdown display (footer text is shown, no buttons).
function BlockScreenOverlay:show(title, body, subtitle, footer, onConfirm)
    self:_syncScreens()
    self.onConfirm = onConfirm

    for _, c in ipairs(self.canvases) do
        c[2].text = tostring(title or "")
        c[3].text = tostring(body or "")
        c[4].text = tostring(subtitle or "")
        -- Footer is blanked while buttons are shown; the button canvas visually
        -- replaces element [5]'s vertical band.
        if onConfirm then
            c[5].text = ""
        else
            c[5].text = tostring(footer or "")
        end
        c:show()
    end

    for _, bc in ipairs(self.buttonCanvases) do
        if onConfirm then
            bc:show()
        else
            bc:hide()
        end
    end
end

-- setFooter is called by Overlay:_refresh() every second to update the
-- countdown text. It is a no-op while confirm buttons are displayed because
-- the buttonCanvas occupies that screen region and a countdown number there
-- would be visually confusing.
function BlockScreenOverlay:setFooter(text)
    if not self.onConfirm then
        for _, c in ipairs(self.canvases) do
            c[5].text = tostring(text or "")
        end
    end
end

-- hide() tears down all visual state. Clearing onConfirm here means any
-- in-flight mouseCallback invocation from another screen will find nil and
-- become a no-op, preventing a second call to the fire() closure.
function BlockScreenOverlay:hide()
    self.onConfirm = nil
    for _, c in ipairs(self.canvases) do
        c:hide()
    end
    for _, bc in ipairs(self.buttonCanvases) do
        bc:hide()
    end
end

-- isCreated returns true if at least one canvas has been created. Used by
-- Overlay:_refresh() to avoid calling setFooter on an uninitialised object.
function BlockScreenOverlay:isCreated()
    return #self.canvases > 0
end

return BlockScreenOverlay
