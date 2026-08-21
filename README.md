# Nova Station Pinball

Nova Station Pinball is an original landscape pinball game for iPhone and
iPad. Its single complete table combines 17 missions, score chasing and a
science-fiction workshop atmosphere while remaining fully playable offline.

- Deterministic pinball simulation and validated table geometry
- 17 table missions and local progression
- Offline scores with optional Game Center leaderboards
- ImageGen-derived visual assets and runtime effects
- One-time Workshop unlock; no subscription, ads or tracking

## Technology and development

Swift 6, SwiftUI, SpriteKit and GameKit for iOS 17+. The deterministic engine
is a Swift package; `project.yml` owns the Xcode project.

```sh
bundle install
swift test
xcodegen generate
xcodebuild -scheme NovaStationPinball -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
ruby scripts/release_contract_test.rb
ruby scripts/verify_imagegen_assets.rb
```

[Product site](https://bnjdpn.github.io/NovaStationPinball/) · [Privacy](https://bnjdpn.github.io/NovaStationPinball/privacy.html)
