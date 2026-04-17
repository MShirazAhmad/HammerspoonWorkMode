-- Default configuration for the whole work-mode system.
-- The goal is to keep almost all day-to-day tuning here so behavior changes
-- rarely require editing the module code itself.
local home = os.getenv("HOME")

return {
    user = {
        -- JSONL-style activity snapshots for later review or analysis.
        activity_log_path = home .. "/web-activity.log",
        -- Human-readable marker log for violations, GPS transitions, and startup.
        marker_log_path = home .. "/.hammerspoon/hard-blocker.marker.log",
        -- A small state file that external tools can read to know the current
        -- GPS-derived mode without speaking directly to Hammerspoon.
        geofence_state_path = home .. "/.hammerspoon/manage-py-geofence.state",
    },
    timers = {
        -- How often to re-check the current screen context for enforcement.
        scan_seconds = 2,
        -- How often to write background activity snapshots.
        activity_log_seconds = 20,
        -- Default GPS refresh interval used by the location module.
        location_poll_seconds = 5,
        -- Baseline overlay duration for a normal violation.
        overlay_default_seconds = 180,
        -- Escalation base used for repeat violations in one session.
        lockout_base_seconds = 300,
    },
    thresholds = {
        -- After this many violations, overlays start growing longer.
        max_violations_before_long_lockout = 3,
        -- Confidence threshold before the classifier alone can trigger a lockout.
        off_task_lockout_confidence = 0.9,
    },
    schedule = {
        -- If false, scheduling is ignored and time never suppresses enforcement.
        enabled = true,
        timezone = "local",
        workdays = {
            -- Lua/strftime weekday numbering uses 1=Sunday, 2=Monday, etc.
            [2] = true,
            [3] = true,
            [4] = true,
            [5] = true,
            [6] = true,
        },
        start_hour = 9,
        end_hour = 17,
    },
    location = {
        -- If false, GPS never changes behavior and the script effectively
        -- relies only on schedule plus the current enforcement code.
        enabled = true,
        -- When true, being inside the geofence relaxes BLOCK enforcement.
        lab_relaxes_blocks = true,
        lab_geofence = {
            -- Replace these coordinates with your approved ALLOW-mode location.
            latitude = 33.49317303257537,
            longitude = -86.79794402590039,
            -- Radius is in meters.
            radius = 60.96,
        },
    },
    -- Apps listed here are treated as unsuitable during BLOCK mode.
    blocked_apps = {
        "Books",
        "Codex",
        "Terminal",
        "iTerm2",
        "TextEdit",
        "PyCharm",
        "PyCharm CE",
        "Activity Monitor",
    },
    browser = {
        -- Supported apps are the browsers for which AppleScript tab inspection
        -- is implemented in browser_filter.lua.
        supported_apps = {
            "Safari",
            "Google Chrome",
            "Brave Browser",
            "Arc",
            "Microsoft Edge",
            "Opera",
            "Vivaldi",
        },
        -- Hosts here are treated as explicitly research-safe browser contexts.
        allowed_domains = {
            "arxiv.org",
            "scholar.google.com",
            "semanticscholar.org",
            "pubmed.ncbi.nlm.nih.gov",
            "nature.com",
            "science.org",
            "ieeexplore.ieee.org",
            "acm.org",
            "openai.com",
            "overleaf.com",
            "zotero.org",
            "github.com",
            "docs.python.org",
            "pytorch.org",
            "numpy.org",
            "scipy.org",
            "stanford.edu",
            "mit.edu",
            "cmu.edu",
        },
        -- Hosts here count as directly distracting and can trigger enforcement.
        blocked_domains = {
            "youtube.com",
            "youtu.be",
            "reddit.com",
            "x.com",
            "twitter.com",
            "instagram.com",
            "facebook.com",
            "discord.com",
            "netflix.com",
            "primevideo.com",
            "amazon.com",
            "espn.com",
            "cnn.com",
            "foxnews.com",
            "buzzfeed.com",
            "tiktok.com",
            "twitch.tv",
        },
        -- Title matching is a backup when the host alone is not enough.
        blocked_title_terms = {
            "youtube",
            "reddit",
            "twitter",
            "instagram",
            "shopping",
            "sports",
            "entertainment",
            "news",
            "stream",
            "netflix",
            "prime video",
        },
    },
    categories = {
        -- These app names help the classifier recognize common research tools.
        research_apps = {
            "Safari",
            "Google Chrome",
            "Brave Browser",
            "Arc",
            "Preview",
            "Skim",
            "Zotero",
            "Overleaf",
            "Visual Studio Code",
            "Code",
            "Python",
            "RStudio",
        },
        -- Keywords that make a visible title look clearly distracting.
        distraction_keywords = {
            "youtube",
            "reddit",
            "shopping",
            "sports",
            "entertainment",
            "celebrity",
            "gaming",
            "twitch",
            "netflix",
            "prime video",
            "news",
        },
        -- Keywords that make a visible title look clearly research-related.
        research_keywords = {
            "paper",
            "study",
            "research",
            "experiment",
            "analysis",
            "dataset",
            "dissertation",
            "thesis",
            "arxiv",
            "pubmed",
            "overleaf",
            "zotero",
            "notebook",
            "manuscript",
        },
    },
    overlay = {
        -- Visual text used by the full-screen intervention canvas.
        title = "RESEARCH MODE",
        subtitle = "Return to writing, reading, coding, or analysis.",
        background_alpha = 0.96,
    },
}
