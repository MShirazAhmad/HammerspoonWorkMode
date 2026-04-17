-- The classifier turns the current visible context into a simple judgment:
-- research, off_task, or neutral. It is intentionally heuristic and uses
-- config-driven keywords instead of heavy modeling so it stays explainable.
local ActivityClassifier = {}
ActivityClassifier.__index = ActivityClassifier

local function lower(value)
    -- Normalize unknown values into a lowercase string so later checks do not
    -- need to repeat type guards.
    if type(value) ~= "string" then
        return ""
    end
    return value:lower()
end

local function containsAny(text, values)
    -- Return the first matching keyword to make later explanations more useful.
    local haystack = lower(text)
    for _, value in ipairs(values or {}) do
        local needle = lower(value)
        if haystack:find(needle, 1, true) then
            return needle
        end
    end
    return nil
end

function ActivityClassifier.new(config)
    local self = setmetatable({}, ActivityClassifier)
    self.config = config
    return self
end

function ActivityClassifier:classify(snapshot)
    -- Pull the most useful fields out of the snapshot so classification logic
    -- reads as a sequence of rules instead of deeply nested table access.
    local app = snapshot.app or ""
    local windowTitle = snapshot.window_title or ""
    local browser = snapshot.browser or {}
    local title = browser.title or windowTitle
    local host = browser.host or ""

    -- Research-safe domains are the strongest positive signal.
    local allowedDomain = containsAny(host, self.config.browser.allowed_domains)
    if allowedDomain then
        return {
            status = "research",
            confidence = 0.95,
            reason = "Allowed research domain: " .. allowedDomain,
        }
    end

    -- Research keywords in titles are a softer but still useful positive signal.
    local researchKeyword = containsAny(title, self.config.categories.research_keywords)
    if researchKeyword then
        return {
            status = "research",
            confidence = 0.82,
            reason = "Research keyword detected: " .. researchKeyword,
        }
    end

    -- Distraction keywords in a title indicate visible drift even if the host
    -- alone is ambiguous.
    local distractionKeyword = containsAny(title, self.config.categories.distraction_keywords)
    if distractionKeyword then
        return {
            status = "off_task",
            confidence = 0.93,
            reason = "Distracting keyword detected: " .. distractionKeyword,
        }
    end

    -- Explicitly blocked domains are the strongest negative signal.
    local blockedDomain = containsAny(host, self.config.browser.blocked_domains)
    if blockedDomain then
        return {
            status = "off_task",
            confidence = 0.98,
            reason = "Blocked distracting domain: " .. blockedDomain,
        }
    end

    -- If no title or host rule matched, still give research-capable apps some
    -- credit because they are often used for legitimate work.
    for _, researchApp in ipairs(self.config.categories.research_apps or {}) do
        if app == researchApp then
            return {
                status = "research",
                confidence = 0.65,
                reason = "Research-capable app in focus: " .. app,
            }
        end
    end

    -- Neutral means "not enough visible evidence either way."
    return {
        status = "neutral",
        confidence = 0.4,
        reason = "Activity is ambiguous from visible app and title context.",
    }
end

return ActivityClassifier
