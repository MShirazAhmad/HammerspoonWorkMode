# First Run Checklist

Use this checklist right after your first setup.

## Before Testing

Make sure:

- Hammerspoon is installed
- the project files are in `~/.hammerspoon`
- you edited `~/.hammerspoon/config/default.lua`
- you granted permissions

## Checklist

### 1. Hammerspoon Loads

Check:

- Hammerspoon opens
- no obvious error appears
- you see the startup message

### 2. Location Indicator Appears

Check:

- a menu bar indicator appears
- it changes when your location changes enough

### 3. Logs Are Being Written

Check:

- `~/web-activity.log` exists
- `~/.hammerspoon/hard-blocker.marker.log` exists

### 4. `ALLOW` Mode Works

Go inside your approved place and check:

- the system behaves more relaxed
- blocked behavior is reduced

### 5. `BLOCK` Mode Works

Go outside your approved place and check:

- the system becomes more strict

### 6. Blocked App Test

While in `BLOCK`:

1. open a blocked app
2. bring it to the front
3. see whether it closes

### 7. Blocked Website Test

While in `BLOCK`:

1. open a supported browser
2. visit a blocked website
3. bring the tab to the front
4. see whether the browser is hidden or the blocker responds

### 8. Overlay Test

Trigger a blocked action and check:

- the overlay appears
- the text is readable
- the timer counts down

## If A Step Fails

Read:

- `docs/troubleshooting.md`

That is the fastest way to find the most likely cause.
