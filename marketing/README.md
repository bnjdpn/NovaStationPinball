# Nova Station Pinball marketing site

The committed GitHub Pages site is generated from the current public product copy,
`marketing/site.json`, the real app icon/screenshots, the app-specific
`marketing/site.html.erb`, and its sober layout CSS. The stable design contract,
asset provenance, ImageGen prompt record, and anti-cliche rules live in
`site/DIRECTION.md`; review them before changing the page.

Run `rtk proxy /opt/homebrew/opt/ruby/bin/ruby scripts/marketing_site.rb` after an
approved public metadata, localization, icon, screenshot, or product-positioning
change. Run the same command with `--check` in `release_contract`.

Do not publish candidate-only features before the matching storefront version is
visible. After Apple propagation, update `public_version` and the screenshot URLs,
regenerate, visually review desktop/mobile and every locale, then commit the site
with the app release. Keep support on Formspree; never add public email, analytics,
tracking, stock imagery, or cross-app data claims.

Files under `marketing/app-store-badges/` are unmodified official artwork fetched
from Apple Marketing Tools. Keep the localized badge at least 40 px high, preserve
its clear space, and never recolor, crop, tilt, animate, redraw, or replace it with
a homemade App Store badge.
