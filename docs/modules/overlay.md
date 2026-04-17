# Overlay

## What This Module Does

This module creates the full-screen warning screen.

It is the part of the project you actually see when the blocker steps in.

The overlay can show:

- a warning message
- a reason
- a countdown timer

If you keep drifting, the overlay can stay longer.

## File Used By This Module

- `~/.hammerspoon/modules/overlay.lua`

## Settings You Need To Edit

Open:

- `~/.hammerspoon/config/default.lua`

Important sections:

- `overlay`
- `timers`
- `thresholds`

Most important settings:

- `overlay.title`
- `overlay.subtitle`
- `overlay.background_alpha`
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

1. Make sure you are in `BLOCK` mode
2. Open a blocked website or blocked app
3. Wait for the blocker to respond
4. Check whether the overlay appears
5. Check whether the timer behaves as expected

## Best Advice For Non-Programmers

Do not start by making long lockouts.

Begin with short test times until you trust the system.
