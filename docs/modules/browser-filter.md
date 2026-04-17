# Browser Filter

## What This Module Does

This module looks at your front browser tab and checks:

- the website address
- the tab title

If the current page looks distracting during `BLOCK` mode, the browser can be hidden and the blocker can respond.

This module is useful because browsers can be both:

- productive
- distracting

So instead of blocking the whole browser, it looks at what you are actually viewing.

## File Used By This Module

- `~/.hammerspoon/modules/browser_filter.lua`

## Settings You Need To Edit

Open:

- `~/.hammerspoon/config/default.lua`

Find the `browser = { ... }` section.

Important settings:

- `supported_apps`
- `allowed_domains`
- `blocked_domains`
- `blocked_title_terms`

## How To Install It

Make sure these files exist:

- `~/.hammerspoon/init.lua`
- `~/.hammerspoon/modules/browser_filter.lua`
- `~/.hammerspoon/config/default.lua`

## How To Activate It

This module becomes active automatically when:

1. the module file exists
2. Hammerspoon reloads
3. you are using a supported browser
4. the system is in `BLOCK` mode

You usually activate it by filling in the browser lists in `default.lua`.

## How To Set It Up

### Allowed Domains

These are websites you want treated as research-safe.

Examples:

- `arxiv.org`
- `scholar.google.com`
- `overleaf.com`

### Blocked Domains

These are websites you want treated as distractions.

Examples:

- `youtube.com`
- `reddit.com`
- `instagram.com`

### Blocked Title Terms

These are words that may appear in a tab title even on a mixed website.

Examples:

- `sports`
- `shopping`
- `entertainment`

## How To Turn It Off

The easiest layman-friendly ways are:

- keep `blocked_domains` empty
- keep `blocked_title_terms` empty

If nothing is listed, this module has nothing to block.

## How To Test It

1. Make sure you are in `BLOCK` mode
2. Open a supported browser
3. Visit a blocked site such as YouTube
4. Bring the tab to the front
5. See whether the browser is hidden and enforcement happens

## If It Does Not Work

Check:

- Hammerspoon has Automation permission
- your browser is listed in `supported_apps`
- the domain is spelled correctly

## Best Advice For Non-Programmers

Start with only a few blocked sites and a few allowed research sites.

Too many rules at once can make the system harder to understand.
