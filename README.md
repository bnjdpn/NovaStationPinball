# Nova Station Pinball

An original, offline pinball game for iPhone and iPad. Nova Station Pinball is
landscape-only and targets iOS 17 or later with Swift 6.

The repository starts with its XcodeGen, Swift Package, release, privacy, and
support contracts. Gameplay and visual assets are added in later lots.

## Simulation initialization

`PinballSimulation()` is nonthrowing and always starts from the built-in,
validated standard table. Initializing with a custom `TableDefinition`, or
restoring a custom `SimulationSnapshot`, validates all supplied geometry and
state and therefore uses a throwing initializer. Legacy v1 table JSON that only
contains `version`, `playfieldSize`, and `gravity` remains supported with the
standard mechanism and tuning defaults.

## Local checks

```sh
rtk proxy ruby scripts/release_contract_test.rb
rtk proxy xcodegen generate
```

Support is available through the [Nova Station Pinball support form](https://bnjdpn.github.io/NovaStationPinball/#contact).
