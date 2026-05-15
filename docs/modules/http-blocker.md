# HTTP Blocker

## What This Module Does

This module enforces network traffic restrictions at the system level during `BLOCK` mode. It uses macOS firewall rules (`pfctl`) to block all ports **except** port 443 (HTTPS) and port 53 (DNS).

The result is that while `BLOCK` is active, every app on your Mac — browsers, curl, background processes, and APIs — can only reach the internet over HTTPS. Plain HTTP connections and any non-standard port are blocked at the network level.

This module runs underneath browser-level filtering. It does not replace [Browser Filter](browser-filter.md); it adds a network-layer backstop.

## Files Used By This Module

- `~/.hammerspoon/modules/http_blocker.lua`

## How It Works

The module is called from `init.lua` on every mode transition:

- **Entering `BLOCK`**: Writes a `pfctl` anchor named `com.hammerspoon/http-blocker` that passes port 443 and 53, blocks everything else.
- **Exiting `BLOCK`**: Flushes all rules from the anchor, restoring normal network access.
- **On reload**: `cleanup()` is called at startup to remove any rules left over from a previous Hammerspoon session.

## System Requirement

The `pfctl` changes require administrator (sudo) access. The first time the module activates `BLOCK` mode, macOS will prompt for your password to allow the firewall changes. After that it uses the cached credentials.

## Configuration

There are no user-facing config keys for HTTP Blocker in `config/default.lua`. It activates and deactivates automatically with `BLOCK` mode.

If you want to disable network-level blocking without changing mode logic, you can comment out the `httpBlocker:updateForStrictMode()` call in `init.lua`'s `enforce()` function.

## Relationship to Browser Filter

| | Browser Filter | HTTP Blocker |
|---|---|---|
| **What it watches** | Front browser tab URL and title | All network ports, all apps |
| **What it does on violation** | Shows red warning overlay | Drops non-HTTPS/non-DNS packets |
| **Requires** | Automation permission | sudo/admin access |
| **Scope** | Browser only | System-wide |

Both modules are active during `BLOCK` mode and complement each other.

## Troubleshooting

**Firewall rules are not cleaned up after a crash**

Reload Hammerspoon. The `cleanup()` call at startup removes any leftover rules.

To check manually:

```bash
sudo pfctl -a com.hammerspoon/http-blocker -sr 2>/dev/null
```

If this returns rules when Hammerspoon is in `ALLOW` mode, reload Hammerspoon or run:

```bash
sudo pfctl -a com.hammerspoon/http-blocker -F rules
```

**HTTPS connections fail in BLOCK mode**

HTTPS (port 443) is explicitly allowed. If HTTPS is failing, check whether another firewall rule on your machine is more restrictive.

**Module is not activating**

Check `~/.hammerspoon/hard-blocker.marker.log` for `http_blocker` entries. If none appear, confirm you are testing while clearly inside the geofence during scheduled hours.
