# Troubleshooting

This guide covers the most common setup problems for first-time users.

## Hammerspoon Does Not Load The Project

Try:

- confirm `~/.hammerspoon/init.lua` exists
- confirm `~/.hammerspoon/modules/` exists
- confirm `~/.hammerspoon/config/` exists
- open the Hammerspoon Console and look for an error message

## The System Does Not Switch Between `ALLOW` And `BLOCK`

Check:

- Location Services is enabled for Hammerspoon
- your latitude is correct
- your longitude is correct
- your radius is large enough
- you are testing clearly inside and clearly outside the approved area

Read:

- [How To Find GPS Coordinates](find-gps-coordinates.md)

## Browser Blocking Does Not Work

Check:

- Automation permission is enabled for Hammerspoon
- you are using a supported browser
- the blocked domain is written correctly
- you are testing while in `BLOCK`

## A Blocked App Does Not Close

Check:

- the app name in `blocked_apps` matches the real app name
- you are in `BLOCK`
- current time is inside the work schedule

Read:

- [How To Find App Names](find-app-names.md)

## The Overlay Never Appears

Check:

- you are in `BLOCK`
- a real violation is happening
- the blocked app or blocked website rule is actually being matched

## The Overlay Appears Too Often

Try:

- blocking fewer apps
- using fewer broad title keywords
- reducing overlay times
- raising the activity confidence threshold

## The Project Feels Too Harsh

Start smaller:

- use fewer blocked apps
- use fewer blocked sites
- shorten overlay times
- keep one simple approved location

## The Project Feels Too Weak

Try:

- adding more blocked apps
- adding more blocked domains
- adding better distraction keywords
- increasing lockout durations

## I Am Not Sure Which Doc To Read

Use this order:

1. [Getting Started](getting-started.md)
2. [Permissions](permissions.md)
3. [First Run Checklist](first-run-checklist.md)
4. [How To Find GPS Coordinates](find-gps-coordinates.md)
5. [How To Find App Names](find-app-names.md)
6. [Module Guides](modules/README.md)
