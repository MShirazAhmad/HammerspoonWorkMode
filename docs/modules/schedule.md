# Schedule

## What This Module Does

This module decides what hours the blocker should care about.

Example:

- Monday to Friday
- 9 AM to 5 PM

If the current time is outside your work schedule, the blocker becomes much less active.

## File Used By This Module

- `~/.hammerspoon/modules/schedule.lua`

## Settings You Need To Edit

Open:

- `~/.hammerspoon/config/default.lua`

Find the `schedule = { ... }` section.

Important settings:

- `enabled`
- `workdays`
- `start_hour`
- `end_hour`

## How To Install It

Make sure these files exist:

- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/modules/schedule.lua`
- `~/.hammerspoon/config/default.lua`

## How To Activate It

1. Open `~/.hammerspoon/config/default.lua`
2. Find `schedule = { ... }`
3. Set `enabled = true`
4. Choose which days should count as work days
5. Set start and end hour
6. Save the file
7. Reload Hammerspoon

## How To Turn It Off

Set:

```lua
schedule = {
    enabled = false,
}
```

Then reload Hammerspoon.

When schedule is off, time will no longer limit enforcement.

## How To Test It

1. Set a very short test window, such as the current hour
2. Reload Hammerspoon
3. Check whether the blocker behaves differently inside and outside that time window

## Best Advice For Non-Programmers

Keep your first version simple.

Start with:

- weekdays only
- one start time
- one end time

You can always make it more detailed later.
