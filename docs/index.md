# HammerspoonWorkMode

GPS-aware Hammerspoon configuration for protecting research time on macOS.

## The Core Idea

This project gives your Mac two modes:

- **`BLOCK`** — you are physically inside your configured work location (your lab, desk, or office). The system enforces focus rules.
- **`ALLOW`** — you are anywhere else. The system stays out of your way completely.

That means your desk is your guarded zone for focused work, and everywhere else becomes your freedom zone.

## What It Does In BLOCK Mode

When you are inside the configured geofence and within scheduled work hours:

- blocked apps are force-closed when they come to the front
- distracting browser tabs raise a full-screen red warning until you close or change them
- off-task behavior can trigger escalating warning overlays
- Terminal and other tools can be routed through a Y/N research-check prompt
- file and folder access can be gated to a pre-approved list

## What It Does In ALLOW Mode

When you are outside the geofence:

- all blocking is off
- browser enforcement is off
- overlays do not appear
- activity is still logged
- the menu bar shows `ALLOW`

## Quick Start

1. Install [Hammerspoon](https://www.hammerspoon.org) on your Mac.
2. Put this repo somewhere stable on your computer.
3. Link or copy `init.lua`, `modules/`, and `config/` into `~/.hammerspoon/`.
4. Open `~/.hammerspoon/config/default.lua` and fill in your GPS coordinates and blocked apps.
5. Give Hammerspoon Accessibility, Automation, and Location permissions.
6. Reload Hammerspoon.
7. Test inside your work location and outside it.

For the shortest possible first setup, start with [Fill In 5 Values](fill-in-5-values.md).

For the full installation walkthrough, read [Installation](setup.md).

## Navigation

| If you want to… | Read… |
|---|---|
| Get set up for the first time | [Getting Started](getting-started.md) |
| Do the shortest possible first edit | [Fill In 5 Values](fill-in-5-values.md) |
| See the full install steps | [Installation](setup.md) |
| Grant the required permissions | [Permissions](permissions.md) |
| Find your GPS coordinates | [Find GPS Coordinates](find-gps-coordinates.md) |
| Find your app names | [Find App Names](find-app-names.md) |
| Verify everything works | [First Run Checklist](first-run-checklist.md) |
| Look up every config key | [Configuration Reference](configuration.md) |
| Understand each module | [Module Guides](modules/README.md) |
| Fix a problem | [Troubleshooting](troubleshooting.md) |

## Architecture Summary

```
GPS + Schedule → BLOCK / ALLOW
     └─► AppBlocker        kills blocked frontmost apps
     └─► BrowserFilter     raises red warning for distracting tabs
     └─► FilePathBlocker   gates folder/file access
     └─► ActivityClassifier flags off-task heuristics
     └─► Overlay            shows the warning screen
     └─► HTTPBlocker        blocks non-HTTPS network ports
```

All behavior is configured in `~/.hammerspoon/config/default.lua`.
Message text is customized in `~/.hammerspoon/config/messages.yaml`.

## Privacy Note

Runtime files are intentionally ignored by git. Do not publish your local logs, GPS state, terminal decision state, or path decision state files.
