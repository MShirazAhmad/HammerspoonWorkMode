# Folder Blocker

## What This Module Does

This module monitors applications (VS Code, IDEs, editors) for newly opened folder paths. When a new folder is detected during `BLOCK` mode, it shows a Y/N prompt:

**"Is this folder related to work?"**

- **YES** → folder is added to the allowed list in `~/.hammerspoon/allowed-folders.state`
- **NO** → the frontmost app is killed immediately

Terminal `cd` commands are also gated by reading the allowed folders list, so users cannot `cd` into non-approved paths during `BLOCK` mode.

## How It Works

### Phase 1: Folder Detection

When a monitored app becomes frontmost:
1. Parse the window title for folder path (app-specific regex patterns)
2. Normalize the path (expand ~, resolve symlinks)
3. Check if this is a NEW folder (debounced to 2 seconds)
4. If new and not already in allowed list → trigger prompt

### Phase 2: User Approval

A full-screen Y/N overlay appears:
- Title: "IS THIS WORK?"
- Question: Displays the folder path
- Response options: **Y** (approve) or **N** (block)
- Timeout: 300 seconds (safety net)

### Phase 3: Enforcement

**If YES (approved):**
- Add the folder path to `~/.hammerspoon/allowed-folders.state`
- Show alert: "Folder approved"
- Continue working in that folder

**If NO (blocked):**
- Kill the frontmost app with SIGKILL
- Show alert: "App closed: Non-work folder blocked"
- Prevent access to that path

### Terminal cd Blocking

The shell guard (`terminal-command-guard.zsh`) also checks `cd` commands:
1. When you type `cd /some/path` and press Enter
2. Parse the target path from the command
3. Check if it's in the allowed list
4. If NOT in the list and you're in BLOCK mode → block the cd
5. Show: "cd: folder access blocked"

## Configuration

Edit `~/.hammerspoon/config/default.lua`:

```lua
folder_blocker = {
    monitored_apps = {
        "Visual Studio Code",
        "Code",
        "Xcode",
        "PyCharm",
        "PyCharm CE",
        "IntelliJ IDEA",
        "Sublime Text",
        "Atom",
    },
},
```

Add more apps as needed. The module attempts to parse folder paths from window titles using app-specific patterns.

## State Files

- **`~/.hammerspoon/allowed-folders.state`**: One absolute path per line, auto-created/updated
  - Written by: Hammerspoon when user approves a folder
  - Read by: Shell guard (terminal-command-guard.zsh) to gate cd commands

Example:
```
~/projects/research
~/work/data-analysis
```

## Example Workflow

1. **Start VS Code** → open folder `~/projects/distraction-tracker`
2. **System detects new folder** → shows Y/N prompt
3. **User says NO** → VS Code is killed
4. **Try to cd manually** → shell blocks: `cd: folder access blocked`
5. **Open legitimate work folder** → user says YES
6. **Now you can cd there** → path added to allowed list

## Important Notes

- **Debouncing**: Paths are debounced (2 second window) to prevent rapid re-prompting
- **Symlink resolution**: Paths are normalized so symlinks don't bypass restrictions
- **Path normalization**: `~` is expanded, trailing slashes removed, symlinks resolved
- **Terminal commands**: Only applies during BLOCK mode
- **Outside BLOCK mode**: All folders are accessible; the Y/N prompt does not appear

## Troubleshooting

### Prompt not showing
- Make sure Hammerspoon has Accessibility permissions (System Settings → Privacy & Security → Accessibility)
- Check `~/.hammerspoon/hard-blocker.marker.log` for "folder_blocker" entries

### cd always blocked
- Run `cat ~/.hammerspoon/allowed-folders.state` to see approved paths
- Check if you're in BLOCK mode (workdays, within work hours, inside geofence)

### Window title not parsing
- Add your app to `monitored_apps` in config/default.lua
- If app window title format is different, the module may need custom regex patterns

## Advanced: Adding Custom App Support

To add support for a new app:

1. Edit `modules/folder_blocker.lua`
2. Find the `parsePathFromTitle()` function
3. Add a pattern for your app similar to the existing ones:

```lua
-- MyEditor: "project_name → /path/to/folder"
if appName == "MyEditor" then
    local path = windowTitle:match("→%s(.+)$")
    if path then return path end
end
```

4. Add your app name to `monitored_apps` in config/default.lua
5. Reload Hammerspoon
