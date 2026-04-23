# Location Mode

## What This Module Does

This module decides whether the system is in:

- `ALLOW` mode
- `BLOCK` mode

It uses your Mac's location and compares it to one approved GPS area.

Simple rule:

- inside the approved area = `BLOCK`
- outside the approved area = `ALLOW`

This is the most important module in the whole project because the rest of the behavior depends on it.

In plain language:

- this module lets you pick one place where your MacBook should enforce focus
- when you are sitting in that place, the blocker becomes strict
- when you leave that place, reminder popups and app blocking relax
- when you leave that place, the rest of the system stops controlling behavior

## File Used By This Module

- `~/.hammerspoon/modules/location_mode.lua`

## Settings You Need To Edit

Open:

- `~/.hammerspoon/config/default.lua`

Find the `location = { ... }` section.

Important settings:

- `enabled`
- `block_inside_geofence`
- `lab_relaxes_blocks`
- `lab_geofence.latitude`
- `lab_geofence.longitude`
- `lab_geofence.radius`

## How To Install It

Make sure these files exist:

- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/modules/location_mode.lua`
- `~/.hammerspoon/config/default.lua`

If you followed the main setup guide, this is already done.

## How To Activate It

1. Open `~/.hammerspoon/config/default.lua`
2. Set `location.enabled = true`
3. Enter the GPS coordinates for your approved place
4. Set a radius in meters
5. Save the file
6. Reload Hammerspoon

## What `block_inside_geofence` Means

If this is set to `true`:

- being inside the approved area enables strict enforcement
- this behaves like `BLOCK`
- this is the default project behavior

If this is set to `false`:

- the geofence no longer means "strict work zone"
- you can then use `lab_relaxes_blocks = true` to make the geofence the relaxed area instead

For most users, `true` is the right choice.

## How To Turn It Off

Open `~/.hammerspoon/config/default.lua` and set:

```lua
location = {
    enabled = false,
}
```

Then reload Hammerspoon.

When this module is off, GPS will no longer control `ALLOW` and `BLOCK`.

## How To Test It

1. Reload Hammerspoon
2. Look for the location label in the menu bar
3. Go clearly inside your approved area
4. Check whether behavior changes toward `BLOCK`
5. Go clearly outside your approved area
6. Check whether behavior changes toward `ALLOW`

## If It Does Not Work

Check these things:

- macOS Location Services is enabled for Hammerspoon
- the latitude and longitude are correct
- the radius is large enough
- you are not testing too close to the edge of the radius

## Best Advice For Non-Programmers

Do not change the code in `location_mode.lua` unless you really have to.

Just edit the values in `~/.hammerspoon/config/default.lua`.
