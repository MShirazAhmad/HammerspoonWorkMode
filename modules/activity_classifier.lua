-- activity_classifier.lua — Heuristic classifier for the current work context.
--
-- ROLE IN THE SYSTEM
-- ------------------
-- The classifier is the THIRD and weakest enforcement layer in enforce().
-- It only fires after BrowserFilter and AppBlocker both find nothing wrong.
-- Its job is to catch drift that neither of the simpler layers can see — e.g.
-- reading a distracting article in a mixed-use app like a notes app, or
-- having a vague window title without a clear browser URL.
--
-- INPUT: a snapshot table produced by currentSnapshot() in init.lua. The
-- relevant fields are:
--   snapshot.app          — frontmost application name
--   snapshot.window_title — frontmost window title (may be nil)
--   snapshot.browser      — { title, url, host } if a supported browser is
--                           frontmost, else nil
--
-- OUTPUT: { status, confidence, reason }
--   status     — "research" | "off_task" | "neutral"
--   confidence — float 0–1; used by enforce() to gate lockouts
--   reason     — human-readable explanation shown in the overlay and menu
--
-- RULE ORDER (first match wins):
--   1. Allowed domain   → research (0.95) — strongest positive signal
--   2. Research keyword → research (0.82) — softer positive signal
--   3. Distraction keyword → off_task (0.93) — strong negative signal
--   4. Blocked domain   → off_task (0.98) — strongest negative signal
--   5. Research app     → research (0.65) — weak positive; app alone not definitive
--   6. (none matched)   → neutral (0.40)
--
-- NOTE: enforce() only triggers a lockout from the classifier when
-- confidence >= config.thresholds.off_task_lockout_confidence (default 0.9),
-- so the "research app" rule (0.65) and "neutral" (0.40) never cause lockouts.
-- This prevents false positives from ambiguous context.
--
-- The rule order is intentionally conservative: an allowed domain beats any
-- keyword, so opening arxiv.org in a browser with "news" in the title still
-- counts as research.

local ActivityClassifier = {}
ActivityClassifier.__index = ActivityClassifier

-- lower normalises a value into a lowercase string. Returns "" for non-strings
-- so downstream checks never crash on nil app names or window titles.
local function lower(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:lower()
end

-- containsAny does a plain-text substring search of `text` against each entry
-- in `values`. Returns the FIRST matching needle (lowercase) so the caller
-- can include it in the reason string. Returns nil if nothing matches.
-- Plain search (no Lua patterns) avoids false matches from special characters
-- in domain names or titles.
local function containsAny(text, values)
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

function ActivityClassifier:title()
    return "Activity Classifier"
end

function ActivityClassifier:description()
    return "Scores the visible app, browser host, and titles as research, off-task, or neutral."
end

function ActivityClassifier:classify(snapshot)
    local app = snapshot.app or ""
    local windowTitle = snapshot.window_title or ""
    local browser = snapshot.browser or {}
    -- Use browser tab title over window title when available; it is more precise.
    local title = browser.title or windowTitle
    local host = browser.host or ""

    -- Rule 1: allowed domains are the strongest research signal.
    -- Checked before keywords so arxiv.org with a "news" headline is not blocked.
    local allowedDomain = containsAny(host, self.config.browser.allowed_domains)
    if allowedDomain then
        return { status = "research", confidence = 0.95, reason = "Allowed research domain: " .. allowedDomain }
    end

    -- Rule 2: research keywords in the title (softer; title can be unreliable).
    local researchKeyword = containsAny(title, self.config.categories.research_keywords)
    if researchKeyword then
        return { status = "research", confidence = 0.82, reason = "Research keyword detected: " .. researchKeyword }
    end

    -- Rule 3: distraction keywords in the title.
    -- High confidence because an explicit distraction keyword is a strong signal.
    local distractionKeyword = containsAny(title, self.config.categories.distraction_keywords)
    if distractionKeyword then
        return { status = "off_task", confidence = 0.93, reason = "Distracting keyword detected: " .. distractionKeyword }
    end

    -- Rule 4: blocked domains — highest negative confidence because the URL
    -- is an authoritative signal (unlike a window title which can be set freely).
    local blockedDomain = containsAny(host, self.config.browser.blocked_domains)
    if blockedDomain then
        return { status = "off_task", confidence = 0.98, reason = "Blocked distracting domain: " .. blockedDomain }
    end

    -- Rule 5: research-capable app in focus, but no title/URL evidence either way.
    -- Confidence 0.65 is deliberately below off_task_lockout_confidence (0.9)
    -- so using VSCode or a browser without a telling title never triggers a lockout.
    for _, researchApp in ipairs(self.config.categories.research_apps or {}) do
        if app == researchApp then
            return { status = "research", confidence = 0.65, reason = "Research-capable app in focus: " .. app }
        end
    end

    -- Rule 6: not enough evidence to classify. Confidence 0.4 is well below the
    -- lockout threshold so neutral never triggers enforcement.
    return { status = "neutral", confidence = 0.4, reason = "Activity is ambiguous from visible app and title context." }
end

-- statusSummary is called by the menu builder in init.lua. It re-runs classify()
-- on the supplied snapshot so the menu always shows a fresh classification,
-- not a cached one.
function ActivityClassifier:statusSummary(snapshot)
    if not snapshot then
        return "No current snapshot"
    end
    local result = self:classify(snapshot)
    return string.format("%s (%.0f%%): %s", tostring(result.status), (result.confidence or 0) * 100, tostring(result.reason or ""))
end

return ActivityClassifier
