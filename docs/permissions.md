# Permissions

This project depends on several macOS permissions because it watches apps, reads browser state, and uses GPS to switch between `ALLOW` and `BLOCK`.

## Required Permissions

### Accessibility

Why it matters:

- detects app activation
- controls or closes blocked apps
- works with overlays and frontmost app state

Grant it at:

- `System Settings -> Privacy & Security -> Accessibility`

### Automation

Why it matters:

- reads browser tab title and URL using AppleScript
- supports Safari, Chrome, Arc, Brave, Edge, Opera, and Vivaldi workflows

Grant it at:

- `System Settings -> Privacy & Security -> Automation`

If `browser_filter.lua` is not seeing tabs, this permission is the first thing to inspect.

### Location Services

Why it matters:

- decides whether the system is in `ALLOW` or `BLOCK`
- drives the geofence-based mode switch

Grant it at:

- `System Settings -> Privacy & Security -> Location Services`

If Location Services is missing or denied, the GPS-based model cannot behave reliably.

## Helpful Permissions

### Screen Recording

This version does not require it for core logic, but it can be useful later if you extend the project to richer activity capture.

Grant it at:

- `System Settings -> Privacy & Security -> Screen Recording`

## Permission Testing

After granting permissions, test in this order:

1. Reload Hammerspoon.
2. Open a supported browser and visit a known blocked domain.
3. Verify the tab is detected.
4. Move inside or outside the approved GPS area.
5. Verify the mode label changes.

If mode switching works but browser filtering does not, the issue is usually Automation.

If browser filtering works but mode switching does not, the issue is usually Location Services or geofence values.
