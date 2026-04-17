# HammerspoonWorkMode

`HammerspoonWorkMode` is a GPS-aware Hammerspoon configuration for protecting research time.

The idea is simple and very practical:

- you choose one approved location where you do your real research work
- when you are physically sitting in that location, the system stays out of your way
- when you leave that location, the system starts controlling how you use your MacBook so it is harder to drift

That means one place is your freedom zone for research, and everywhere else becomes a guarded zone.

## Start Here

If you are opening this project for the first time, follow these documents in this order:

1. `docs/setup.md`
2. `docs/getting-started.md`
3. `docs/fill-in-5-values.md`
4. `docs/find-gps-coordinates.md`
5. `docs/find-app-names.md`
6. `docs/permissions.md`
7. `docs/first-run-checklist.md`
8. `docs/troubleshooting.md`

If you want the shortest possible path, use the quick start below.

## Quick Start

1. Install Hammerspoon on your Mac.
2. Put this repo somewhere stable on your computer.
3. Link or copy `init.lua`, `modules/`, and `config/` into `~/.hammerspoon/`.
4. Open `~/.hammerspoon/config/default.lua`.
5. Set your approved GPS place:
   `latitude`, `longitude`, `radius`
6. Leave `lab_relaxes_blocks = true` if you want that approved place to behave like `ALLOW`.
7. Edit your blocked apps and browser rules.
8. Give Hammerspoon Accessibility, Automation, and Location permissions.
9. Reload Hammerspoon.
10. Test one allowed place and one blocked place.

If you want the least confusing first setup, open:

- `docs/fill-in-5-values.md`
- `config/starter.lua.example`

## What This Really Means In Daily Life

Think of it like this:

- when you are in your chosen research location, such as your lab or another approved work spot, there are no extra limitations on what you use
- you can open Terminal, browsers, editors, PDFs, research tools, or whatever else you need
- once you leave that location, the system starts watching and controlling behavior more strictly

Outside the approved place, the system can react to things like:

- opening blocked apps
- visiting distracting websites
- switching to off-task tabs
- using tools like Terminal or command prompt if you decided those should be restricted in `BLOCK` mode

So the goal is not "block everything all the time."

The goal is:

- full freedom in the place where you do serious research
- behavior control outside that place so research time is protected

## Minimum Working Setup

If you want the easiest first version, do only this:

- turn on `location.enabled = true`
- enter one approved location in `lab_geofence`
- leave `lab_relaxes_blocks = true`
- keep weekday work hours
- block only a few obvious distractions
- keep a few research-safe domains such as `arxiv.org` and `overleaf.com`

That is enough to get a real first version running.

The core idea is intentionally simple:

- `ALLOW` mode means you are inside an approved GPS area, such as the lab.
- `BLOCK` mode means you are outside that approved GPS area, such as at home or elsewhere.

When the system is in `ALLOW` mode, it stays out of your way so you can use your MacBook freely in the place you chose for real work.

When the system is in `BLOCK` mode, it actively protects writing, reading, coding, and analysis time by closing blocked apps, detecting distracting browser activity, showing full-screen warnings, and logging what happened.

This repo turns a large, prebuilt `~/.hammerspoon/init.lua` into a modular project you can version, tune, and extend.

## Mental Model

Think of the project as a state machine driven by location first.

1. `location_mode.lua` checks GPS against your configured geofence.
2. If you are inside the approved radius, the system enters `ALLOW`.
3. If you are outside the approved radius, the system enters `BLOCK`.
4. `schedule.lua` narrows enforcement to the hours you care about.
5. `app_blocker.lua`, `browser_filter.lua`, `activity_classifier.lua`, and `overlay.lua` enforce the current mode.
6. `logger.lua` records snapshots, events, and violations so you can review behavior later.

In short:

- GPS answers: "Where am I?"
- Schedule answers: "Should this be enforced right now?"
- Enforcement modules answer: "What should happen on this screen?"

## Allow / Block Behavior

### `ALLOW` Mode

`ALLOW` mode is intended for an approved place such as the lab.

Default behavior:

- app blocking is relaxed
- distracting tabs are not aggressively hidden
- overlays do not keep interrupting normal work
- activity is still logged
- the menubar label shows that the approved location is active
- you can use tools like Terminal, browsers, editors, PDFs, and other research tools without the system getting in your way

This is the location where you trust yourself to work freely.

### `BLOCK` Mode

`BLOCK` mode is intended for places where distraction risk is higher, such as home.

Default behavior:

- blocked non-research apps are closed if they become active
- distracting browser URLs and titles trigger enforcement
- off-task behavior can trigger a full-screen overlay
- repeated violations can increase lockout duration
- events and snapshots are logged for later review
- tools like Terminal or command prompt can also be restricted if you put them in the blocked app list

This is the behavior-control mode that protects research time outside your approved work location.

## Research Use Case

This project is built around work such as:

- dissertation writing
- literature review
- reading papers and PDFs
- coding for experiments
- analysis notebooks and scripts
- Zotero / Overleaf workflows
- research-related browsing
- research-related AI use

A very simple real-world use case is:

- choose your lab as the approved location
- when you are sitting in the lab, use your MacBook however you need for research
- when you leave the lab, the system becomes stricter and starts controlling distracting or non-research behavior

That can include browser behavior, app behavior, and even apps like Terminal if you choose to block them outside the approved location.

The default configuration assumes that context matters. Browsers, terminals, and editors can all be productive tools, but some apps, domains, and tabs are much more likely to pull attention away from research.

## Distraction Categories Blocked During Writing / Analysis

The default configuration blocks or flags categories that commonly break deep work:

- social media
- streaming and short-form video
- shopping
- sports
- entertainment and celebrity news
- general news rabbit holes
- gaming and game-related browsing
- community/chat sites that are not clearly research-related

The specific domains, title terms, thresholds, and blocked apps live in `~/.hammerspoon/config/default.lua`.

## Architecture

### Entry Point

- `~/.hammerspoon/init.lua`
  Loads configuration, starts timers/watchers, computes current mode, logs snapshots, and dispatches enforcement.

### Core Modules

- `~/.hammerspoon/modules/location_mode.lua`
  Reads macOS location data, compares it to the geofence, publishes `ALLOW` or `BLOCK`, writes a state file, and updates the menubar indicator.

- `~/.hammerspoon/modules/schedule.lua`
  Applies work-hour rules so the system only enforces during the schedule you define.

- `~/.hammerspoon/modules/app_blocker.lua`
  Detects frontmost blocked apps and closes them during `BLOCK` mode.

- `~/.hammerspoon/modules/browser_filter.lua`
  Reads frontmost browser tab title and URL using AppleScript, checks against allowed and blocked lists, and hides the browser when a distracting tab is detected.

- `~/.hammerspoon/modules/activity_classifier.lua`
  Classifies visible activity as `research`, `neutral`, or `off_task` based on app, domain, and title keywords.

- `~/.hammerspoon/modules/overlay.lua`
  Shows the full-screen intervention UI, countdown timer, and escalating lockout behavior.

- `~/.hammerspoon/modules/logger.lua`
  Writes marker logs and JSON activity logs.

### Configuration

- `~/.hammerspoon/config/default.lua`
  User-editable defaults for geofence, work hours, blocked apps, allowed domains, distraction keywords, log paths, and timing thresholds.

### Documentation

- `docs/getting-started.md`
  Plain-English first-time setup guide for non-programmers.

- `docs/setup.md`
  Full installation and bootstrapping guide.

- `docs/first-run-checklist.md`
  A simple step-by-step list to confirm the system is working.

- `docs/fill-in-5-values.md`
  The shortest onboarding path: only 5 values to change first.

- `docs/find-gps-coordinates.md`
  How to find the location values you need for `ALLOW` mode.

- `docs/find-app-names.md`
  How to find the exact macOS app names to use in the block list.

- `docs/permissions.md`
  macOS permissions required for reliable operation.

- `docs/troubleshooting.md`
  Common setup failures and what to do next.

- `docs/workflow-examples.md`
  Example flows for `ALLOW` and `BLOCK`.

- `docs/project-guidelines.md`
  Guidelines for maintaining and extending the project safely.

- `docs/modules/README.md`
  Beginner-friendly module-by-module setup guides.

- `config/starter.lua.example`
  A minimal beginner-ready example config.

## Full Setup Guide

Use `docs/setup.md` for the full install steps.

Then use:

- `docs/getting-started.md` for the easiest first setup
- `docs/fill-in-5-values.md` for the smallest possible first edit
- `docs/first-run-checklist.md` to test everything
- `docs/troubleshooting.md` if anything fails

## Operating Guidelines

### Daily Use

- keep the geofence accurate
- keep blocked apps limited to things you genuinely do not want during research blocks
- keep allowed domains narrow and intentional
- review the log files occasionally to see whether the rules are doing what you expect

### Tuning Philosophy

- prefer small edits in `config/default.lua` before changing module logic
- add a domain to `allowed_domains` only when it is repeatedly useful for research
- add a domain to `blocked_domains` when it repeatedly causes drift
- keep title keyword rules broad enough to catch distractions, but not so broad that they punish legitimate research pages

### Safety Notes

- browser automation depends on macOS Automation permission
- GPS can be temporarily inaccurate, so test around the edge of the radius before trusting it fully
- full-screen overlays are intentionally disruptive, so keep durations realistic while tuning

## Logs And State Files

By default the project uses paths derived from your existing setup:

- activity log: `~/web-activity.log`
- marker log: `~/.hammerspoon/hard-blocker.marker.log`
- geofence state file: `~/.hammerspoon/manage-py-geofence.state`

These can be adjusted in `~/.hammerspoon/config/default.lua`.

## Current Status

This repo is now documented as an `ALLOW` / `BLOCK` GPS-driven research blocker and is structured to replace the older monolithic `.hammerspoon` config over time.
