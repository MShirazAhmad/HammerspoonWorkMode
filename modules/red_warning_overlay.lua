-- red_warning_overlay.lua — Pulsing full-screen awareness overlay for violations.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- RedWarningOverlay is the SOFT enforcement surface. It covers all displays
-- with a red (or image-backed) full-screen overlay and a countdown timer, but
-- it does NOT intercept mouse clicks — the user can still see and interact
-- with the app behind it (to close a distracting tab, for example).
-- This contrasts with BlockScreenOverlay, which is opaque, mouse-blocking,
-- and used only for the terminal guard hard prompt.
--
-- Shown by: Overlay:showIntervention() and Overlay:showInterventionWhile()
-- Hidden by: Overlay:hide() when countdown expires or activePredicate → false.
--
-- MULTI-SCREEN SUPPORT
-- --------------------
-- _fitToDesktopScreens() creates one canvas per connected display (via
-- hs.screen.allScreens()) and is called on every show(). Canvases are
-- re-used across show() calls; only the count and frames are updated.
-- Surplus canvases are deleted; new screens get a fresh canvas.
--
-- COORDINATE SYSTEM NOTE
-- ----------------------
-- Each canvas is created slightly larger than its screen (expandedFrame adds
-- 160 px padding on all sides). This overdraw ensures the red glow reaches
-- behind the macOS menu bar and Dock, which sit in special regions that would
-- otherwise show through a normally-sized canvas. The text elements are then
-- positioned relative to the REAL screen frame using offsetX/offsetY so they
-- appear centered on the visible area, not inside the overdraw gutter.
--
-- PULSE ANIMATION
-- ---------------
-- A fast timer (default 30 ms tick) calls _refreshPulse() which computes a
-- sinusoidal alpha value from elapsed time. The pulse drives the background
-- rectangle or image alpha between min_alpha and max_alpha over cycle_seconds.
-- Pulse can be disabled in config.red_warning_overlay.background_pulse.enabled.
--
-- BACKGROUND IMAGE
-- ----------------
-- If config.red_warning_overlay.background_image_path points to a valid image
-- (SVG, PNG, etc.), it is used instead of the plain red rectangle. The image
-- is loaded once in newCanvas and reused across show() calls on that canvas.
-- If the path is missing or the image fails to load, falls back to a solid
-- red rectangle.

local RedWarningOverlay = {}
RedWarningOverlay.__index = RedWarningOverlay

function RedWarningOverlay.new(config, messages)
    local self = setmetatable({}, RedWarningOverlay)
    self.config = config
    self.messages = messages
    -- canvases[i] corresponds to hs.screen.allScreens()[i].
    self.canvases = {}
    -- backgroundElementTypes[i] is "image" or "rectangle" for canvases[i],
    -- used by _setBackgroundAlpha to know which property to animate.
    self.backgroundElementTypes = {}
    self.pulseTimer = nil
    self.pulseStartedAt = 0
    return self
end

function RedWarningOverlay:message(key, fallback)
    if self.messages then
        return self.messages:get(key, fallback)
    end
    return fallback or ""
end

function RedWarningOverlay:_settings()
    return self.config.red_warning_overlay or {}
end

-- imageElement tries to load a background image from path. Returns nil if the
-- path is empty or the image cannot be loaded, which causes the caller to fall
-- back to a plain red rectangle.
local function imageElement(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local image = hs.image.imageFromPath(path)
    if not image then
        return nil
    end
    return {
        type = "image",
        image = image,
        imageScaling = "scaleToFill",
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
    }
end

-- screenFrames returns one fullFrame per connected display (never empty).
local function screenFrames()
    local frames = {}
    for _, screen in ipairs(hs.screen.allScreens() or {}) do
        table.insert(frames, screen:fullFrame())
    end
    if #frames == 0 then
        table.insert(frames, hs.screen.mainScreen():fullFrame())
    end
    return frames
end

-- expandedFrame adds 160 px overdraw on all sides of a screen frame.
-- This is needed because macOS reserves the menu bar and Dock in regions that
-- sit outside the "normal" screen content area. Without overdraw the red
-- background would stop short and the reserved areas would show through.
local function expandedFrame(frame)
    local padding = 160
    return {
        x = frame.x - padding,
        y = frame.y - padding,
        w = frame.w + (padding * 2),
        h = frame.h + (padding * 2),
    }
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

-- _setBackgroundAlpha updates the alpha of canvas element [1] for all canvases.
-- For image elements it uses imageAlpha (scaled by 0.5 to keep images subtle),
-- for rectangle elements it sets fillColor.alpha directly.
function RedWarningOverlay:_setBackgroundAlpha(alpha)
    for index, canvas in ipairs(self.canvases) do
        if self.backgroundElementTypes[index] == "image" then
            canvas[1].imageAlpha = alpha
        elseif canvas[1].fillColor then
            canvas[1].fillColor.alpha = alpha
        end
    end
end

-- _refreshPulse computes the current pulse alpha using a triangle wave over
-- cycle_seconds and applies it via _setBackgroundAlpha. Called every tick_seconds
-- (default 30 ms) by pulseTimer.
function RedWarningOverlay:_refreshPulse()
    if #self.canvases == 0 then return end

    local pulse = self:_settings().background_pulse or {}
    local minimum = clamp(pulse.min_alpha or 0.45, 0, 1)
    local maximum = clamp(pulse.max_alpha or 1.0, minimum, 1)
    local cycle = math.max(0.1, tonumber(pulse.cycle_seconds) or 2.8)
    local elapsed = (hs.timer.secondsSinceEpoch() - self.pulseStartedAt) % cycle
    local phase = elapsed / cycle
    -- Triangle wave: rises 0→1 over the first half-cycle, falls 1→0 over the second.
    local amount = phase < 0.5 and (phase * 2) or ((1 - phase) * 2)

    self:_setBackgroundAlpha(minimum + ((maximum - minimum) * amount))
end

-- _startPulse initialises the pulse animation. If pulse.enabled = false in
-- config, it sets a static alpha instead.
function RedWarningOverlay:_startPulse()
    if self.pulseTimer then
        self.pulseTimer:stop()
        self.pulseTimer = nil
    end

    local settings = self:_settings()
    local pulse = settings.background_pulse or {}
    if pulse.enabled == false then
        self:_setBackgroundAlpha(settings.background_alpha or 0.96)
        return
    end

    self.pulseStartedAt = hs.timer.secondsSinceEpoch()
    self:_refreshPulse()
    self.pulseTimer = hs.timer.doEvery(math.max(0.016, tonumber(pulse.tick_seconds) or 0.03), function()
        self:_refreshPulse()
    end)
end

-- _newCanvas creates a fresh canvas for one display frame. The canvas uses
-- "assistiveTechHigh" level (above Dock/menu/status bars) rather than
-- "screenSaver" because the red overlay is awareness-only and should not
-- prevent the user from dismissing the offending app.
-- Element indices: [1]=background, [2]=title, [3]=body, [4]=subtitle, [5]=footer.
function RedWarningOverlay:_newCanvas(frame)
    local settings = self:_settings()
    local canvas = hs.canvas.new(expandedFrame(frame))
    canvas:level("assistiveTechHigh")
    canvas:behavior({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary", "ignoresCycle", "transient" })

    canvas[1] = imageElement(settings.background_image_path) or {
        type = "rectangle",
        action = "fill",
        fillColor = { red = 0.45, green = 0, blue = 0, alpha = settings.background_alpha or 0.96 },
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
    }
    canvas[2] = {
        type = "text", text = self:message("overlay.title"),
        textSize = 68, textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "10%", y = "18%", w = "80%", h = "12%" },
    }
    canvas[3] = {
        type = "text", text = "",
        textSize = 34, textColor = { red = 1, green = 0.35, blue = 0.35, alpha = 1 },
        textAlignment = "center",
        frame = { x = "12%", y = "38%", w = "76%", h = "22%" },
    }
    canvas[4] = {
        type = "text", text = "",
        textSize = 26, textColor = { white = 1, alpha = 0.92 },
        textAlignment = "center",
        frame = { x = "16%", y = "60%", w = "68%", h = "12%" },
    }
    canvas[5] = {
        type = "text", text = "",
        textSize = 44, textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "30%", y = "78%", w = "40%", h = "10%" },
    }
    return canvas
end

-- _fitCanvas repositions text elements inside a canvas whose frame was resized
-- (e.g. after display rearrangement). The background element uses the full
-- expanded canvas; text elements are aligned to the real screen frame using
-- offsetX/offsetY to account for the overdraw padding.
function RedWarningOverlay:_fitCanvas(canvas, frame)
    local canvasFrame = expandedFrame(frame)
    canvas:frame(canvasFrame)
    local width = frame.w
    local height = frame.h
    local offsetX = frame.x - canvasFrame.x
    local offsetY = frame.y - canvasFrame.y
    canvas[1].frame = { x = 0, y = 0, w = canvasFrame.w, h = canvasFrame.h }
    canvas[2].frame = { x = offsetX + (width * 0.10), y = offsetY + (height * 0.18), w = width * 0.80, h = height * 0.12 }
    canvas[3].frame = { x = offsetX + (width * 0.12), y = offsetY + (height * 0.38), w = width * 0.76, h = height * 0.22 }
    canvas[4].frame = { x = offsetX + (width * 0.16), y = offsetY + (height * 0.60), w = width * 0.68, h = height * 0.12 }
    canvas[5].frame = { x = offsetX + (width * 0.30), y = offsetY + (height * 0.78), w = width * 0.40, h = height * 0.10 }
end

-- _fitToDesktopScreens reconciles self.canvases with the current screen list.
-- Surplus canvases are deleted; missing ones are created; all are resized.
-- Called at the start of every show() so display changes take effect immediately.
function RedWarningOverlay:_fitToDesktopScreens()
    local frames = screenFrames()
    while #self.canvases < #frames do
        table.insert(self.canvases, self:_newCanvas(frames[#self.canvases + 1]))
    end
    while #self.canvases > #frames do
        local canvas = table.remove(self.canvases)
        table.remove(self.backgroundElementTypes)
        canvas:delete()
    end
    for index, frame in ipairs(frames) do
        self:_fitCanvas(self.canvases[index], frame)
        self.backgroundElementTypes[index] = self.canvases[index][1].type
    end
end

function RedWarningOverlay:show(title, body, subtitle, footer)
    self:_fitToDesktopScreens()
    for _, canvas in ipairs(self.canvases) do
        canvas[2].text = tostring(title or "")
        canvas[3].text = tostring(body or "")
        canvas[4].text = tostring(subtitle or "")
        canvas[5].text = tostring(footer or "")
    end
    self:_startPulse()
    for _, canvas in ipairs(self.canvases) do
        canvas:show()
    end
end

function RedWarningOverlay:setFooter(text)
    for _, canvas in ipairs(self.canvases) do
        canvas[5].text = tostring(text or "")
    end
end

-- hide() stops the pulse animation and hides all canvases. The canvases are
-- NOT deleted because show() re-uses them on the next violation, avoiding
-- the overhead of recreating canvas windows each time.
function RedWarningOverlay:hide()
    if self.pulseTimer then
        self.pulseTimer:stop()
        self.pulseTimer = nil
    end
    for _, canvas in ipairs(self.canvases) do
        canvas:hide()
    end
end

-- isCreated returns true if any canvas has been allocated. Used by
-- Overlay:_refresh() to avoid updating an uninitialised instance.
function RedWarningOverlay:isCreated()
    return #self.canvases > 0
end

return RedWarningOverlay
