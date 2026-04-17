# Logger

## What This Module Does

This module writes down what the system is doing.

It creates two main kinds of records:

- activity records
- marker records

Activity records are useful when you want to review what was on screen over time.

Marker records are useful when you want to know why the blocker reacted.

## File Used By This Module

- `~/.hammerspoon/modules/logger.lua`

## Settings You Need To Edit

Open:

- `~/.hammerspoon/config/default.lua`

Important settings:

- `user.activity_log_path`
- `user.marker_log_path`
- `timers.activity_log_seconds`

## How To Install It

Make sure these files exist:

- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/modules/logger.lua`
- `~/.hammerspoon/config/default.lua`

## How To Activate It

This module becomes active automatically when Hammerspoon loads the project.

There is no separate switch for normal use.

## Where The Logs Go

By default:

- activity log: `~/web-activity.log`
- marker log: `~/.hammerspoon/hard-blocker.marker.log`

You can change these paths in `default.lua`.

## How To Turn It Down

If you want fewer activity records:

- raise `timers.activity_log_seconds`

That means the system writes snapshots less often.

## How To Test It

1. Reload Hammerspoon
2. Use your computer for a few minutes
3. Open the activity log file
4. Open the marker log file
5. Check whether new entries were added

## Why This Module Matters

Without logs, it becomes much harder to answer questions like:

- Why did the blocker trigger?
- Was I in `ALLOW` or `BLOCK`?
- Was the current app detected correctly?

## Best Advice For Non-Programmers

Leave logging on, especially while you are still tuning the system.

Logs are the easiest way to understand what the setup is doing.
