# Activity Classifier

## What This Module Does

This module tries to judge whether your current visible activity looks like:

- `research`
- `neutral`
- `off_task`

It does this by checking things like:

- app name
- browser domain
- window title
- tab title

This module is softer and smarter than simple app blocking.

## File Used By This Module

- `~/.hammerspoon/modules/activity_classifier.lua`

## Settings You Need To Edit

Open:

- `~/.hammerspoon/config/default.lua`

Find the `categories = { ... }` section.

Important settings:

- `research_apps`
- `distraction_keywords`
- `research_keywords`

Also check:

- `browser.allowed_domains`
- `browser.blocked_domains`
- `thresholds.off_task_lockout_confidence`

## How To Install It

Make sure these files exist:

- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/modules/activity_classifier.lua`
- `~/.hammerspoon/config/default.lua`

## How To Activate It

This module becomes active automatically when Hammerspoon reloads the project.

In practice, you activate it by filling in good keyword lists.

## How To Set It Up

### Research Apps

Put apps here that are often used for real work.

Examples:

- Preview
- Zotero
- Visual Studio Code

### Research Keywords

Put words here that often appear in serious work.

Examples:

- `paper`
- `analysis`
- `experiment`
- `dissertation`

### Distraction Keywords

Put words here that often appear in drifting behavior.

Examples:

- `shopping`
- `sports`
- `celebrity`
- `gaming`

## How To Make It Less Aggressive

If it is being too strict:

- remove broad distraction words
- add more real research keywords
- raise `off_task_lockout_confidence`

## How To Test It

1. Open something clearly research-related
2. Check whether the system behaves calmly
3. Open something clearly distracting
4. Check whether the system reacts more strongly

## Best Advice For Non-Programmers

Treat this module like a word list system, not like artificial intelligence magic.

If it makes a bad decision, the fix is usually simple:

- add better keywords
- remove bad keywords
- improve your allowed and blocked domain lists
