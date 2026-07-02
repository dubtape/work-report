---
name: work-report
description: Generic web work-report automation using OpenCLI, short eval calls, configurable lookup fields, and model synchronization.
---

# Work Report Automation

This skill automates adding work-report records in a browser-based enterprise
system. It is intentionally generic: all organization-specific URLs, project
names, employee names, internal IDs, DOM IDs, and lookup values must live in a
local private config file.

## What This Skill Does

- Opens or reuses the work-report page in the browser connected to OpenCLI.
- Checks whether a target date already exists before creating a duplicate.
- Clicks the configured "New" button.
- Fills date, hours, and content.
- Fills configured lookup fields.
- Synchronizes both visible UI controls and the underlying page model.
- Saves and verifies that the list contains the new record.

## Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Public usage notes and fallback procedure. |
| `report-config.example.json` | Template config with placeholder values only. Copy to `report-config.local.json`. |
| `fast_work_report.ps1` | Main fast runner. Reads private config and syncs UI plus model fields. |
| `fast_work_report.js` | Node wrapper that calls the PowerShell runner. |
| `gs_report_tiny.js` | Minimal browser-side helper for single-page experiments. |
| `.gitignore` | Keeps private config files out of source control. |

## Private Configuration

Before using this skill, copy the example config:

```powershell
Copy-Item .\report-config.example.json .\report-config.local.json
```

Then edit `report-config.local.json` with values from your own system.

Never commit `report-config.local.json`. It may contain internal URLs, project
codes, employee names, customer names, DOM IDs, and system GUIDs.

## Fast Path

Daily use should call the fast runner:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\fast_work_report.ps1 -Date 2026-07-04 -Content "Your work content"
```

The runner updates two layers:

- Visible controls such as `lookupbox`, date boxes, number boxes, and text areas.
- The underlying page model, usually a Knockout-style `currentItem`.

This second layer is important. Many enterprise pages validate the data model,
not only the visible input controls. If a visible lookup field shows a value but
the model field remains empty, save validation can still fail.

## Required Config Sections

`report-config.local.json` contains these main sections:

- `targetUrl`: The work-report page URL.
- `opencliSession`: OpenCLI browser session name, usually `tape`.
- `frameIds`: Parent page iframe IDs.
- `selectors`: DOM IDs and selectors used by the page.
- `defaults`: Default hours and content.
- `lookups`: Display and value pairs for lookup fields.
- `model`: Underlying model field/value pairs needed before save.
- `verification`: Text or fields used to verify save success.

## Fallback Procedure

If the fast runner fails, use short `opencli browser <session> eval` calls
instead of one large script. Large eval payloads are fragile on Windows and can
break when they contain non-ASCII content or shell-sensitive characters.

The fallback sequence is:

1. Bind the OpenCLI browser session.
2. Open the work-report page.
3. Open the work-report tab or iframe.
4. Check whether the target date already exists.
5. Click the configured "New" button.
6. Fill lookup fields using the page's own lookup controls.
7. Fill date, hidden date, hours, and content.
8. Blur and validate fields.
9. Save and close.
10. Reopen or refresh the list and verify the new row.

## Notes For Maintainers

- Prefer config-driven selectors and model values over hard-coded values.
- Keep all real company/customer/project/person data out of this repository.
- Keep comments in scripts focused on page mechanics, not private business data.
- If a field appears filled but save fails, inspect the underlying model field.
- If direct `lookupbox('setValue')` is not enough, synchronize the model field
  that the save action validates.
