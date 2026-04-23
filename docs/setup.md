# Setup

This guide walks through the whole project setup so the repo becomes your real Hammerspoon configuration.

## Goal

The goal is to run this project from `~/.hammerspoon` while keeping the source code versioned in git.

The project has one primary operating rule:

- inside your approved GPS radius: `BLOCK`
- outside your approved GPS radius: `ALLOW`

## Prerequisites

Before wiring the repo in, make sure you have:

- macOS
- Hammerspoon installed
- access to your current `~/.hammerspoon` folder
- the repo checked out locally

## Recommended Layout

Recommended live layout:

- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/modules/`
- `~/.hammerspoon/config/`

Recommended source-of-truth layout:

- your git repo contains `init.lua`
- your git repo contains `modules/`
- your git repo contains `config/`

## Back Up Existing Config

Before switching over, keep a backup of the current live config.

Example:

```bash
cp ~/.hammerspoon/init.lua ~/.hammerspoon/init.lua.backup.$(date +%Y%m%d-%H%M%S)
```

If you already have custom helper files in `~/.hammerspoon`, back those up too.

## Install With Symlinks

Symlinks are the easiest way to edit the repo and have Hammerspoon use it directly.

Example:

```bash
REPO_PATH="/path/to/HammerspoonWorkMode"
mkdir -p ~/.hammerspoon
rm -f ~/.hammerspoon/init.lua
rm -rf ~/.hammerspoon/modules ~/.hammerspoon/config
ln -s "$REPO_PATH/init.lua" ~/.hammerspoon/init.lua
ln -s "$REPO_PATH/modules" ~/.hammerspoon/modules
ln -s "$REPO_PATH/config" ~/.hammerspoon/config
```

## Alternative: Copy Files

If you do not want symlinks, you can copy the files instead.

```bash
REPO_PATH="/path/to/HammerspoonWorkMode"
mkdir -p ~/.hammerspoon
cp "$REPO_PATH/init.lua" ~/.hammerspoon/init.lua
cp -R "$REPO_PATH/modules" ~/.hammerspoon/modules
cp -R "$REPO_PATH/config" ~/.hammerspoon/config
```

Symlinks are usually better for active development.

## Configure GPS And Mode Switching

Open `~/.hammerspoon/config/default.lua` and set:

- `location.enabled`
- `location.block_inside_geofence`
- `location.lab_relaxes_blocks`
- `location.lab_geofence.latitude`
- `location.lab_geofence.longitude`
- `location.lab_geofence.radius`

Interpretation:

- inside radius -> `BLOCK`
- outside radius -> `ALLOW`

If you want the default behavior, leave `block_inside_geofence = true`.

If you want to flip the model so the geofence becomes the relaxed area instead, set `block_inside_geofence = false` and then use `lab_relaxes_blocks = true`.

## Configure Work-Hour Enforcement

In `~/.hammerspoon/config/default.lua`, edit:

- `schedule.enabled`
- `schedule.workdays`
- `schedule.start_hour`
- `schedule.end_hour`

This decides when the project is allowed to enforce `BLOCK` behavior.

## Configure App And Browser Rules

Also edit:

- `blocked_apps`
- `browser.allowed_domains`
- `browser.blocked_domains`
- `browser.blocked_title_terms`
- `categories.research_keywords`
- `categories.distraction_keywords`

Recommended approach:

- keep `blocked_apps` for clear non-research distractions
- keep `allowed_domains` narrow and academic
- keep `blocked_domains` focused on recurring distractions
- tune title terms only after real usage shows what slips through

## Configure Logs And Timers

Check these values:

- `user.activity_log_path`
- `user.marker_log_path`
- `user.geofence_state_path`
- `user.terminal_guard_state_path`
- `user.messages_path`
- `timers.scan_seconds`
- `timers.activity_log_seconds`
- `timers.overlay_default_seconds`
- `timers.lockout_base_seconds`
- `timers.terminal_guard_decision_seconds`

These control where evidence is stored and how quickly the system reacts.

## Customize Screen And Shell Text

Edit `config/messages.yaml` to rename the full-screen overlay text, Terminal prompt text, zsh blocked-command messages, and notification titles.

The messages file is organized by feature:

```yaml
terminal_guard:
  prompt:
    question: "Is this Terminal command related to your research work?"
shell:
  command_blocked:
    title: "Command blocked"
```

Use `\n` inside a value when you want a line break on the Hammerspoon screen.

## Configure Terminal Command Guard

The Terminal command guard has two parts:

- Hammerspoon handles `hammerspoon://terminal-check-prompt`, shows the full-screen research question, and writes `~/.hammerspoon/terminal-command-guard.state`.
- zsh reads that state file before running commands.

Add this line to `~/.zshrc`, using your actual repo path:

```zsh
source "/path/to/HammerspoonWorkMode/shell/terminal-command-guard.zsh"
```

During `BLOCK` mode, the first command opens a full-screen question:

- `Y` allows Terminal commands for 30 minutes.
- `N` blocks Terminal commands for 30 minutes and prints the remaining time for every attempted command.

Terminal and iTerm2 are listed under `terminal_guard.apps`, so the app blocker leaves those apps open and lets the command guard make the decision.

## Reload Hammerspoon

Once linked and configured:

1. Open Hammerspoon.
2. Use `Reload Config`.
3. Watch for the startup alert.
4. Confirm the menubar state appears.

## Module-By-Module Help

If you want to set up one part at a time in plain English, read:

- `docs/modules/README.md`
- `docs/modules/location-mode.md`
- `docs/modules/schedule.md`
- `docs/modules/app-blocker.md`
- `docs/modules/browser-filter.md`
- `docs/modules/activity-classifier.md`
- `docs/modules/overlay.md`
- `docs/modules/logger.md`

## Simplest Possible Onboarding

If you want the shortest beginner path after installation, use:

- `docs/fill-in-5-values.md`
- `config/starter.lua.example`

## Initial Validation Checklist

Test the project deliberately before trusting it.

- Confirm the config loads without a visible error.
- Confirm the menubar shows location state.
- Confirm activity snapshots are written to the activity log.
- Confirm marker messages are written to the marker log.
- Confirm a blocked app is closed in `BLOCK` mode.
- Confirm an allowed research site remains usable.
- Confirm a blocked domain like YouTube triggers intervention.
- Confirm moving inside the approved GPS radius changes behavior to `BLOCK`.

## Troubleshooting

### Config Reload Fails

- Check `Hammerspoon Console` for Lua errors.
- Verify that `modules/` and `config/` are actually reachable from `~/.hammerspoon`.

### Browser Detection Fails

- Recheck Automation permission.
- Verify the browser name is listed in `browser.supported_apps`.

### GPS Never Switches To `ALLOW`

- Recheck latitude, longitude, and radius.
- Recheck macOS Location Services permission.
- Test while clearly inside the geofence instead of near its edge.

### Apps Are Not Being Closed

- Make sure you are in scheduled hours.
- Make sure GPS puts you in `BLOCK`.
- Make sure the frontmost app name matches the entry in `blocked_apps`.

## Migration Notes

This repo was derived from a prebuilt `~/.hammerspoon` configuration. The modular version keeps the same ideas but separates them into understandable parts so future changes are safer and easier.
