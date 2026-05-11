-- config/default.lua — Single source of truth for all runtime configuration.
--
-- DESIGN INTENT
-- -------------
-- Almost all day-to-day tuning should happen here, not in module code. The
-- modules read from this table but do not write to it, so changing a value
-- here takes effect after the next hs.reload() without editing any module.
--
-- HOW IT IS LOADED
-- ----------------
-- init.lua does: local config = require("config.default")
-- The returned table is passed to every module constructor. Modules store only
-- the sub-table they need (e.g. BrowserFilter stores config.browser) so they
-- cannot accidentally read unrelated sections.
--
-- KEY SECTIONS
-- ------------
--   user       — file paths for logs, state files, and messages
--   timers     — poll intervals, overlay durations, decision windows
--   thresholds — classifier confidence gates and violation escalation limits
--   schedule   — work-hours window (weekdays × hour range)
--   location   — GPS geofence coordinates, mode (block inside vs outside)
--   blocked_apps      — apps killed immediately when frontmost in BLOCK mode
--   terminal_guard    — apps routed to the Y/N prompt instead of being killed
--   browser           — allowed/blocked domains and blocked title keywords
--   categories        — research and distraction keywords for the classifier
--   red_warning_overlay   — visual settings for the awareness overlay
--   block_screen_overlay  — visual settings for the terminal guard prompt

local home = os.getenv("HOME")

local config = {
    user = {
        -- JSONL-style activity snapshots (one JSON object per line).
        -- Read by analysis scripts; never read by the enforcement system itself.
        activity_log_path = home .. "/web-activity.log",
        -- Human-readable marker log. One line per event (violation, GPS, startup).
        -- This is the log to look at when debugging "why did it fire?"
        marker_log_path = home .. "/.hammerspoon/hard-blocker.marker.log",
        -- GPS decision state file. Written by location_mode.lua after every poll.
        -- Read by terminal-command-guard.zsh via _research_geofence_is_relaxed().
        -- Format: key=value, one pair per line.
        geofence_state_path = home .. "/.hammerspoon/manage-py-geofence.state",
        -- Terminal guard decision state file. Written by init.lua after Y/N.
        -- Read by terminal-command-guard.zsh to allow or block the pending command.
        -- Format: mode=allow|block, until_epoch=<unix>, reason=<text>
        terminal_guard_state_path = home .. "/.hammerspoon/terminal-command-guard.state",
        -- YAML file loaded by messages.lua at startup. Values here override the
        -- hardcoded defaults in messages.lua. Missing keys fall back to defaults.
        messages_path = home .. "/.hammerspoon/config/messages.yaml",
        -- Allowed folders state file. Written by init.lua when user approves a folder.
        -- Read by terminal-command-guard.zsh to gate cd commands.
        -- Format: one folder path per line (absolute paths).
        allowed_folders_state_path = home .. "/.hammerspoon/allowed-folders.state",
        -- Exact-only allowed paths. These are useful for container/navigation
        -- folders such as $HOME or a projects root: the folder itself is allowed,
        -- but children are not automatically allowed.
        exact_allowed_paths_state_path = home .. "/.hammerspoon/exact-allowed-paths.state",
        -- Paths denied from the folder path prompt. Recursive and exact variants
        -- mirror the allowed path state files.
        blocked_paths_state_path = home .. "/.hammerspoon/blocked-paths.state",
        exact_blocked_paths_state_path = home .. "/.hammerspoon/exact-blocked-paths.state",
    },

    timers = {
        -- How often enforce() is called from the background scan timer.
        -- The appWatcher also calls enforce() on every app activation so this
        -- scan_seconds only catches state changes that happen without an app switch.
        scan_seconds = 2,
        -- How often activity snapshots are written to the JSONL log.
        -- Duplicate records are suppressed anyway, so this mostly matters for idle periods.
        activity_log_seconds = 20,
        -- How often LocationMode polls hs.location.get() for a new GPS fix.
        location_poll_seconds = 5,
        -- Overlay duration for a normal (first or second) violation.
        overlay_default_seconds = 180,
        -- Duration multiplier base for escalated violations. After
        -- max_violations_before_long_lockout, duration = lockout_base_seconds × count.
        lockout_base_seconds = 300,
        -- How long a Y ("allow") or N ("block") terminal decision stays valid.
        -- 1800 = 30 minutes. After expiry the shell guard requires a new Y/N answer.
        terminal_guard_decision_seconds = 1800,
    },

    thresholds = {
        -- Number of violations in one BLOCK session before overlay durations start
        -- escalating. Default 3: violations 1–2 use overlay_default_seconds,
        -- violation 3+ uses lockout_base_seconds × violationCount.
        max_violations_before_long_lockout = 3,
        -- Minimum classifier confidence required to trigger a lockout from
        -- ActivityClassifier alone. Must be high to avoid false positives.
        -- Browser and app enforcement ignore this threshold.
        off_task_lockout_confidence = 0.9,
    },

    schedule = {
        -- When false, schedule is treated as always active (no time gating).
        enabled = true,
        timezone = "local",
        workdays = {
            -- Lua os.date() wday: 1=Sunday, 2=Monday, …, 7=Saturday
            [2] = true,  -- Monday
            [3] = true,  -- Tuesday
            [4] = true,  -- Wednesday
            [5] = true,  -- Thursday
            [6] = true,  -- Friday
        },
        start_hour = 9,   -- enforcement begins at 09:00 local time
        end_hour = 17,    -- enforcement ends at 17:00 local time (not 17:59)
    },

    location = {
        -- When false, GPS is ignored and the system behaves as if always outside
        -- the geofence (i.e. always relaxed = the schedule gate is the only gate).
        enabled = true,
        -- block_inside_geofence = true  → inside geofence means BLOCK active.
        -- block_inside_geofence = false → inside geofence means ALLOW (lab mode).
        block_inside_geofence = true,
        -- Only used when block_inside_geofence = false. True means being inside
        -- the geofence (lab) relaxes BLOCK enforcement.
        lab_relaxes_blocks = true,
        lab_geofence = {
            -- GPS coordinates of the enforced work location.
            -- Replace with your actual lab/office coordinates in your local copy.
            latitude = 0,
            longitude = 0,
            -- Geofence radius in meters.
            radius = 100,
        },
    },

    -- Apps in this list are kill9'd immediately when they become frontmost
    -- during BLOCK mode, UNLESS they are also in terminal_guard.apps (which
    -- routes them to the Y/N prompt instead of killing them outright).
    blocked_apps = {
        "Books",
        "Terminal",
        "iTerm2",
        "TextEdit",
        "PyCharm",
        "PyCharm CE",
        "Activity Monitor",
    },

    -- Apps listed here are exempt from the kill9 path and instead trigger the
    -- full-screen Y/N terminal prompt. They should also appear in blocked_apps
    -- so AppBlocker knows to defer them rather than kill them.
    terminal_guard = {
        apps = {
            "Terminal",
            "iTerm2",
        },
    },

    -- Folder path blocker scans Accessibility AXDocument/AXFilename/AXURL values
    -- and reduces files to their containing folder. During BLOCK mode, a known
    -- blocked folder kills the owning app; unknown folders prompt for a decision.
    file_path_blocker = {
        enabled = true,
        violation_overlay_seconds = 5,
        -- Paths here are roots: any file under one of these paths is allowed.
        -- The existing allowed_folders.state file is also included by default.
        allowed_paths = {
            home .. "/.hammerspoon",
            home .. "/Documents/GitHub/research-project",
            home .. "/Documents/GitHub/writing-project",
        },
        exact_allowed_paths = {
            home,
            home .. "/Documents/GitHub",
        },
        blocked_paths = {},
        exact_blocked_paths = {},
        include_allowed_folders_state = true,
        include_exact_allowed_paths_state = true,
        include_blocked_paths_state = true,
        include_exact_blocked_paths_state = true,
        -- Empty monitored lists mean "all apps except ignored apps", but an
        -- explicit list keeps the 2-second enforcement scan responsive.
        monitored_apps = {
            "Finder",
            "Terminal",
            "iTerm2",
            "Code",
            "Visual Studio Code",
            "Visual Studio Code - Insiders",
            "PyCharm",
            "PyCharm CE",
            "IntelliJ IDEA",
            "BBEdit",
            "Preview",
            "Microsoft Word",
            "Microsoft PowerPoint",
            "Microsoft Excel",
            "Obsidian",
            "Zotero",
            "GIMP",
        },
        monitored_bundle_ids = {},
        -- Headless helpers do not have windows, so match their command line and
        -- inspect open files/cwd with lsof. Keep this targeted to avoid killing
        -- ordinary language servers or build tools.
        monitored_process_patterns = {
            "mcp",
            "model-context-protocol",
        },
        process_path_prefixes = {
            home,
        },
        ignored_apps = {
            "Hammerspoon",
            "System Settings",
            "Notification Center",
        },
        ignored_bundle_ids = {
            "org.hammerspoon.Hammerspoon",
            "com.apple.systempreferences",
            "com.apple.notificationcenterui",
        },
    },

    -- Folder blocker monitors app window titles for folder paths and requires
    -- approval before allowing access. Approved folders are persisted in the
    -- allowed_folders_state_path file. Terminal cd commands are gated by reading
    -- this file (see terminal-command-guard.zsh).
    folder_blocker = {
        -- Apps monitored for folder path detection via window title parsing.
        -- When a new folder is detected in the title, a Y/N prompt appears.
        monitored_apps = {
            "Visual Studio Code",
            "Code",
            "Xcode",
            "PyCharm",
            "PyCharm CE",
            "IntelliJ IDEA",
            "Sublime Text",
            "Atom",
        },
    },

    browser = {
        -- Browsers for which BrowserFilter has an AppleScript implementation.
        -- Adding a new browser here without adding an APPLESCRIPTS entry in
        -- browser_filter.lua will have no effect.
        supported_apps = {
            "Safari", "Google Chrome", "Brave Browser", "Arc",
            "Microsoft Edge", "Opera", "Vivaldi",
        },
        -- Hosts that are explicitly research-safe. Matched as substring of the
        -- URL host (e.g. "stanford.edu" matches "cs.stanford.edu").
        -- Allowed domains WIN against all other rules in both BrowserFilter
        -- and ActivityClassifier, so a research site with a distracting title
        -- is still treated as research.
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
        -- Hosts that trigger an immediate browser violation when the frontmost
        -- tab lands on them. The tab is NOT closed; the red warning overlay
        -- shows instead and persists until the user navigates away.
        blocked_domains = {
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
        -- Title keywords catch distracting content on mixed-use domains (e.g. a
        -- news article on a domain not in blocked_domains). Matched against the
        -- full tab title as a case-insensitive substring.
        blocked_title_terms = {
            "reddit", "twitter", "instagram", "shopping", "sports",
            "entertainment", "news", "stream", "netflix", "prime video",
        },
    },

    categories = {
        -- App names recognised by ActivityClassifier as research-capable.
        -- A match here gives confidence 0.65 (below the 0.9 lockout threshold)
        -- so a research app alone cannot trigger enforcement.
        research_apps = {
            "Safari", "Google Chrome", "Brave Browser", "Arc",
            "Preview", "Skim", "Zotero", "Overleaf",
            "Visual Studio Code", "Code", "Python", "RStudio",
        },
        -- Keywords whose presence in a window/tab title signals distraction.
        -- Matched case-insensitively as a substring of the combined title.
        distraction_keywords = {
            "reddit", "shopping", "sports", "entertainment",
            "celebrity", "gaming", "twitch", "netflix", "prime video", "news",
        },
        -- Keywords whose presence in a window/tab title signals research work.
        -- Matched case-insensitively as a substring of the combined title.
        research_keywords = {
            "paper", "study", "research", "experiment", "analysis",
            "dataset", "dissertation", "thesis", "arxiv", "pubmed",
            "overleaf", "zotero", "notebook", "manuscript",
        },
    },

    red_warning_overlay = {
        -- Pulsing red awareness overlay for browser/app/classifier violations.
        -- background_image_path: path to an SVG or PNG used instead of the plain
        -- red rectangle. Set to "" or remove the key to use the solid red fallback.
        background_alpha = 0.96,
        background_image_path = home .. "/.hammerspoon/assets/screens/soft-red-vignette-overlay.svg",
        background_pulse = {
            enabled = true,
            min_alpha = 0.45,
            max_alpha = 1.0,
            cycle_seconds = 2.8,   -- time for one full pulse cycle
            tick_seconds = 0.03,   -- animation frame rate (≈33 fps)
        },
    },

    block_screen_overlay = {
        -- Near-opaque black hard-block/prompt screen for the terminal guard Y/N.
        -- Kept visually distinct from the red warning overlay so users can
        -- immediately distinguish "awareness hint" from "action required."
        background_color = { red = 0, green = 0, blue = 0, alpha = 0.96 },
    },
}

local function mergeTable(base, override)
    for key, value in pairs(override or {}) do
        if type(value) == "table" and type(base[key]) == "table" then
            mergeTable(base[key], value)
        else
            base[key] = value
        end
    end
    return base
end

local localPath = (hs and hs.configdir or (home .. "/.hammerspoon")) .. "/config/local.lua"
local localChunk = loadfile(localPath)
if localChunk then
    local ok, localConfig = pcall(localChunk)
    if ok and type(localConfig) == "table" then
        mergeTable(config, localConfig)
    end
end

return config
