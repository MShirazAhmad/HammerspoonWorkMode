# Overlay

## What This Module Does

This module coordinates the full-screen warning and block screens.

It is the part of the project you actually see when the blocker steps in.

The red warning overlay is awareness-only. It can show:

- a warning message
- a reason
- a countdown timer

The block screen is separate and is reserved for hard prompts or blocking flows.

If you keep drifting, warning durations can stay longer.

## File Used By This Module

- `~/.hammerspoon/modules/overlay.lua`
- `~/.hammerspoon/modules/red_warning_overlay.lua`
- `~/.hammerspoon/modules/block_screen_overlay.lua`

## Settings You Need To Edit

Open:

- `~/.hammerspoon/config/default.lua`

Important sections:

- `red_warning_overlay`
- `block_screen_overlay`
- `timers`
- `thresholds`

Most important settings:

- `overlay.title`
- `overlay.subtitle`
- `red_warning_overlay.background_alpha`
- `timers.overlay_default_seconds`
- `timers.lockout_base_seconds`
- `thresholds.max_violations_before_long_lockout`

## How To Install It

Make sure these files exist:

- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/modules/overlay.lua`
- `~/.hammerspoon/config/default.lua`

## How To Activate It

This module becomes active automatically when:

1. Hammerspoon loads the project
2. another module reports a violation

You do not normally turn it on by itself.

It is the display system used by the blocker.

## How To Customize It

You can safely change:

- the title text
- the subtitle text
- how dark the background is
- how long the overlay stays on screen

## How To Make It Less Harsh

Try:

- lowering `overlay_default_seconds`
- lowering `lockout_base_seconds`
- raising the number of allowed violations before long lockouts

## How To Test It

1. Open the ALLOW/BLOCK menubar pill
2. Choose `Test red warning`
3. Confirm the red warning reaches the notch/menu-bar and Dock edges
4. For live behavior, open a blocked website in `BLOCK` mode
5. Close or change the distracting tab/window and confirm the warning clears

## Best Advice For Non-Programmers

Do not start by making long lockouts.

Begin with short test times until you trust the system.
