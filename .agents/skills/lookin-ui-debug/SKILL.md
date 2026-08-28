---
name: lookin-ui-debug
description: Inspect, diagnose, or reproduce an iOS UI currently connected to the Lookin macOS app using synchronized screenshots and structured hierarchy data. Use for AI-assisted iOS UI debugging, visual comparison, layout investigation, or implementation from a live reference; do not use when no Lookin session or exported capture is available.
---

# Lookin UI Debug

Use Lookin as the source of truth for the currently inspected iOS UI. Keep visual evidence and hierarchy evidence from the same capture.

## Choose A Mode

- For a layout or visibility bug, query the smallest relevant subtree, inspect candidate elements, then compare their absolute frames and constraints.
- For UI reproduction, create a capture bundle before implementation. Use the screenshot for appearance and the JSON for exact geometry, text, colors, typography, identifiers, and hierarchy.
- For an existing capture bundle, work from `manifest.json`, `context.json`, `element.json`, and `screenshot.png` without requiring a live Lookin session.

## Connect

Prefer the Lookin MCP tools when they are available. Otherwise run the repository CLI from the Lookin checkout:

```bash
./bin/lookin doctor
```

If it cannot connect, ask the user to open Lookin, inspect the target app, and enable **AI Integration** in Settings. Do not guess UI state from an unavailable or stale session.

## Capture For Reproduction

Write capture artifacts into a task-specific directory inside the user's workspace:

```bash
./bin/lookin capture --output <capture-directory>
```

Use `--element-id <oid>` for a component-level reproduction. The command refreshes once before collecting data; keep that default unless the user needs to preserve a transient state.

Inspect `screenshot.png` visually and parse the JSON as structured data. Treat these fields as complementary:

- Screenshot: rendered appearance, composition, clipping, imagery, and perceived spacing.
- Hierarchy frames: exact position, size, nesting, and overlap.
- Element attributes: text, colors, fonts, corner radii, borders, and effective constraints.

When screenshot pixels and exported properties disagree, report the discrepancy and prefer the screenshot for rendered appearance. Do not invent assets, hidden states, interactions, or off-screen content that the capture does not establish.

## Debug A Focused Issue

Use the narrowest query that can answer the question:

```bash
./bin/lookin search "<text-or-class>" --type all
./bin/lookin inspect <element-id>
./bin/lookin relative <first-element-id> <second-element-id>
./bin/lookin hierarchy --element-id <element-id> --max-depth 3
```

Reload once before validating a claimed fix. Re-query only the affected subtree or elements so the comparison remains readable.

## Reproduce And Verify

1. Record the target viewport or root frame from the capture.
2. Implement structure and layout before fine visual styling.
3. Apply typography, color, borders, radii, shadows, and image treatment from the captured evidence.
4. Run the target and compare it at the same viewport and UI state.
5. Correct the largest visual differences first, then validate text wrapping, clipping, and small spacing.

Keep generated captures out of source control unless the user explicitly wants fixtures or documentation artifacts.
