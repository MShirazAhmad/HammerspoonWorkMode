# Messages

## What This Module Does

This module provides a single editable store for every string shown to the user: overlay titles, button labels, terminal prompt text, shell messages, and alert text.

All strings live in `config/messages.yaml` rather than being hardcoded across modules. This means you can rephrase, translate, or adjust any user-facing text without touching Lua code.

## Files Used By This Module

- `~/.hammerspoon/modules/messages.lua` — Lua loader and fallback defaults
- `~/.hammerspoon/config/messages.yaml` — Your editable text overrides

## How It Works

At startup `Messages.new()` loads all built-in defaults first, then overlays any matching keys from `messages.yaml`. If the YAML file is missing or cannot be parsed, the system falls back to the built-in defaults and continues running.

The key format is dot-separated and mirrors the YAML hierarchy:

```
terminal_guard.prompt.title  →  terminal_guard: { prompt: { title: "..." } }
```

The same key format is also used by `terminal-command-guard.zsh`, so shell-side messages stay in sync with the Hammerspoon side when you edit `messages.yaml`.

## Editing Messages

Open `~/.hammerspoon/config/messages.yaml`.

The default file looks like this:

```yaml
overlay:
  title: "RESEARCH MODE"
  subtitle: "Return to writing, reading, coding, or analysis."
  remaining_prefix: "Remaining: "
  fallback_message: "Return to research work."
  fallback_reason: "Off-task behavior detected."

terminal_guard:
  prompt:
    title: "TERMINAL CHECK"
    question: "Is this Terminal command related to your research work?"
    instructions: "Press Y to allow Terminal for 30 minutes.\nPress N to block Terminal commands for 30 minutes."
  alert:
    allow: "Terminal allowed for 30 minutes"
    block: "Terminal blocked for 30 minutes"

shell:
  decision_expired: "Decision window expired. Please answer the BLOCK mode prompt."
  command_blocked:
    title: "Command blocked"
    detail: "{detail} (remaining: {remaining})"
```

Use `\n` inside a value when you want a line break on a Hammerspoon screen.

After editing, reload Hammerspoon to apply changes.

## YAML Limitations

The built-in YAML reader supports only the subset used by this project:

- Nested scalar mappings (`key: value`)
- Inline comments (`# text`)
- Single- and double-quoted string values
- `\n` escape sequences inside values

It does **not** support lists, multi-line blocks, anchors, or other YAML features. Use simple key: value pairs only.

## Available Keys

| Key | Default | Used by |
|---|---|---|
| `overlay.title` | `RESEARCH MODE` | Red warning overlay |
| `overlay.subtitle` | `Return to writing…` | Red warning overlay |
| `overlay.remaining_prefix` | `Remaining: ` | Overlay countdown |
| `overlay.idle` | `Idle` | Overlay status |
| `overlay.active_countdown_prefix` | `Active countdown: ` | Overlay status |
| `overlay.fallback_message` | `Return to research work.` | Overlay when no specific reason |
| `overlay.fallback_reason` | `Off-task behavior detected.` | Overlay when no specific reason |
| `overlay.block_suffix` | `BLOCK` | Menu bar badge |
| `terminal_guard.prompt.title` | `TERMINAL CHECK` | Terminal Y/N screen |
| `terminal_guard.prompt.question` | `Is this Terminal command…` | Terminal Y/N screen |
| `terminal_guard.prompt.instructions` | `Press Y to allow…` | Terminal Y/N screen |
| `terminal_guard.prompt.waiting` | `Waiting for Y or N` | Terminal Y/N screen |
| `terminal_guard.state_reason.allow` | `Terminal allowed for research work.` | State file written on Y |
| `terminal_guard.state_reason.block` | `Terminal blocked…` | State file written on N |
| `terminal_guard.alert.allow` | `Terminal allowed for 30 minutes` | Hammerspoon alert on Y |
| `terminal_guard.alert.block` | `Terminal blocked for 30 minutes` | Hammerspoon alert on N |
| `shell.awaiting_confirmation` | `Awaiting BLOCK mode terminal confirmation.` | Shell prompt |
| `shell.blocked_default` | `Blocked by BLOCK mode terminal check` | Shell block message |
| `shell.decision_required` | `Decision required…` | Shell when no state file |
| `shell.decision_expired` | `Decision window expired…` | Shell when state is stale |
| `shell.command_blocked.title` | `Command blocked` | Shell blocked command |
| `shell.command_blocked.detail` | `{detail} (remaining: {remaining})` | Shell blocked command |
| `shell.allowed_status` | `Terminal allowed by Y selection…` | Shell allowed command |

## Troubleshooting

**Changes to messages.yaml are not showing up**

Reload Hammerspoon after editing the file.

**The Y/N prompt shows wrong text**

Check that the YAML file at `user.messages_path` (default `~/.hammerspoon/config/messages.yaml`) exists and has valid syntax. The module logs a warning if the file cannot be parsed.
