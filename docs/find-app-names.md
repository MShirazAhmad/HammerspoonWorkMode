# How To Find App Names

This guide helps you find the exact app names to use in `blocked_apps`.

Example:

```lua
blocked_apps = {
    "Books",
    "Terminal",
}
```

The names must match what macOS and Hammerspoon see.

## The Easiest Way

Use the app name exactly as it appears in:

- Finder
- Launchpad
- the top menu bar when the app is active

## Good Examples

- `Books`
- `Terminal`
- `TextEdit`
- `Activity Monitor`

## Where To Put The Names

Open:

- `~/.hammerspoon/config/default.lua`

Find:

```lua
blocked_apps = {
}
```

Add app names inside the list.

## How To Test An App Name

1. add the name to `blocked_apps`
2. save the file
3. reload Hammerspoon
4. make sure you are in `BLOCK`
5. open the app
6. bring it to the front
7. see whether it closes

If it does not close, the app name may not match exactly.

## Best Advice

Start with very obvious app names first.

Avoid adding apps that can sometimes be useful for work until you have tested carefully.

## Common Mistakes

- spelling the name differently from macOS
- adding an app that is not truly distracting
- assuming a browser should be blocked as an app instead of filtered by website
