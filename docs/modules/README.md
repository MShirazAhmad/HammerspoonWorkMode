# Module Guides

This folder explains each module in plain language.

These guides are written for someone who is not a programmer and just wants to set up the system step by step.

## Read These In This Order

1. [Location Mode](./location-mode.md)
2. [Schedule](./schedule.md)
3. [App Blocker](./app-blocker.md)
4. [Browser Filter](./browser-filter.md)
5. [Activity Classifier](./activity-classifier.md)
6. [Overlay](./overlay.md)
7. [File Path Blocker](./file-path-blocker.md)
8. [Folder Blocker](./folder-blocker.md)
9. [HTTP Blocker](./http-blocker.md)
10. [Messages](./messages.md)
11. [Logger](./logger.md)

## Important Idea

You do not usually install one module by itself.

In normal use:

- `~/.hammerspoon/init.lua` loads all modules together
- each module becomes active automatically when Hammerspoon reloads
- most of your control comes from editing `~/.hammerspoon/config/default.lua`

So in these guides, "install and activate a module" usually means:

1. make sure the module file exists in `~/.hammerspoon/modules/`
2. make sure `~/.hammerspoon/init.lua` is using that module
3. turn on the matching settings in `~/.hammerspoon/config/default.lua`
4. reload Hammerspoon

## Before You Start

Make sure you already completed the main setup guide in [docs/setup.md](../setup.md).
