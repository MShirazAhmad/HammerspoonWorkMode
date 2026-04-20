# Getting Started

This guide is for someone opening the project for the first time and wanting the easiest possible path.

You do not need to understand the code to use this guide.

## What You Are Setting Up

This project gives your Mac two modes:

- `BLOCK`
- `ALLOW`

Simple meaning:

- `BLOCK` means you are inside your configured work location, such as your lab desk
- `ALLOW` means you are anywhere else

This is meant to protect research time in a very practical way:

- choose one place where you want the system to enforce focus discipline
- when you are sitting there, the system controls behavior and closes distractions
- once you leave that place, the system relaxes and does not limit anything

In `BLOCK`, the system can close blocked apps, react to distracting websites, show a full-screen warning, and restrict tools like Terminal or Claude if you put them on your blocked list.

## What You Need Before Starting

- a Mac
- Hammerspoon installed
- this repo downloaded onto your Mac

## The Easiest First Setup

Follow these steps in order.

If you want an even shorter path, also open:

- `docs/fill-in-5-values.md`
- `config/starter.lua.example`

### Step 1: Put The Project In `~/.hammerspoon`

Make sure these exist:

- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/modules/`
- `~/.hammerspoon/config/`

If you need help, read `docs/setup.md`.

### Step 2: Open The Main Settings File

Open:

- `~/.hammerspoon/config/default.lua`

This is the main file you will edit.

If you want a beginner example while editing, keep this open too:

- `config/starter.lua.example`

## Step 3: Enter Your Enforced Work Location

Find:

```lua
location = {
    enabled = true,
    block_inside_geofence = true,
    lab_geofence = {
        latitude = ...,
        longitude = ...,
        radius = ...,
    },
}
```

Put in:

- the latitude of your work location, such as your lab desk
- the longitude of that same place
- a radius in meters

This location is your enforced zone.

When you are physically there, the system actively controls your behavior.

That means:

- blocked apps are force-closed
- distracting browser tabs trigger enforcement
- off-task behavior shows a full-screen overlay
- tools like Claude or Terminal are blocked if you listed them

When you leave, the system relaxes completely.

If you do not know these values, read `docs/find-gps-coordinates.md`.

## Step 4: Keep The First Version Small

For your first setup:

- block only a few obvious distraction apps
- allow only a few research websites
- keep the default work hours unless you need different ones

Example of a simple first setup:

- enforced location = your lab desk
- blocked apps inside the lab = `Books`, `Claude`, `Terminal`, `TextEdit`
- blocked sites inside the lab = `youtube.com`, `reddit.com`

You can always add more later.

## Step 5: Give macOS Permissions

You must give Hammerspoon permission to:

- control apps
- read browser tab information
- read location

Read:

- `docs/permissions.md`

## Step 6: Reload Hammerspoon

After saving `default.lua`:

1. open Hammerspoon
2. choose `Reload Config`
3. look for the startup message

## Step 7: Test It

Now test the system:

1. go to your work location and check whether it behaves like `BLOCK`
2. go outside that place and check whether it behaves like `ALLOW`
3. open a blocked app while inside the geofence
4. open a blocked website while inside the geofence
5. if you blocked Terminal, Claude, or other tools, test those inside the enforced zone

For a more complete test, read:

- `docs/first-run-checklist.md`

## If Something Goes Wrong

Read:

- `docs/troubleshooting.md`

That document covers the most common first-time problems.
