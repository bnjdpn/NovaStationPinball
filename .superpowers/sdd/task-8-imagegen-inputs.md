# Task 8 — ImageGen source record

All seven production/provenance files below were produced by the ImageGen tool in this task and copied byte-for-byte into `Art/ImageGen/`. The original generated files remain under `/Users/benjamin/.codex/generated_images/019f8653-c857-7fe2-80d6-7dbb4e0dbf66/`.

## table-master.png

- Generated source: `exec-6693ebac-590c-494d-a800-bcf01fda5af3.png`
- Mode: generation
- Reference: `NovaStationPinball/Resources/Art/greybox-table-guide.png`
- Native: 1448x1086, opaque, no embedded ICC profile
- Timestamp: `2026-07-22T03:07:23+0200`
- SHA-256: `e89bcdfba569e70fd02130203e942ddc40cea6fa79f11ccc53ef484ea20b2e84`
- Roles: table, CRT console, panels, ramps, portal, lamps, targets, bumpers, flippers, plunger, HUD/menu surfaces
- Prompt: `Create the FINAL original raster master artwork for an iOS landscape pinball game called Nova Station Pinball. Use the attached greybox PNG as a strict composition and mechanical-placement reference: exact 4:3 canvas, the pinball playfield occupies the left 70 percent and a separate vertical CRT control console occupies the right 30 percent. Orthographic near-top-down game-ready view, absolutely no perspective distortion and no cropping. Preserve the safe-zone frame and the approximate positions of the four upper target lanes, three central bumpers, two lower flippers, and right-side plunger lane. Add original pinball mechanisms that fit the empty space: two luminous ramps, one orbital portal, rails, rollover lamps, target inserts, ball guides, and a drain, while keeping the main placements mechanically readable. Art direction: original retro-futurist deep-space research station, tactile late-1990s arcade pinball cabinet, dark graphite metal, oxidized brass, midnight teal, electric cyan, warm amber, subtle magenta nebula accents, believable brushed metal, molded plastic, enamel inserts, restrained wear, high contrast, premium painted raster art. The console should look like an integrated smoked-glass CRT hardware panel with bezel and blank screen regions for runtime HUD overlay. No text, no letters, no numbers, no logos, no Windows branding, no Space Cadet symbols, no copyrighted characters, no UI labels, no watermark. Do not render guide annotations or greybox outlines. The result must look like a cohesive production pinball table texture and cabinet art, with clean readable components suitable for cropping into runtime PNG sprites.`

## components-checker-master.png

- Generated source: `exec-bb3f04d4-18b2-49e9-9815-aeb327f4b8be.png`
- Mode: generation
- Reference: `table-master.png`
- Native: 1536x1024, opaque, no embedded ICC profile; ImageGen rendered a checker pattern rather than real alpha, so this is retained only as provenance and is never a runtime source.
- Timestamp: `2026-07-22T03:09:03+0200`
- SHA-256: `b9315c14dea3e8aa4726bc5966e1c233676a66d600007c23e301206d751b0ce9`
- Roles: provenance parent for the edited chroma atlas
- Prompt: `Using the attached Nova Station Pinball table master only as the visual style reference, create a clean production sprite atlas of ORIGINAL pinball parts for the same game. Exact orthographic top-down orientation, no perspective, consistent dark graphite metal + oxidized brass + electric cyan + warm amber + subtle magenta nebula enamel. Arrange isolated objects in a strict spacious grid with no overlap and generous empty gutters: two separate mirrored pinball flippers in neutral horizontal poses; three identical circular bumper caps; four identical rectangular drop targets; one slender plunger rod and knob; one polished steel pinball; two curved translucent cyan ramp/rail modules; one circular orbital portal ring; six small round insert lamps shown lit and unlit; one CRT smoked-glass bezel; two blank instrument panels; one blank menu frame; one blank HUD frame; several small hardware buttons. Make every object fully visible and easy to crop. Prefer true transparent background with clean alpha; if transparency is unavailable, use a perfectly uniform pure chroma green #00FF00 background with no green reflections on objects. No cast shadows outside each object, no text, no letters, no numbers, no logos, no labels, no watermark, no Windows or Space Cadet imagery. This is a raster game sprite atlas, not a concept-art scene.`

## table-background-master.png

- Generated source: `exec-afac4a31-addc-4c7a-977e-4de55038f7bb.png`
- Mode: ImageGen edit
- Parent: `table-master.png`
- Native: 1448x1086, opaque, no embedded ICC profile
- Timestamp: `2026-07-22T03:25:58+0200`
- SHA-256: `c3f20bdd842e2e8090fd4b1d5041e16c67ace2ce57d7de13849aae1a5f1467ab`
- Roles: static runtime table/console background with dynamic flipper and plunger silhouettes removed
- Prompt: `Edit this exact Nova Station Pinball 4:3 table master for use as the STATIC runtime background. Preserve the entire image pixel composition, 70/30 playfield-console split, camera, crop, colors, lighting, CRT console, ramps, portal, bumpers, targets, rails, lamps, drain, cabinet borders, and all other mechanisms. Remove ONLY the two large silver-and-amber lower flipper paddles and the visible vertical plunger rod/knob in the far-right launch lane. Keep their pivot hubs, mounting plates, lane, and surrounding hardware, but fill the removed paddle/rod silhouettes naturally with the matching dark graphite, brass, teal-enamel playfield surface and underlying mechanical detail. There must be no pinball ball and no movable paddle or plunger rod left in the background. Do not add, shift, resize, rotate, or redesign anything else. No text, letters, numbers, logos, labels, watermark, Windows or Space Cadet imagery. Exact orthographic top-down raster game background, same aspect ratio and boundaries.`

## components-master.png

- Generated source: `exec-65a383e3-0cf7-4df0-8b5d-6c4cae4c0d48.png`
- Mode: ImageGen edit
- Parent: `components-checker-master.png`
- Native: 1536x1024, opaque, no embedded ICC profile, pure-green background intended for deterministic alpha extraction
- Timestamp: `2026-07-22T03:10:24+0200`
- SHA-256: `c9fbb24aec78541f6f0f4a433079798c2c57d9083b6091ff957c1ee091022d13`
- Roles: flippers, bumpers, targets, plunger, ball, ramps, portal, lamps, CRT, panels, menu, HUD, hardware buttons
- Prompt: `Edit this exact Nova Station Pinball sprite atlas. Preserve every object, its position, scale, lighting, materials, colors, orthographic orientation, and generous spacing. Change ONLY the entire checkerboard/background into a perfectly uniform flat pure chroma green RGB #00FF00, edge to edge, with no checkerboard, no texture, no gradient, no shadows, no green spill or reflections on objects. Keep all objects fully visible. Add nothing. Remove nothing. No text, logos, labels, or watermark. The purpose is deterministic chroma-key alpha extraction for raster game sprites.`

## app-icon-master.png

- Generated source: `exec-1877dbbd-6193-46d6-af1c-13e3b8ca5d84.png`
- Mode: generation
- Reference: `table-master.png`
- Native: 1254x1254, opaque, no embedded ICC profile
- Timestamp: `2026-07-22T03:11:57+0200`
- SHA-256: `e469bdc5f0e4b964ee66111de52788dde81be1b17600b5476fcf14236262618a`
- Roles: AppIcon and small brand mark derivatives
- Prompt: `Create a premium ORIGINAL 1024x1024 app icon master for Nova Station Pinball, visually derived from the attached table artwork. A single polished steel pinball is suspended directly above a luminous cyan orbital portal set into a dark graphite and oxidized-brass space-station mechanism, with two subtle warm-amber flipper silhouettes forming a dynamic V beneath it. Strong centered silhouette, near-orthographic symmetry, tactile late-1990s arcade hardware, deep midnight-teal space backdrop, tiny restrained magenta nebula glow, bright cyan/amber rim lighting, high contrast readable at 64px, rich raster texture but uncluttered. Fill the entire square canvas; do not draw a rounded-square mask or transparent corners because iOS applies its own mask. No text, letters, numbers, logos, Windows branding, Space Cadet symbols, copyrighted characters, border, badge, watermark, or mockup device.`

## key-art-master.png

- Generated source: `exec-5cce2cbc-7aa3-4c22-ae36-29dbfa818336.png`
- Mode: generation
- Reference: `table-master.png`
- Native: 1536x1024, opaque, no embedded ICC profile
- Timestamp: `2026-07-22T03:13:19+0200`
- SHA-256: `9a02f1402be765efd76e96f3e78d436fccde86fddc706bec97f9ef28e836f3f0`
- Roles: title background and key-art derivatives
- Prompt: `Create ORIGINAL cinematic key art for Nova Station Pinball in a wide landscape composition suitable for an iOS game title screen and marketing crop. Use the attached table master as the exact art-direction reference. Show the complete Nova Station pinball table installed inside a vast dark orbital research-station arcade bay, seen from a dramatic but mechanically believable three-quarter overhead angle. A polished steel pinball arcs above the luminous cyan orbital portal while amber flippers and insert lamps glow; subtle magenta nebula light enters through a distant window. Materials: dark graphite, oxidized brass, smoked glass, cyan energy rails, warm amber hardware, premium tactile late-1990s arcade realism. Strong focal center, clear dark negative space across the upper-left and upper-center for title text to be overlaid later by native UI, and crop-safe edges for 16:9 and 4:3 derivatives. No text, no letters, no numbers, no logos, no Windows branding, no Space Cadet imagery, no characters, no watermark, no phone mockup, no UI labels.`

## store-creatives-master.png

- Generated source: `exec-89dd546e-a043-4960-bf3d-d1c8d52c13d8.png`
- Mode: generation
- References: `table-master.png`, `key-art-master.png`
- Native: 1774x887, opaque, no embedded ICC profile
- Timestamp: `2026-07-22T03:14:33+0200`
- SHA-256: `e71ea02fdbbe695a6a61976bf322e5f395ab5d2ada9d2c2ba3ee77ed956cfdf3`
- Roles: App Store promotional backgrounds and screenshot creative crops
- Prompt: `Create an ORIGINAL App Store promotional creative master for Nova Station Pinball, consistent with both attached ImageGen masters. Wide landscape marketing composition designed to yield three crop-safe screenshot backgrounds: left zone highlights the cyan orbital ramp and portal, center zone highlights the polished ball and amber flippers, right zone highlights the smoked-glass CRT console and brass instrument hardware. Unify all three zones as one continuous premium orbital-station pinball cabinet scene, not a collage, with clear dark areas where native localized captions can later be overlaid. Dark graphite and oxidized brass, midnight teal, electric cyan, warm amber, restrained magenta nebula, tactile late-1990s arcade realism, strong high-contrast raster detail. Keep mechanisms believable and coherent with the table master. No text, letters, numbers, logos, branding, Space Cadet or Windows imagery, characters, UI labels, screenshot frames, devices, watermark, or borders.`

## Root visual inspection

All seven masters/provenance images were inspected at original detail after copying. Accepted: no text/logos/watermarks; no Windows/Space Cadet identity; coherent graphite/brass/cyan/amber/magenta palette; the table master is orthographic and exact 4:3 with the required 70/30 split and mechanically readable flippers, targets, bumpers, ramps, portal and plunger; the edited table background cleanly removes only the three moving sprites so they cannot double during animation; component objects are fully visible and crop-separated; key art and Store art contain safe dark overlay regions. The checker master is provenance-only because its background is baked rather than alpha. The chroma edit is the sole component extraction source.
