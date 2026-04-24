# Workflow Examples

These examples describe the project in terms of `ALLOW` and `BLOCK` mode.

## Example 1: Home During Writing Hours

You are outside the approved GPS radius and inside your scheduled research hours.

Result:

- mode becomes `ALLOW`
- enforcement is relaxed
- activity continues to be logged

Typical flow:

1. `location_mode.lua` reports outside geofence.
2. `schedule.lua` may still report active work time.
3. `init.lua` keeps the session non-strict because location is relaxed.
4. Blocking modules stay idle.

## Example 2: Lab During Research Hours

You are inside the approved GPS radius and inside scheduled research hours.

Result:

- mode becomes `BLOCK`
- strict enforcement is active
- logging continues
- blocked apps and browser rules can intervene

Typical flow:

1. `location_mode.lua` reports inside geofence.
2. `schedule.lua` reports active work time.
3. `init.lua` treats the session as strict.
4. Blocking modules enforce the rules.

## Example 3: YouTube During Analysis

You are in `BLOCK` mode and switch to a distracting tab.

Result:

- `browser_filter.lua` sees a blocked domain or title term
- `overlay.lua` shows the red warning overlay
- closing the distracting tab or window clears the warning
- `logger.lua` records the violation

## Example 4: Neutral But Ambiguous Activity

You are in `BLOCK` mode, but the current app or tab is not obviously research and not obviously distracting.

Result:

- `activity_classifier.lua` may label the activity `neutral`
- the system logs it
- no strong intervention happens unless later evidence becomes clearly off-task

## Example 5: Repeated Drift

You are in `BLOCK` mode and trigger multiple violations in one session.

Result:

- violation count increases
- overlay durations can escalate
- the system becomes more disruptive until focus is restored
