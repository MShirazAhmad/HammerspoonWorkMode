# Configuration Reference

All runtime behavior is configured in `~/.hammerspoon/config/default.lua`.

The table below lists every setting grouped by area. Settings marked **Beginner** are the ones you are most likely to need on a first setup. Settings marked **Advanced** are for tuning or extension.

---

## Location

Controls the GPS geofence that determines `ALLOW` vs `BLOCK`.

| Key | Type | Default | Level | Description |
|---|---|---|---|---|
| `location.enabled` | boolean | `true` | Beginner | When `false`, GPS is ignored and the system behaves as always relaxed. |
| `location.block_inside_geofence` | boolean | `true` | Beginner | When `true`, being inside the geofence activates `BLOCK`. When `false`, the geofence is the relaxed area instead. |
| `location.lab_relaxes_blocks` | boolean | `true` | Advanced | Only used when `block_inside_geofence = false`. Makes the geofence the relaxed (ALLOW) area. |
| `location.lab_geofence.latitude` | number | `0` | Beginner | Latitude of the enforced work location. |
| `location.lab_geofence.longitude` | number | `0` | Beginner | Longitude of the enforced work location. |
| `location.lab_geofence.radius` | number | `100` | Beginner | Geofence radius in meters. Start around 75–100 and adjust after testing. |

---

## Schedule

Controls which hours enforcement applies. Outside the schedule, the system stays relaxed even inside the geofence.

| Key | Type | Default | Level | Description |
|---|---|---|---|---|
| `schedule.enabled` | boolean | `true` | Beginner | When `false`, time gating is disabled and enforcement is always active when GPS puts you in `BLOCK`. |
| `schedule.workdays` | table | Mon–Fri | Beginner | Lua `os.date()` wday keys set to `true`. 1=Sun, 2=Mon, …, 7=Sat. |
| `schedule.start_hour` | number | `9` | Beginner | Enforcement begins at this hour (24-hour local time). |
| `schedule.end_hour` | number | `17` | Beginner | Enforcement ends at this hour (exclusive). |
| `schedule.timezone` | string | `"local"` | Advanced | Reserved for future timezone override support. |

---

## Blocked Apps

Apps that are force-closed when they become frontmost during `BLOCK` mode.

| Key | Type | Default | Level | Description |
|---|---|---|---|---|
| `blocked_apps` | list of strings | see `default.lua` | Beginner | App names as macOS shows them. Apps in this list are killed immediately unless they also appear in `terminal_guard.apps`. |
| `terminal_guard.apps` | list of strings | `["Terminal", "iTerm2"]` | Beginner | Apps routed to the Y/N research-check prompt instead of being killed outright. Must also appear in `blocked_apps`. |

---

## Browser Rules

Controls which websites trigger enforcement and which are treated as research-safe.

| Key | Type | Default | Level | Description |
|---|---|---|---|---|
| `browser.supported_apps` | list of strings | Safari, Chrome, Brave, Arc, Edge, Opera, Vivaldi | Beginner | Browsers for which URL/title inspection is enabled via AppleScript. |
| `browser.allowed_domains` | list of strings | arxiv.org, scholar.google.com, … | Beginner | Domains treated as research-safe. Matched as a substring of the URL host. Allowed domains win against all other rules. |
| `browser.blocked_domains` | list of strings | youtube.com, reddit.com, … | Beginner | Domains that trigger the red warning overlay. The tab is not closed; the overlay persists until you navigate away. |
| `browser.blocked_title_terms` | list of strings | shopping, sports, entertainment, … | Moderate | Tab title substrings (case-insensitive) that trigger the red warning on mixed-use domains not in `blocked_domains`. |

---

## Activity Classification

Controls the keyword-based classifier that labels visible activity as `research`, `neutral`, or `off_task`.

| Key | Type | Default | Level | Description |
|---|---|---|---|---|
| `categories.research_apps` | list of strings | Safari, Preview, Zotero, VS Code, … | Moderate | App names the classifier treats as research-capable. A match gives confidence 0.65, below the lockout threshold. |
| `categories.research_keywords` | list of strings | paper, analysis, experiment, … | Moderate | Title substrings (case-insensitive) that signal research activity. |
| `categories.distraction_keywords` | list of strings | reddit, shopping, gaming, … | Moderate | Title substrings (case-insensitive) that signal off-task activity. |
| `thresholds.off_task_lockout_confidence` | number | `0.9` | Advanced | Minimum classifier confidence required to trigger a lockout from the classifier alone. Browser and app enforcement ignore this. |

---

## Path Blocking

Controls which file system paths apps are allowed to access during `BLOCK` mode.

| Key | Type | Default | Level | Description |
|---|---|---|---|---|
| `file_path_blocker.enabled` | boolean | `true` | Advanced | When `false`, path blocking is disabled entirely. |
| `file_path_blocker.violation_overlay_seconds` | number | `5` | Advanced | How long the fixed-duration warning overlay shows on a path violation. |
| `file_path_blocker.allowed_paths` | list of strings | `~/.hammerspoon`, research project paths | Advanced | Recursive roots. Any file at or below a path here is allowed. |
| `file_path_blocker.exact_allowed_paths` | list of strings | `~`, `~/Documents/GitHub` | Advanced | Exact container paths only. The folder itself is allowed but children are not automatically allowed. |
| `file_path_blocker.blocked_paths` | list of strings | `[]` | Advanced | Recursive blocked roots. |
| `file_path_blocker.exact_blocked_paths` | list of strings | `[]` | Advanced | Exact-only blocked paths. |
| `file_path_blocker.monitored_apps` | list of strings | Finder, Terminal, VS Code, … | Advanced | Apps whose Accessibility document attributes are scanned. |
| `file_path_blocker.monitored_process_patterns` | list of strings | `mcp`, `model-context-protocol` | Advanced | Headless process command-line patterns inspected via lsof. |
| `file_path_blocker.ignored_apps` | list of strings | Hammerspoon, System Settings, … | Advanced | Apps excluded from scanning. |
| `folder_blocker.monitored_apps` | list of strings | VS Code, Xcode, PyCharm, … | Advanced | Apps monitored for folder paths in window titles. New unknown folders trigger a Y/N approval prompt. |

State files that supplement the config:

- `~/.hammerspoon/allowed-folders.state` — recursive allowed roots (one path per line)
- `~/.hammerspoon/exact-allowed-paths.state` — exact-only allowed paths
- `~/.hammerspoon/blocked-paths.state` — recursive blocked roots
- `~/.hammerspoon/exact-blocked-paths.state` — exact-only blocked paths

---

## Overlay Appearance

Controls the visual style and timing of the warning screens.

| Key | Type | Default | Level | Description |
|---|---|---|---|---|
| `timers.overlay_default_seconds` | number | `180` | Moderate | Duration of the red warning overlay for the first violations. |
| `timers.lockout_base_seconds` | number | `300` | Moderate | Base duration for escalated violations. After `max_violations_before_long_lockout`, duration = base × count. |
| `thresholds.max_violations_before_long_lockout` | number | `3` | Moderate | Number of violations before overlay durations start escalating. |
| `red_warning_overlay.background_alpha` | number | `0.96` | Advanced | Opacity of the red warning overlay. |
| `red_warning_overlay.background_image_path` | string | SVG path | Advanced | Path to an SVG or PNG background. Set to `""` for a plain solid red fallback. |
| `red_warning_overlay.background_pulse.enabled` | boolean | `true` | Advanced | When `true`, the overlay pulses between min and max alpha. |
| `red_warning_overlay.background_pulse.min_alpha` | number | `0.45` | Advanced | Minimum alpha during the pulse cycle. |
| `red_warning_overlay.background_pulse.max_alpha` | number | `1.0` | Advanced | Maximum alpha during the pulse cycle. |
| `red_warning_overlay.background_pulse.cycle_seconds` | number | `2.8` | Advanced | Duration of one full pulse cycle. |
| `block_screen_overlay.background_color` | table | black 0.96 alpha | Advanced | Background color for the hard-block terminal prompt screen. |

---

## Timers

Controls polling intervals and decision windows.

| Key | Type | Default | Level | Description |
|---|---|---|---|---|
| `timers.scan_seconds` | number | `2` | Advanced | How often `enforce()` is called from the background timer. |
| `timers.activity_log_seconds` | number | `20` | Advanced | How often activity snapshots are written to the JSONL log. |
| `timers.location_poll_seconds` | number | `5` | Advanced | How often GPS is polled for a new fix. |
| `timers.terminal_guard_decision_seconds` | number | `1800` | Moderate | How long a Y or N terminal guard decision stays valid (default 30 minutes). |

---

## Logging and State Files

Controls where logs and runtime state are written.

| Key | Type | Default | Level | Description |
|---|---|---|---|---|
| `user.activity_log_path` | string | `~/web-activity.log` | Optional | Path for JSONL activity snapshots. |
| `user.marker_log_path` | string | `~/.hammerspoon/hard-blocker.marker.log` | Optional | Path for human-readable marker log. One line per event. |
| `user.geofence_state_path` | string | `~/.hammerspoon/manage-py-geofence.state` | Optional | Written by `location_mode.lua` after every GPS poll. Read by the shell guard. |
| `user.terminal_guard_state_path` | string | `~/.hammerspoon/terminal-command-guard.state` | Optional | Written by `init.lua` after Y/N. Read by `terminal-command-guard.zsh`. |
| `user.messages_path` | string | `~/.hammerspoon/config/messages.yaml` | Optional | YAML file with user-facing text overrides. See [Messages](modules/messages.md). |
| `user.allowed_folders_state_path` | string | `~/.hammerspoon/allowed-folders.state` | Optional | Approved folder roots for terminal cd and path blocking. |
| `user.exact_allowed_paths_state_path` | string | `~/.hammerspoon/exact-allowed-paths.state` | Optional | Exact-only approved paths. |
| `user.blocked_paths_state_path` | string | `~/.hammerspoon/blocked-paths.state` | Optional | Blocked recursive roots. |
| `user.exact_blocked_paths_state_path` | string | `~/.hammerspoon/exact-blocked-paths.state` | Optional | Blocked exact-only paths. |

---

## Local Overrides

You can create `~/.hammerspoon/config/local.lua` to override specific keys without editing `default.lua`. The file is loaded last and deep-merged, so only the keys you list are changed.

Example `local.lua`:

```lua
return {
    location = {
        lab_geofence = {
            latitude = 37.7749,
            longitude = -122.4194,
            radius = 80,
        },
    },
    blocked_apps = { "Books", "Claude" },
}
```

This is the recommended approach for keeping personal GPS coordinates and app lists out of the shared repo.
