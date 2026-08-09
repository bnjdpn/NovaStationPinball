# Task 8 — Review package

Review the current implementation against `.superpowers/sdd/task-8-brief.md`, `.superpowers/sdd/task-8-imagegen-inputs.md`, and `.superpowers/sdd/task-8-report.md`.

## Files in scope

- `Art/ImageGen/*.png`
- `Art/imagegen-provenance.json`
- `Art/QA/table-guide-overlay.png`
- `Art/QA/runtime-iphone-raster.png`
- `scripts/build_imagegen_assets.rb`
- `scripts/verify_imagegen_assets.rb`
- `scripts/verify_imagegen_assets_test.rb`
- `NovaStationPinball/Resources/Assets.xcassets/AppIcon.appiconset/*`
- `NovaStationPinball/Resources/Art/*.png`
- `NovaStationPinball/Game/PinballScene.swift`
- `NovaStationPinball/App/RootView.swift`
- `NovaStationPinballUITests/LayoutUITests.swift`
- `project.yml`

## Required review focus

- Every identity-bearing asset must be an ImageGen PNG master or a deterministic crop/resize/chroma/defringe derivative. Reject fabricated developer art, SVG, PDF or CSS illustration.
- Verify manifest prompts, timestamps, exact SHA-256, native dimensions, roles, references/edit parents, inspection state, and byte-preservation of masters.
- Verify reproducible derivatives, sRGB/alpha/AppIcon contract, path confinement, deterministic hashes, and negative tests.
- Inspect every master at original detail, the black/white edge composite if still present, the mechanical overlay, and `Art/QA/runtime-iphone-raster.png`.
- Reject perspective/text/logo/copyright identity/mechanical/crop issues.
- Confirm the static background has no flippers/plunger and runtime does not double static mechanisms.
- Confirm visible runtime uses raster SpriteKit nodes only; invisible accessibility/layout rectangles are acceptable but must not claim greybox.
- Confirm dynamic flipper/plunger/ball positions use the same normalized constants as simulation definitions.
- Verify the root receipt `/private/tmp/apps-factory/NovaStationPinball/task8-root-runtime-fix-20260722/xcresult/task8-root-runtime-fix.xcresult`: 20 unit + 2 UI pass, and the failed predecessor is accurately documented.
- Confirm owned root UDID `C3B0C31A-F6C0-4AA1-B72F-FB4CE91F56E1` is absent without touching other devices.

Return findings ordered by severity with file/line references. If no finding remains, return `Approved` with the evidence checked. Do not modify files.
