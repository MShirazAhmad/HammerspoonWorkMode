# Contributing

This page explains how to build the documentation locally, add new pages, and keep the doc style consistent.

For guidelines on maintaining and extending the Lua code, read [Project Guidelines](project-guidelines.md).

---

## Building the Docs Locally

### Prerequisites

- Python 3.9 or later
- pip

### Install the documentation dependencies

```bash
pip install -r docs/requirements.txt
```

### Preview the site

```bash
mkdocs serve
```

Open your browser at `http://127.0.0.1:8000`. Changes to any Markdown file in `docs/` are picked up automatically.

### Build a static copy

```bash
mkdocs build
```

The output goes into `site/`. The `site/` directory is ignored by git.

---

## Adding a New Page

1. Create a new Markdown file in the appropriate folder:
   - User-facing guides belong in `docs/`
   - Module-specific guides belong in `docs/modules/`
   - Contributor or developer notes belong in `docs/`

2. Add the page to the `nav:` block in `mkdocs.yml`:

   ```yaml
   nav:
     - Setup:
         - My New Guide: my-new-guide.md
   ```

3. Run `mkdocs serve` and verify the page renders and appears in the nav.

---

## Documentation Style

The existing docs are written in a plain, direct style aimed at non-programmers as well as developers. Please match that style when adding or editing pages.

- Write in short sentences.
- Prefer imperative mood for steps: "Open the file", "Set the value", "Reload Hammerspoon".
- Use code blocks for any config values, file paths, or commands.
- Use `BLOCK` and `ALLOW` in backticks when referring to the two modes.
- Keep `~/.hammerspoon/...` paths as instructional content — they tell the user where to look on their real Mac.
- Reference other pages using relative Markdown links, for example `[Troubleshooting](troubleshooting.md)`.

---

## Adding a New Module Doc

If you add a new Lua module to `modules/`, follow this template:

```markdown
# Module Name

## What This Module Does

One or two sentences. What problem does it solve? When is it active?

## Files Used By This Module

- `~/.hammerspoon/modules/module_name.lua`

## Settings You Need To Edit

Which keys in `config/default.lua` affect this module?

## How It Works

Brief explanation of the internal flow.

## Configuration

Code example showing the relevant config block.

## Troubleshooting

Common problems and what to check.
```

Then add the new file to `mkdocs.yml` under the `Module Guides` section.

Also update `docs/modules/README.md` to include the new module in the ordered list.

---

## Read the Docs

The site is hosted on Read the Docs. The build is configured in `.readthedocs.yaml` at the root of the repository. It uses MkDocs with the Material theme.

Pushes to the default branch trigger an automatic rebuild. You can view the build status on the [Read the Docs project dashboard](https://readthedocs.org/projects/hammerspoonworkmode/).
