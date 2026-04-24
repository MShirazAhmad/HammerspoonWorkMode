-- BlockScreenOverlay is reserved for hard blocking and confirmation prompts.
-- It is intentionally separate from RedWarningOverlay, whose only job is to
-- make the user aware they are going out of track.
local BlockScreenOverlay = {}
BlockScreenOverlay.__index = BlockScreenOverlay

function BlockScreenOverlay.new(config, messages)
    local self = setmetatable({}, BlockScreenOverlay)
    self.config = config
    self.messages = messages
    self.canvas = nil
    return self
end

function BlockScreenOverlay:_settings()
    return self.config.block_screen_overlay or {}
end

local function fullFrame()
    return hs.screen.mainScreen():fullFrame()
end

function BlockScreenOverlay:ensureCanvas()
    if self.canvas then
        return
    end

    local settings = self:_settings()
    self.canvas = hs.canvas.new(fullFrame())
    self.canvas:level("screenSaver")
    self.canvas:behavior({ "canJoinAllSpaces", "stationary", "fullScreenAuxiliary" })

    self.canvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = settings.background_color or { red = 0, green = 0, blue = 0, alpha = 0.96 },
        frame = { x = 0, y = 0, w = "100%", h = "100%" },
    }
    self.canvas[2] = {
        type = "text",
        text = "",
        textSize = 64,
        textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "10%", y = "18%", w = "80%", h = "12%" },
    }
    self.canvas[3] = {
        type = "text",
        text = "",
        textSize = 34,
        textColor = { white = 1, alpha = 0.96 },
        textAlignment = "center",
        frame = { x = "12%", y = "38%", w = "76%", h = "22%" },
    }
    self.canvas[4] = {
        type = "text",
        text = "",
        textSize = 26,
        textColor = { white = 1, alpha = 0.86 },
        textAlignment = "center",
        frame = { x = "16%", y = "60%", w = "68%", h = "12%" },
    }
    self.canvas[5] = {
        type = "text",
        text = "",
        textSize = 44,
        textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "30%", y = "78%", w = "40%", h = "10%" },
    }
end

function BlockScreenOverlay:show(title, body, subtitle, footer)
    self:ensureCanvas()
    self.canvas[2].text = tostring(title or "")
    self.canvas[3].text = tostring(body or "")
    self.canvas[4].text = tostring(subtitle or "")
    self.canvas[5].text = tostring(footer or "")
    self.canvas:show()
end

function BlockScreenOverlay:setFooter(text)
    if self.canvas then
        self.canvas[5].text = tostring(text or "")
    end
end

function BlockScreenOverlay:hide()
    if self.canvas then
        self.canvas:hide()
    end
end

function BlockScreenOverlay:isCreated()
    return self.canvas ~= nil
end

return BlockScreenOverlay
