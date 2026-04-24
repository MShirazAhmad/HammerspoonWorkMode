-- RedWarningOverlay is the awareness overlay: a red full-screen warning that
-- tells the user they are drifting out of track. It is not the block screen.
local RedWarningOverlay = {}
RedWarningOverlay.__index = RedWarningOverlay

function RedWarningOverlay.new(config, messages)
    local self = setmetatable({}, RedWarningOverlay)
    self.config = config
    self.messages = messages
    self.canvases = {}
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
    return self.config.red_warning_overlay or self.config.overlay or {}
end

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

local function expandedFrame(frame)
    -- macOS keeps the notch/menu bar and Dock in special regions. Overdraw the
    -- canvas beyond the normal screen bounds so the warning glow reaches those
    -- edges instead of stopping at the desktop-safe area.
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
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

function RedWarningOverlay:_setBackgroundAlpha(alpha)
    for index, canvas in ipairs(self.canvases) do
        if self.backgroundElementTypes[index] == "image" then
            canvas[1].imageAlpha = alpha
        elseif canvas[1].fillColor then
            canvas[1].fillColor.alpha = alpha
        end
    end
end

function RedWarningOverlay:_refreshPulse()
    if #self.canvases == 0 then
        return
    end

    local pulse = self:_settings().background_pulse or {}
    local minimum = clamp(pulse.min_alpha or 0.45, 0, 1)
    local maximum = clamp(pulse.max_alpha or 1.0, minimum, 1)
    local cycle = math.max(0.1, tonumber(pulse.cycle_seconds) or 2.8)
    local elapsed = (hs.timer.secondsSinceEpoch() - self.pulseStartedAt) % cycle
    local phase = elapsed / cycle
    local amount = phase < 0.5 and (phase * 2) or ((1 - phase) * 2)

    self:_setBackgroundAlpha(minimum + ((maximum - minimum) * amount))
end

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

function RedWarningOverlay:_newCanvas(frame)
    local settings = self:_settings()
    local canvas = hs.canvas.new(expandedFrame(frame))
    -- assistiveTechHigh sits above Dock/menu/status window levels, which is
    -- necessary for this overlay to read as a whole-desktop warning.
    canvas:level("assistiveTechHigh")
    canvas:behavior({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary", "ignoresCycle", "transient" })

    canvas[1] = imageElement(settings.background_image_path) or {
        type = "rectangle",
        action = "fill",
        fillColor = { red = 0.45, green = 0, blue = 0, alpha = settings.background_alpha or 0.96 },
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
    }
    canvas[2] = {
        type = "text",
        text = self:message("overlay.title"),
        textSize = 68,
        textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "10%", y = "18%", w = "80%", h = "12%" },
    }
    canvas[3] = {
        type = "text",
        text = "",
        textSize = 34,
        textColor = { red = 1, green = 0.35, blue = 0.35, alpha = 1 },
        textAlignment = "center",
        frame = { x = "12%", y = "38%", w = "76%", h = "22%" },
    }
    canvas[4] = {
        type = "text",
        text = "",
        textSize = 26,
        textColor = { white = 1, alpha = 0.92 },
        textAlignment = "center",
        frame = { x = "16%", y = "60%", w = "68%", h = "12%" },
    }
    canvas[5] = {
        type = "text",
        text = "",
        textSize = 44,
        textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "30%", y = "78%", w = "40%", h = "10%" },
    }
    return canvas
end

function RedWarningOverlay:_fitCanvas(canvas, frame)
    local canvasFrame = expandedFrame(frame)
    canvas:frame(canvasFrame)
    local width = frame.w
    local height = frame.h
    local offsetX = frame.x - canvasFrame.x
    local offsetY = frame.y - canvasFrame.y
    -- The background uses the expanded canvas, while text remains aligned to
    -- the real display frame so copy does not drift into the overdraw gutter.
    canvas[1].frame = { x = 0, y = 0, w = canvasFrame.w, h = canvasFrame.h }
    canvas[2].frame = { x = offsetX + (width * 0.10), y = offsetY + (height * 0.18), w = width * 0.80, h = height * 0.12 }
    canvas[3].frame = { x = offsetX + (width * 0.12), y = offsetY + (height * 0.38), w = width * 0.76, h = height * 0.22 }
    canvas[4].frame = { x = offsetX + (width * 0.16), y = offsetY + (height * 0.60), w = width * 0.68, h = height * 0.12 }
    canvas[5].frame = { x = offsetX + (width * 0.30), y = offsetY + (height * 0.78), w = width * 0.40, h = height * 0.10 }
end

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

function RedWarningOverlay:hide()
    if self.pulseTimer then
        self.pulseTimer:stop()
        self.pulseTimer = nil
    end
    for _, canvas in ipairs(self.canvases) do
        canvas:hide()
    end
end

function RedWarningOverlay:isCreated()
    return #self.canvases > 0
end

return RedWarningOverlay
