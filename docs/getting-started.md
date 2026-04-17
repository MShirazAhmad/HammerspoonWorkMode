# Getting Started

This guide is for someone opening the project for the first time and wanting the easiest possible path.

You do not need to understand the code to use this guide.

## What You Are Setting Up

This project gives your Mac two modes:

- `ALLOW`
- `BLOCK`

Simple meaning:

- `ALLOW` means you are in one approved place, such as a lab
- `BLOCK` means you are anywhere else

This is meant to protect research time in a very practical way:

- choose one place where you want full freedom for serious work
- when you are sitting there, the system should not limit how you use your MacBook
- once you leave that place, the system becomes stricter and starts controlling behavior

In `BLOCK`, the system can close blocked apps, react to distracting websites, show a full-screen warning, and restrict tools like Terminal if you put them on your blocked list.

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

## Step 3: Enter One Approved GPS Place

Find:

```lua
location = {
    enabled = true,
    lab_relaxes_blocks = true,
    lab_geofence = {
        latitude = ...,
        longitude = ...,
        radius = ...,
    },
}
```

Put in:

- the latitude of your approved place
- the longitude of your approved place
- a radius in meters

This approved place is your freedom zone.

When you are physically there, the system should mostly leave you alone.

When you are not there, the system should become stricter.

If you do not know these values, read `docs/find-gps-coordinates.md`.

## Step 4: Keep The First Version Small

For your first setup:

- block only a few obvious distraction apps
- allow only a few research websites
- keep the default work hours unless you need different ones

Example of a simple first setup:

- approved location = your lab
- blocked apps outside the lab = `Books`, `Terminal`, `TextEdit`
- blocked sites outside the lab = `youtube.com`, `reddit.com`

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

1. go to your approved place and check whether it behaves like `ALLOW`
2. go outside that place and check whether it behaves like `BLOCK`
3. open a blocked app in `BLOCK`
4. open a blocked website in `BLOCK`
5. if you blocked Terminal or command prompt tools, test those too outside the approved place

For a more complete test, read:

- `docs/first-run-checklist.md`

## If Something Goes Wrong

Read:

- `docs/troubleshooting.md`

That document covers the most common first-time problems.
