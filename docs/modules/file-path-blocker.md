# File Path Blocker

## What This Module Does

This module scans Accessibility document attributes of running apps and checks whether the files or folders they have open are on the approved list. During `BLOCK` mode, accessing a known blocked path kills the owning app immediately. Accessing an unknown path triggers a Y/N approval prompt.

The module reduces every file path to its containing folder before making a decision, so allowing or blocking a folder applies to everything inside it.

## Files Used By This Module

- `~/.hammerspoon/modules/file_path_blocker.lua`

## How It Works

On every enforcement pass (every 2 seconds and on app activation):

1. For each monitored app, read `AXDocument`, `AXFilename`, and `AXURL` accessibility attributes from all open windows.
2. Reduce each file path to its containing folder.
3. Check that folder against:
   - `allowed_paths` (recursive roots)
   - `exact_allowed_paths` (exact container match only)
   - `blocked_paths` (recursive blocked roots)
   - `exact_blocked_paths` (exact blocked paths)
   - State files loaded from disk
4. If the folder is explicitly blocked, kill the app immediately.
5. If the folder is unknown, show a Y/N approval prompt.
6. If the folder is allowed, take no action.

Headless processes (such as MCP servers) are inspected via `lsof` using patterns listed in `monitored_process_patterns`.

## Configuration

Open `~/.hammerspoon/config/default.lua` and find the `file_path_blocker = { ... }` section.

Key settings:

```lua
file_path_blocker = {
    enabled = true,
    violation_overlay_seconds = 5,
    allowed_paths = {
        -- Recursive roots: anything under these paths is allowed
        home .. "/.hammerspoon",
        home .. "/Documents/GitHub/my-research-project",
    },
    exact_allowed_paths = {
        -- Exact paths only: the folder itself is allowed, but children are not
        home,
        home .. "/Documents/GitHub",
    },
    blocked_paths = {},
    exact_blocked_paths = {},
    monitored_apps = {
        "Finder", "Terminal", "iTerm2", "Code", "Visual Studio Code",
        "PyCharm", "PyCharm CE", "Preview", "Obsidian", "Zotero",
    },
    monitored_process_patterns = {
        "mcp",
        "model-context-protocol",
    },
}
```

## State Files

Path decisions persist across sessions using four state files. The Y/N approval prompt writes to these files so the decision is remembered after Hammerspoon reloads.

| File | Meaning |
|---|---|
| `~/.hammerspoon/allowed-folders.state` | Recursive roots the user has approved |
| `~/.hammerspoon/exact-allowed-paths.state` | Exact-only paths the user has approved |
| `~/.hammerspoon/blocked-paths.state` | Recursive roots the user has blocked |
| `~/.hammerspoon/exact-blocked-paths.state` | Exact-only paths the user has blocked |

Each file contains one absolute path per line.

## The Difference Between `allowed_paths` and `exact_allowed_paths`

- **`allowed_paths`**: A recursive root. Any file at the root or anywhere below it is allowed.
  - Example: `~/Documents/GitHub/my-project` allows `~/Documents/GitHub/my-project/src/main.py`
- **`exact_allowed_paths`**: Exact container only. Children are not automatically allowed.
  - Example: `~/Documents/GitHub` allows opening the `~/Documents/GitHub` folder itself but not `~/Documents/GitHub/my-project/`

Use `exact_allowed_paths` for navigation folders you need to browse but do not want to automatically approve all projects inside.

## Troubleshooting

**Prompt appears for a folder you always want to allow**

Add the folder to `allowed_paths` in `config/default.lua`, then reload Hammerspoon.

**App is killed for a path you expected to be allowed**

Run the dry-run command from a terminal (requires the Hammerspoon `hs` CLI):

```bash
/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c \
  'package.path = hs.configdir .. "/?.lua;" .. hs.configdir .. "/?/init.lua;" .. package.path
   local config = require("config.default")
   local B = require("modules.file_path_blocker")
   local b = B.new(config, {marker=function() end})
   local rows = {}
   for _, i in ipairs(b:scanOpenFilePaths()) do
     if i.allowed == false then
       table.insert(rows, {app=i.app, path=i.path, title=i.title})
     end
   end
   return hs.json.encode(rows, true)'
```

**Prompt does not appear**

- Confirm Hammerspoon has Accessibility permission.
- Confirm the app is listed in `monitored_apps`.
- Check `~/.hammerspoon/hard-blocker.marker.log` for `file_path_blocker` entries.
