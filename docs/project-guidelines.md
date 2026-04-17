# Project Guidelines

This document explains how to maintain the project without losing the simplicity of the `ALLOW` / `BLOCK` model.

## Primary Rule

Do not let the architecture drift away from this rule:

- GPS determines `ALLOW` or `BLOCK`
- schedule decides whether enforcement matters right now
- enforcement modules respond to that mode

If a future feature does not fit that model, it should be questioned before being added.

## Preferred Change Order

When behavior needs tuning, change things in this order:

1. `config/default.lua`
2. keyword/domain lists
3. timing thresholds
4. module logic
5. architecture

This keeps the system understandable and easier to debug.

## App Blocking Guidelines

- block only apps that are reliably off-task during research time
- avoid blocking tools that can be both productive and distracting unless you also have context-aware logic
- prefer browser/domain filtering for mixed-use tools

## Browser Filtering Guidelines

- keep `allowed_domains` small and justified
- use `blocked_domains` for repeat offenders
- use title keywords to catch distracting pages that slip past URL rules
- test browser automation after every major browser update

## GPS Guidelines

- treat geofence coordinates as part of the product, not random numbers
- document what location they refer to
- use a radius large enough to be robust against normal GPS drift
- validate transitions while clearly inside and clearly outside the target area

## Logging Guidelines

- logs should help answer why the system enforced
- marker logs should stay human-readable
- activity logs should stay machine-friendly
- avoid logging more personal data than the enforcement system actually needs

## Documentation Guidelines

- describe behavior in terms of `ALLOW` and `BLOCK`
- keep setup steps reproducible
- update docs whenever config keys or module responsibilities change

## Extension Ideas That Fit Well

- richer menubar status
- better allowed-domain matching
- per-mode overlay styles
- smarter activity classification based on recent history

## Extension Ideas That Need Care

- OCR or screenshot-based monitoring
- terminal command filtering
- repo-specific coding restrictions
- aggressive process killing across many apps

These can be useful, but they also add complexity fast. The project works best when the location-driven model stays obvious.
