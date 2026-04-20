# Fill In These 5 Values Only

If you feel overwhelmed by the full configuration, start here.

You do not need to understand the whole project.

Just open:

- `~/.hammerspoon/config/default.lua`

Then change these 5 things first.

## 1. Your Work Location Latitude

Find:

```lua
latitude = ...
```

Replace it with the latitude of the place where you want focus to be enforced, such as your lab desk.

## 2. Your Work Location Longitude

Find:

```lua
longitude = ...
```

Replace it with the longitude of the same place.

## 3. Your Work Location Radius

Find:

```lua
radius = ...
```

Use a reasonable starting radius such as:

- `50`
- `75`
- `100`

This is measured in meters.

## 4. Your Blocked Apps Inside That Place

Find:

```lua
blocked_apps = {
}
```

Add only a few obvious apps at first.

Example:

```lua
blocked_apps = {
    "Books",
    "Claude",
    "Terminal",
    "TextEdit",
}
```

These apps will be force-closed when you are inside the geofence during work hours.

## 5. Your Blocked Websites Inside That Place

Find:

```lua
blocked_domains = {
}
```

Add only a few obvious distractions at first.

Example:

```lua
blocked_domains = {
    "youtube.com",
    "reddit.com",
    "instagram.com",
}
```

## After You Change Those 5 Things

1. Save the file.
2. Reload Hammerspoon.
3. Test the system inside your work location — it should enforce.
4. Test the system outside your work location — it should relax.

## If You Want An Easier Starting Point

Look at:

- `config/starter.lua.example`

That file shows a small beginner-friendly setup with obvious placeholders.

## If You Need Help Finding The Values

Read:

- `docs/find-gps-coordinates.md`
- `docs/find-app-names.md`
- `docs/first-run-checklist.md`
- `docs/troubleshooting.md`
