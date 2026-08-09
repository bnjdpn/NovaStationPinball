# Task 7 — Review package

Review the Task 7 implementation against `.superpowers/sdd/task-7-brief.md` and the evidence in `.superpowers/sdd/task-7-report.md`.

## Files in scope

- `NovaStationPinball/App/NovaStationPinballApp.swift`
- `NovaStationPinball/App/AppModel.swift`
- `NovaStationPinball/App/RootView.swift`
- `NovaStationPinball/Game/PinballScene.swift`
- `NovaStationPinball/Game/SimulationDriver.swift`
- `NovaStationPinball/Game/TouchInterpreter.swift`
- `NovaStationPinball/Resources/Art/greybox-table-guide.png`
- `NovaStationPinballTests/SimulationDriverTests.swift`
- `NovaStationPinballTests/TouchInterpreterTests.swift`
- `NovaStationPinballUITests/LayoutUITests.swift`
- `scripts/export_greybox_guide.swift`
- `project.yml`

## Evidence to verify

- RED and GREEN receipts listed in the report.
- Generic simulator build succeeded.
- Final iPhone and iPad XCTest receipts pass.
- Final live captures exist and show the complete 4:3 frame without crop.
- The guide is a real reproducible 2048x1536 PNG.
- Both owned simulator UDIDs were deleted and absence was checked.

## Review focus

- Touch identity, coordinate orientation, invisible lower left/right zones, plunger swipe/release, short upper horizontal nudge, and multi-touch cancellation.
- Fixed 240 Hz accumulation, bounded catch-up, dropped-time accounting, and determinism.
- `AppModel` ownership/thread isolation and SpriteKit update-loop integration.
- Exact 4:3 letterbox and 70/30 table-console composition on iPhone and iPad without crop.
- No SVG, PDF, CSS illustration, or unmarked developer-drawn final art. Every visible procedural primitive must be explicitly greybox-only.
- Tests must assert behavior rather than merely existence.

Return findings ordered by severity with file and line references. If none, return `Approved` and state the evidence checked.
