# App Blocker

## What This Module Does

This module closes blocked apps when they become active during `BLOCK` mode.

Example:

- if a blocked app comes to the front
- and the system is in `BLOCK`
- the app can be closed automatically

This module is best for apps that are almost never useful during deep work.

This is the part that controls how you use your MacBook after you leave the approved location.

For example, if you decide that tools like Terminal, iTerm, Books, or other apps should not be used outside your research location, this module is what enforces that choice.

## File Used By This Module

- `~/.hammerspoon/modules/app_blocker.lua`

## Settings You Need To Edit

Open:

- `~/.hammerspoon/config/default.lua`

Find the `blocked_apps = { ... }` list.

## How To Install It

Make sure these files exist:

- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/modules/app_blocker.lua`
- `~/.hammerspoon/config/default.lua`

## How To Activate It

This module becomes active automatically when:

1. the file exists in `~/.hammerspoon/modules/`
2. Hammerspoon loads `~/.hammerspoon/init.lua`
3. the system is in `BLOCK` mode
4. the app name appears in `blocked_apps`

So for most people, activation means editing the app list.

## How To Add An App To The Block List

Open `~/.hammerspoon/config/default.lua` and add the app name inside:

```lua
blocked_apps = {
    "Books",
    "Terminal",
}
```

Use the app name as macOS shows it.

That means if you leave your approved location and open Terminal, the system can close it because it is treating that as behavior you do not want outside your research place.

## How To Turn It Off

Simplest method:

- remove app names from `blocked_apps`

If the list is empty, this module has nothing to block.

## How To Test It

1. Make sure you are in `BLOCK` mode
2. Add a test app to `blocked_apps`
3. Reload Hammerspoon
4. Open that app
5. Bring it to the front
6. See whether it closes

## Important Safety Tip

Do not put mixed-use work apps here unless you are sure.

Examples of risky choices:

- browser apps
- code editors
- note-taking apps

Those are often better controlled by browser filtering or activity rules.
