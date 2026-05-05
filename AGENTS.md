# Agent Guide

Use this file first when a GPT/Codex agent needs to work on this Hammerspoon config. It is intentionally compact so future sessions do not spend tokens rediscovering the same architecture.

## Core Model

This repo is the live `~/.hammerspoon` configuration. `init.lua` is the orchestrator.

Enforcement is active only when:

1. `schedule:isActiveNow()` is true.
2. `locationMode:isRelaxed()` is false.

That combined state is called `BLOCK` mode in comments and UI. Outside that state, most blockers do nothing.

## Startup And Loop

Main flow in `init.lua`:

- load `config/default.lua`
- create singleton modules
- expose useful globals like `_G.folderBlocker` and `_G.filePathBlocker`
- start GPS polling and menu provider
- start app activation watcher
- start periodic scan timer
- run one immediate `enforce()`

`enforce()` returns after the first violation. Do not stack multiple overlays/kills in one pass unless intentionally changing that invariant.

## Enforcement Order

Current `enforce()` order:

1. `HTTPBlocker:updateForStrictMode()` toggles HTTP firewall behavior.
2. If not `BLOCK`, return after clearing stale terminal prompt state.
3. `BrowserFilter` checks frontmost browser URL/title.
4. `AppBlocker` kills frontmost blocked apps except terminal-guarded apps.
5. `FilePathBlocker` scans monitored windows/processes for disallowed paths and kills violators.
6. `FolderBlocker` detects new folder opens and may ask for approval.
7. `ActivityClassifier` applies high-confidence heuristic off-task detection.

## Important Modules

- `modules/browser_filter.lua`: AppleScript browser URL/title inspection.
- `modules/app_blocker.lua`: immediate `kill9()` for configured frontmost apps.
- `modules/file_path_blocker.lua`: strict folder path enforcement via Accessibility and targeted process/lsof checks; file paths are reduced to their containing folder before decisions.
- `modules/folder_blocker.lua`: folder approval/state workflow, older and softer than `file_path_blocker`.
- `modules/http_blocker.lua`: system HTTP firewall updates.
- `modules/overlay.lua`: gateway for red warning overlays and full-screen prompts.
- `modules/location_mode.lua`: GPS/geofence state and menu bar provider.
- `shell/terminal-command-guard.zsh`: shell-side command gate sourced from zsh.

## Path Blocking Rules

Tune path rules in `config/default.lua` under `file_path_blocker`.

Two different allow styles exist:

- `allowed_paths`: recursive roots. A file at the root or anywhere below it is allowed.
- `exact_allowed_paths`: exact container paths only. Children are not automatically allowed.

State files can add to those lists and record denied choices:

- `allowed-folders.state`: recursive roots.
- `exact-allowed-paths.state`: exact-only paths.
- `blocked-paths.state`: recursive blocked roots.
- `exact-blocked-paths.state`: exact-only blocked paths.

Current intent:

- allow `~` exactly, but not all children.
- allow `~/Documents/GitHub` exactly, but not all projects.
- allow only selected GitHub project folders recursively.
- ask about unknown paths during `BLOCK`, persist the user's allow/block choice, then reuse it.
- block Finder, Terminal, iTerm2, GUI editors, and targeted MCP-style processes from accessing known blocked paths during `BLOCK`.

## Terminal Guard

Terminal has two layers:

- Hammerspoon app/path enforcement through `FilePathBlocker`.
- zsh command interception through `shell/terminal-command-guard.zsh`.

When changing path allow logic, update both Lua and shell behavior if terminal commands should match GUI path enforcement.

The terminal guard reads:

- `terminal-command-guard.state`
- `manage-py-geofence.state`
- `allowed-folders.state`
- `exact-allowed-paths.state`
- `blocked-paths.state`
- `exact-blocked-paths.state`

## Overlay Behavior

`overlay:showIntervention()` uses normal/escalating durations.

`handleFixedViolation()` in `init.lua` is used for fixed-duration warnings such as folder path violations. Current folder path violations use `file_path_blocker.violation_overlay_seconds`, usually `5`.

## Validation Commands

Use Hammerspoon's Lua runtime, not system Lua, when possible:

```bash
/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c 'local chunk,err=loadfile("init.lua"); return hs.inspect({ok=chunk ~= nil, err=err})'
```

Check shell syntax:

```bash
zsh -n shell/terminal-command-guard.zsh
```

Dry-run folder path blocking:

```bash
/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -c 'package.path = hs.configdir .. "/?.lua;" .. hs.configdir .. "/?/init.lua;" .. package.path; local config=require("config.default"); local B=require("modules.file_path_blocker"); local b=B.new(config,{marker=function() end}); local rows={}; for _,i in ipairs(b:scanOpenFilePaths()) do if i.allowed == false then table.insert(rows,{app=i.app,path=i.path,title=i.title}) end end; return hs.json.encode(rows,true)'
```

## Editing Rules For Agents

- Prefer config changes in `config/default.lua` over hardcoding module behavior.
- Keep enforcement idempotent and fast; `scan_seconds` is short.
- Do not remove `kill9()` behavior from blockers unless explicitly requested.
- Do not broaden allowed paths accidentally. Exact path and recursive root are intentionally different.
- If adding a user-facing message, prefer `config/messages.yaml` plus defaults in `modules/messages.lua`.
- Be careful with existing dirty files and state files; this config is live.
