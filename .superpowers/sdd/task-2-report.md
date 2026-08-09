# Task 2 report — deterministic simulation foundation

Status: `DONE`

## Scope delivered

- Added pixel-independent `Vector2` geometry and versioned logical table data.
- Added public value models for balls, player input, events, frames, and snapshots.
- Added a mutable, `Sendable` `PinballSimulation` with an exact fixed time step of
  `1.0 / 240.0` seconds.
- Added the minimum deterministic integration: one gravity update, one
  semi-implicit position update, and one fixed elapsed-time increment per call.
- Refactored physical constants into the internal `PhysicsTuning` namespace.
- Added no collision, mechanism, scoring, mission, replay, persistence, Apple,
  rendering, or art behavior from later tasks.

## TDD evidence

All commands ran from `/Users/benjamin/Documents/Apps/NovaStationPinball` through
`rtk proxy`, with scratch isolated at
`/private/tmp/apps-factory/NovaStationPinball/task2-019f8653/swiftpm`.

### RED

Test production order: `PinballSimulationTests.swift` was created before any of
the four new production files.

Command:

```sh
rtk proxy swift test --package-path /Users/benjamin/Documents/Apps/NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task2-019f8653/swiftpm --filter PinballSimulationTests
```

Result: exit `1`, expected compile failure caused by the absent Task 2 API. The
first diagnostic was:

```text
PinballSimulationTests.swift:9:25: error: cannot find 'Vector2' in scope
```

The same run also reported the expected missing `BallState`, `PlayerInput`,
`GameEvent`, `SimulationFrame`, `SimulationSnapshot`, `TableDefinition`, and
`PinballSimulation` symbols. This was an API-absence RED, not a typo or an
environment failure.

### Initial GREEN

After adding only the minimum value models, table definition, and fixed-step
simulation, the same targeted command completed with exit `0`: 4 tests in 1
suite passed, 0 failures.

Covered behaviors:

- public API and compile-time `Sendable` constraints;
- exact `1.0 / 240.0` fixed step and versioned standard table;
- gravity applied over one tick;
- elapsed-time accumulation over two ticks;
- canonical sorted-key snapshot JSON and decoding round trip.

### Refactor GREEN

After moving `stepsPerSecond`, `fixedTimeStep`, and standard gravity into
`PhysicsTuning`, the targeted command again completed with exit `0`: 4 tests in
1 suite passed, 0 failures.

### Full suite GREEN

Command:

```sh
rtk proxy swift test --package-path /Users/benjamin/Documents/Apps/NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task2-019f8653/swiftpm
```

Result: exit `0`; 5 tests passed, 0 failures. This includes the pre-existing
bootstrap module-name test and all four Task 2 tests. The build emitted no
warnings.

## Files

Created:

- `NovaStationCore/Sources/NovaStationCore/Geometry.swift`
- `NovaStationCore/Sources/NovaStationCore/SimulationModels.swift`
- `NovaStationCore/Sources/NovaStationCore/TableDefinition.swift`
- `NovaStationCore/Sources/NovaStationCore/PinballSimulation.swift`
- `NovaStationCore/Tests/NovaStationCoreTests/PinballSimulationTests.swift`
- `.superpowers/sdd/task-2-report.md`

Preserved unchanged:

- `NovaStationCore/Sources/NovaStationCore/NovaStationCore.swift`
- `NovaStationCore/Tests/NovaStationCoreTests/NovaStationCoreTests.swift`
- all app, Xcode, Fastlane, support, release, and future-task files.

## Auto-review

- Requirements: every named Task 2 interface exists; `step(_:)` returns
  `SimulationFrame`; the fixed step is derived exactly from `1.0 / 240.0` and is
  covered by equality; table data has an explicit integer version and logical
  1-by-2 playfield units, with no pixel or display type.
- Concurrency/data: every public Task 2 type conforms to `Sendable`; persistent
  value models also conform to `Codable` and `Equatable`; the engine itself is
  not encoded because `SimulationSnapshot` is the persistence boundary.
- Portability: production sources import no framework and have no Apple API or
  Apple-platform dependency.
- Determinism: integration uses only fixed-order scalar operations over the
  stable array order. No wall clock, randomness, global mutable state, or
  variable delta is present.
- Scope: no code or asset was taken from the behavioral reference; no future
  collision/rules/replay work was started; no art was created.
- Repository safety: no commit, push, remote operation, release, or App Store
  Connect action was performed. Existing bootstrap files were not reset,
  cleaned, or rewritten.

Findings: none. Concerns: none for Task 2.

## Review fix — reject incompatible table snapshots

Status: `DONE`

### Finding verified

The original snapshot initializer accepted any `SimulationSnapshot` without
checking that `snapshot.tableVersion` matched `table.version`. That could replay
persisted coordinates and state against a different table schema. The review
finding was therefore valid and required an explicit compatibility boundary.

### Corrective RED

Only the mismatch test and the compile-time `Sendable` assertion for the wished
for public error were added before production changed.

Command:

```sh
rtk proxy swift test --package-path /Users/benjamin/Documents/Apps/NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task2-019f8653/swiftpm --filter PinballSimulationTests
```

Result: exit `1`. The expected diagnostics were:

```text
error: cannot find 'SimulationError' in scope
warning: no calls to throwing functions occur within 'try' expression
warning: 'catch' block is unreachable because no errors are thrown in 'do' block
```

This RED demonstrated both missing parts of the contract: there was no typed
public error and the snapshot initializer could not reject incompatible data.

### Minimal correction

- Added public `SimulationError: Error, Sendable, Equatable` with
  `tableVersionMismatch(expected:actual:)`.
- Replaced the optional-snapshot initializer with two unambiguous entry points:
  - `PinballSimulation(table:)`, non-throwing, for a fresh simulation;
  - `PinballSimulation(table:snapshot:) throws`, for restored state.
- The restoring initializer compares versions before assigning state and throws
  the exact expected/actual values. It never normalizes or rewrites the snapshot.
- Existing compatible-snapshot tests now use `try`; the fresh initialization
  test remains non-throwing.

### Corrective GREEN

Targeted command: the same `--filter PinballSimulationTests` command above.

Result: exit `0`; 5 Task 2 tests passed, 0 failures, including explicit mismatch
rejection and successful compatible-snapshot initialization.

Full-suite command:

```sh
rtk proxy swift test --package-path /Users/benjamin/Documents/Apps/NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task2-019f8653/swiftpm
```

Result: exit `0`; 6 tests passed, 0 failures, no warnings.

### Fix auto-review

- The error exposes only deterministic integer schema versions and is both
  `Sendable` and `Equatable` as required.
- A matching snapshot preserves its bytes/value state; only mismatches reject.
- Fresh-game ergonomics are unchanged at call sites using
  `PinballSimulation()` or `PinballSimulation(table:)`.
- No optional snapshot path remains that could bypass validation.
- No Apple dependency, art, future-lot behavior, commit, push, remote, or ASC
  operation was introduced.

Fix findings: none. Fix concerns: none.
