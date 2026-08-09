# Task 3 report — continuous collisions and table mechanisms

Status: `DONE`

## Scope delivered

- Added deterministic, value-based collision geometry for segment capsules,
  circles, and finite arcs, including arc endpoints and both annular faces.
- Added bounded `SweepHit.time` values, contact center/point/normal data,
  restitution, continuous high-speed integration, and a conservative collision
  budget that never falls back to unchecked movement.
- Extended `Vector2` with the scalar, dot, length, normalization, and
  perpendicular operations required by the physics implementation.
- Extended versioned `TableDefinition` with logical collision shapes, ball
  radius, flippers, plunger, bumpers, targets, sensors, friction, nudge tuning,
  and tilt tuning. Values remain table units rather than display pixels.
- Added `FlipperState`, `PlungerState`, `TiltState`, and value definitions for
  all Task 3 mechanisms. The fixed-step simulation now updates them and applies
  flipper surface velocity, plunger release, bumper impulse, target response,
  sensor crossings, friction, nudge, and tilt suppression.
- Kept Task 2 table-version rejection unchanged. No scoring, rules, missions,
  persistence, rendering, Apple adapter, art, release, remote, or ASC work was
  introduced.

## TDD evidence

All Swift commands ran from
`/Users/benjamin/Documents/Apps/NovaStationPinball` through `rtk proxy`, using
the unique scratch path
`/private/tmp/apps-factory/NovaStationPinball/task3-019f8653/swiftpm`.

### Collision RED/GREEN

Initial test-first command:

```sh
rtk proxy swift test --package-path /Users/benjamin/Documents/Apps/NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-019f8653/swiftpm --filter CollisionTests
```

Initial RED: exit `1`. `CollisionTests.swift` existed before Task 3 production
types. Compilation failed on the expected absent API, beginning with
`cannot find 'CollisionShape' in scope`, followed by missing
`SegmentCollider`, `ContinuousCollision`, `SweepHit`, circle/arc colliders, and
the new table fields.

Initial GREEN: the same command passed 6 tests covering segment side impact,
endpoint impact, circle/arc shapes, restitution, `Sendable` value types, and a
600-units/s one-tick rail tunneling case.

Two auto-review collision findings received their own later RED/GREEN cycles:

- Multiple rebounds exhausted the four-contact budget and the old fallback
  placed the ball at `x = 6.9` beyond the rail. The targeted RED failed, then
  GREEN passed after freezing the unused tick fraction instead of applying
  unchecked motion.
- A ball approaching an arc from its inside returned a false time-zero contact.
  The targeted RED observed `time = 0` instead of `0.45`; GREEN passed after
  solving outer and inner radial faces separately while retaining endpoint
  capsules.

Final targeted collision result: 8 tests passed, 0 failures.

### Mechanism RED/GREEN sequence

Each family was appended to `MechanismTests.swift`, run against the prior
production state, and only then implemented. Commands used the same base as
above with `--filter MechanismTests` or the named test filter.

1. Flippers RED: absent `FlipperDefinition`, `FlipperState`, table field, and
   simulation state. GREEN: rest/active angular movement, surface velocity,
   impulse transfer, and left/right input passed. An initial exact floating
   assertion (`3.5999999999999996` versus `3.6`) was corrected to a tolerance
   without changing production behavior.
2. Plunger RED: absent `PlungerDefinition`, `PlungerState`, and table field.
   GREEN: clamped pull, one-shot release impulse, and launch-zone filtering
   passed.
3. Bumper RED: absent `BumperDefinition` and table field. GREEN: continuous
   circle impact, restitution, radial impulse, and event passed.
4. Target RED: absent `TargetDefinition` and table field. GREEN: high-speed
   physical segment response and event passed.
5. Sensor RED: absent `SensorDefinition` and table field. GREEN: high-speed
   non-physical crossing passed without modifying motion.
6. Friction RED: absent `linearFriction`. GREEN: exactly one fixed-tick damping
   operation passed.
7. Nudge RED: absent `nudgeImpulseScale`. GREEN: configured vector impulse
   applied to the ball passed.
8. Tilt RED: absent `TiltDefinition`, `TiltState`, and table field. GREEN:
   deterministic accumulation, one transition event, and flipper suppression
   passed. Swift Testing does not permit a mutating call directly inside this
   `#expect`; results were bound first, then the intended test ran unchanged.
9. Flipper integration behavioral RED: state reached active but the ball kept
   velocity `48` and ended at `x = 0`. GREEN: the updated flipper capsule now
   participates in continuous collision and transfers surface velocity.
10. Sensor ordering behavioral RED: a sensor behind an earlier rail was
    incorrectly emitted. GREEN: sensors are now evaluated only along the
    actually traveled portion before each physical impact.

Final targeted mechanism result: 13 tests passed, 0 failures.

## Final verification

Full suite command:

```sh
rtk proxy swift test --package-path /Users/benjamin/Documents/Apps/NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-019f8653/swiftpm
```

Fresh result: exit `0`; 27 tests in 3 Swift Testing suites passed, 0 failures.
This includes all Task 1/2 bootstrap and fixed-step/version-rejection tests.
The build emitted no warnings.

Diff hygiene command:

```sh
rtk proxy git diff --check
```

Result: exit `0`, no output. Because this new repository has no commits yet and
its files are untracked, an additional temporary-index check is recorded below
after staging only Task 3 paths in an isolated index; the real index is not
modified.

Temporary-index commands used
`GIT_INDEX_FILE=/private/tmp/apps-factory/NovaStationPinball/task3-019f8653/task3-index`
through `rtk proxy env`: `git read-tree --empty`, `git add` of the eight Task 3
source/test/report paths, then `git diff --cached --check`. The final command
also exited `0` with no output. A subsequent real-index status remained wholly
untracked, confirming that this check did not stage repository state.

## Auto-review

- Correctness: sweep times are rejected outside `[0, 1]`; segment side and
  endpoint candidates choose the earliest contact; arc inner/outer faces and
  endpoints are finite-angle checked; restitution only changes entering
  velocity. Static rails and targets use the same continuous path as the
  high-speed tests.
- Determinism: fixed iteration order is table order, equal-time surfaces use
  their stable index, collision work is capped, and cap exhaustion is
  conservative. No randomness, wall clock, task scheduling, global mutable
  state, or variable delta is used.
- Data/concurrency: all public geometry, shapes, definitions, and mechanism
  states are value types conforming to `Sendable`, `Codable`, and `Equatable`.
  `PinballSimulation` remains `Sendable`.
- Compatibility: `TableDefinition.version` remains the schema boundary and the
  throwing snapshot initializer still rejects mismatched versions. Existing
  Task 2 snapshot bytes and tests remain unchanged.
- Portability: core production imports only Swift/Foundation facilities and no
  Apple UI, rendering, audio, haptics, Game Center, or StoreKit framework.
- Scope: event names are mechanical facts only (`bumper`, `target`, `sensor`,
  `tilt`). No score values, rules, mission transitions, rewards, or future-task
  behavior were added.
- Repository safety: no commit, staging in the real index, push, remote query,
  release action, browser, or App Store Connect operation was performed.

## Limits

- Historical initial-pass limit: flipper collision used 32 deterministic
  intermediate capsule poses during a moving tick. Review fix wave 2 below
  supersedes this with validated geometry-derived subdivision.
- The four-contact budget freezes the remaining fraction of an exceptionally
  dense tick. This deliberately trades an imperceptible time loss for the
  stronger invariant that no unchecked fallback can cross a rail or target.
- Mechanism runtime state is held by `PinballSimulation`; Task 2's established
  snapshot wire shape is intentionally unchanged. Persistence/checkpoint work
  remains scoped to Task 6.

Findings after correction: none. Concerns: none blocking Task 3.

---

## Review fix wave — animated contacts, overlap stability, sensors, and numeric boundaries

Status: `DONE`

All commands in this wave ran from the repository root through `rtk proxy`
with the unique scratch path
`/private/tmp/apps-factory/NovaStationPinball/task3-fix-019f8653/swiftpm`.
No real Git index, commit, push, remote, release, or ASC action was used.

### 1. Animated flipper contact

RED command:

```sh
rtk proxy swift test --package-path /Users/benjamin/Documents/Apps/NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix-019f8653/swiftpm --filter MechanismTests.rotatingFlipperStrikesStationaryBall
```

RED result: exit `1`; the stationary ball retained velocity `0` and position
`(0, 0.5)` while the flipper rotated from horizontal to vertical. This
confirmed that the prior final-pose collider only considered ball displacement.

Correction: the simulation preserves the previous flipper pose, samples 32
ordered intermediate capsule poses, finds the first overlap entered by moving
surface velocity, depenetrates along that contact normal, and transfers the
flipper's surface impulse. The same targeted command then passed 1 test with 0
failures.

### 2. Singular circle and segment overlaps

RED command used `--filter CollisionTests.singular`.

RED result: both cases emitted the same bumper/target event four times, stayed
at zero spatial offset, and consumed the collision budget. The exact center or
axis made the fallback normal alternate with reflected velocity.

Correction:

- `SweepHit` now records `startedOverlapping`;
- circle singularity uses a fixed positive-X fallback, while a segment axis
  uses its stable left perpendicular;
- initial overlaps return a depenetrated center at `time = 0`;
- the simulation accepts overlap resolution even with zero ball displacement,
  but applies each surface's event/impulse only once per ball per tick.

GREEN result: 2 singular overlap tests passed. Both balls leave penetration,
their velocity separates along the chosen stable normal, and each mechanical
event appears exactly once.

### 3. Initial arc overlap

RED command used
`--filter CollisionTests.initialArcOverlapDepenetrates`.

RED result: the direct sweep returned `nil` and a stationary ball remained at
radius `1.0` inside the arc band.

Correction: finite arcs now test initial annular overlap before future radial
roots, select the nearest free face deterministically (outer face on an exact
tie), return a `time = 0` overlap hit, and preserve endpoint handling.

GREEN result: the direct hit and simulation both resolved to `(1.1, 0)` with
zero velocity; 1 test passed.

### 4. Sensor crossing semantics and ball identity

Stationary-occupancy RED command used
`--filter MechanismTests.stationaryBallInsideSensorDoesNotTrigger`.

RED result: the same `sensor:occupied` event was emitted on both stationary
ticks. GREEN followed after sensor code explicitly ignored
`startedOverlapping`; an already occupied sensor is now silent.

Multi-ball RED command used
`--filter MechanismTests.twoBallsCrossingSensorRemainDistinct`.

RED result: compilation failed because `GameEvent` had no `ballID`, proving the
event model could not distinguish passages. `GameEvent.ballID: UInt64?` was
then added with a default `nil` for non-ball-specific compatibility. Sensor
events carry the current ball ID and deduplicate only the same ball/sensor pair.
GREEN result: IDs `11` and `22` produced two ordered events in one frame.

The original high-speed outside-through-inside crossing test—whose API-absence
RED and GREEN are documented earlier in this report—remains active and now
asserts `ballID = 1`. The physical-impact occlusion test also remains green.

### 5. Non-finite values and invalid definitions

Runtime-input RED command used
`--filter PinballSimulationTests.nonFiniteInputIsNeutralized`.

RED result: infinite nudge contaminated position/velocity with infinities and
tilted the simulation. GREEN followed after sanitizing a non-finite nudge to
zero and holding the current plunger pull when its new analog input is
non-finite. No invalid value reaches tilt, velocity, position, or snapshot.

Table-validation RED command used
`--filter PinballSimulationTests.rejectsInvalidTableDefinitions`.

RED result: compilation failed on absent `SimulationError.nonFiniteValue` and
`invalidValue`; the compiler also confirmed that the custom table initializer
was not throwing.

Correction:

- `PinballSimulation()` remains a non-throwing standard-table initializer;
- `PinballSimulation(table:)` and the restoring initializer validate before
  assignment and throw a precise field path;
- validation covers playfield dimensions, essential vectors, ball/collider/
  flipper/plunger/arc radii and dimensions, arc/flipper angles, restitution,
  impulses, friction, nudge tuning, tilt threshold/decay, and plunger release
  threshold;
- snapshot elapsed time, ball positions, and velocities must be finite, and
  elapsed time must be non-negative;
- table-version mismatch remains explicit and unchanged.

GREEN results: the table-driven validation test passed all 14 invalid cases;
the dedicated non-finite snapshot test also passed with the exact path
`snapshot.balls[0].position.x`.

### 6. Explicit plunger release threshold

RED command used `--filter MechanismTests.plungerReleaseThreshold`.

RED result: compilation failed because `PlungerDefinition` did not expose a
release threshold.

Correction: `releaseThreshold` defaults to `0.01`, must be finite in `[0, 1)`,
and any input at or below it releases the previously stored pull without first
overwriting that charge.

GREEN result: a pull of `0.5` followed by `0.001` produced the expected impulse
`(0, 6)` and reset stored pull to zero.

### Targeted and full verification

Targeted commands and fresh results:

- `--filter CollisionTests`: 11 tests passed, 0 failures;
- `--filter MechanismTests`: 17 tests passed, 0 failures;
- `--filter PinballSimulationTests`: 8 tests passed, 0 failures.

Full command:

```sh
rtk proxy swift test --package-path /Users/benjamin/Documents/Apps/NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix-019f8653/swiftpm
```

Fresh result: exit `0`; 37 tests in 3 suites passed, 0 failures, no warnings.

`rtk proxy git diff --check` exited `0` with no output. Because the repository
still has no commits and all project files are untracked, the eleven touched
Task 3 paths were also added only to the isolated index
`/private/tmp/apps-factory/NovaStationPinball/task3-fix-019f8653/task3-index`;
`git diff --cached --check` there also exited `0`. The real index remained
untouched.

### Fix-wave auto-review

- Animated flipper contact is caused by ordered capsule motion, not by treating
  the final pose as a static collider.
- Every initial-overlap normal is independent of the velocity it may reflect;
  depenetration guarantees spatial progress before another collision query.
- Static overlap effects are surface-indexed and one-shot during a ball tick;
  the conservative four-contact freeze remains unchanged.
- Sensor semantics are entry/crossing only. Starting inside is not an entry,
  and distinct balls cannot be merged by event equality.
- Numeric validation happens before mutable simulation state is assigned;
  runtime input sanitization happens before any mechanism or physics use.
- The standard initializer remains source-compatible and non-throwing. Custom
  table callers now acknowledge validation with `try`.
- No Apple framework, scoring, rules, mission, persistence, rendering, art, or
  release behavior was introduced.

Fix findings after correction: none. Fix concerns: none.

---

## Review fix wave 2 — relative flipper contact, adaptive sweeps, data compatibility

Status: `DONE`

All commands in this wave ran from the repository root through `rtk proxy`
with the unique scratch path
`/private/tmp/apps-factory/NovaStationPinball/task3-fix2-019f8653/swiftpm`.
No real Git index, commit, push, remote, release, or ASC action was used.

### 1. Relative flipper contact

RED command:

```sh
rtk proxy swift test --package-path NovaStationCore --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix2-019f8653/swiftpm --filter rotatingFlipperIgnoresFasterSeparatingBall
```

RED result: the ball separating at `-1000` units/s was incorrectly changed to
`(-1007.4659969957763, 0.5471737257073787)` by a slower moving flipper surface.

Correction: collision acceptance, moving-surface resolution, and impulse
transfer now all use surface-minus-ball relative velocity. The same command
then passed 1 test with 0 failures and preserved velocity `(-1000, 0)`.

### 2. Adaptive bounded flipper sweep

RED commands:

```sh
rtk proxy swift test --package-path NovaStationCore --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix2-019f8653/swiftpm --filter adaptiveFlipperSweepAvoidsPoseAliasing
rtk proxy swift test --package-path NovaStationCore --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix2-019f8653/swiftpm --filter rejectsExcessiveFlipperSweepWork
```

RED results: a stationary ball halfway between two of the legacy 32 poses kept
zero velocity and its original position; a pathological table requiring far
more work was accepted.

Correction: the deterministic subdivision count is derived from actual angular
travel, flipper length, and `ballRadius + flipperRadius`, with maximum geometric
sampling error equal to half that contact radius. Table validation retains the
existing strict `ballRadius > 0` contract and rejects any flipper requiring
more than 256 substeps as
`invalidValue(path: "table.flippers[i].sweepSubsteps")`.

GREEN results: both commands passed 1 test with 0 failures. The separating-ball
regression command was also rerun and passed.

### 3. Thick arc without an inner free region

RED command:

```sh
rtk proxy swift test --package-path NovaStationCore --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix2-019f8653/swiftpm --filter thickArcDepenetratesOutwardFromCenter
```

RED result: with expanded half-thickness greater than arc radius, both the
direct sweep and simulation returned the unchanged center `(0, 0)` and an
inward normal.

Correction: an arc with no inner free region always resolves an initial
overlap through its outer face, using the finite-arc midpoint direction for the
singular center. GREEN passed 1 test with 0 failures and resolved to `(0.2, 0)`.

### 4. Duplicate ball identifiers

RED command:

```sh
rtk proxy swift test --package-path NovaStationCore --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix2-019f8653/swiftpm --filter rejectsDuplicateBallIdentifiers
```

RED result: a restoring snapshot containing two balls with ID `7` was accepted.

Correction: snapshot validation now rejects the duplicate before state
assignment with the exact path
`snapshot.balls[1].id (duplicate 7; first at snapshot.balls[0].id)`.
GREEN passed 1 test with 0 failures.

### 5. Legacy table JSON and current round trip

RED command:

```sh
rtk proxy swift test --package-path NovaStationCore --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix2-019f8653/swiftpm --filter tableCodingIsBackwardCompatible
```

RED result: decoding the original v1 JSON shape failed with
`DecodingError.keyNotFound` for `ballRadius`.

Correction: `TableDefinition` now has explicit coding. The original required
keys remain `version`, `playfieldSize`, and `gravity`; missing Task 3 keys use
the exact standard defaults (`0.025`, empty collections, nil optionals,
friction `0`, nudge scale `1`). Encoding includes all current nonoptional data,
and a representative table containing every mechanism family round trips
unchanged. GREEN passed 1 test with 0 failures.

The README now documents that `PinballSimulation()` remains nonthrowing while
custom-table and snapshot-restoration initializers validate and throw.

### Targeted and full verification

Targeted commands and fresh results:

- `--filter CollisionTests`: 12 tests passed, 0 failures;
- `--filter MechanismTests`: 19 tests passed, 0 failures;
- `--filter PinballSimulationTests`: 11 tests passed, 0 failures.

Full command:

```sh
rtk proxy swift test --package-path NovaStationCore --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix2-019f8653/swiftpm
```

Fresh result: exit `0`; 43 tests in 3 suites passed, 0 failures, no warnings.

`rtk proxy git diff --check` exited `0` with no output. The repository still
has no commits and remains wholly untracked, so the ten touched paths in this
wave were also added only to the isolated index
`/private/tmp/apps-factory/NovaStationPinball/task3-fix2-019f8653/task3-index`;
`git diff --cached --check` there exited `0`. The real-index status was
identical before and after that check.

This wave supersedes the earlier fixed-32-pose limitation: rotational sweep
work is now geometry-derived, deterministic, capped, and validated before a
custom table can enter the simulation.

---

## Review fix wave 3 — time-aligned animated flipper sweep

Status: `DONE`

All commands in this wave ran from the repository root through `rtk proxy`
with the unique scratch path
`/private/tmp/apps-factory/NovaStationPinball/task3-fix3-019f8653/swiftpm`.

### RED/GREEN evidence

RED command:

```sh
rtk proxy swift test --package-path NovaStationCore --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix3-019f8653/swiftpm --filter rotatingFlipperUsesBallPositionAtEachSweepTime
```

The exact reproduction starts a ball at `(0, 0.5)` with velocity `(0, 1000)`
while a unit flipper rotates from horizontal to vertical in one fixed tick.
RED failed because the ball received an artificial contact: velocity became
`(-191.77347615597446, 1004.745472203028)` and position became
`(-0.8790561506498934, 4.686718353789624)` instead of preserving velocity and
ending at `(0, 4.666666666666667)`.

Root cause: every adaptive flipper pose was compared with the ball's initial
position, then the flipper's final static collider was queried again across the
whole tick. This mixed different instants and double-counted the moving surface.

Correction:

- gravity, friction, nudge, and plunger velocity changes are applied before the
  animated sweep;
- each flipper pose is compared with the ball position predicted at the same
  substep fraction, `start + velocity * fraction * fixedTimeStep`;
- candidates from multiple animated flippers choose the earliest fraction,
  with flipper index as deterministic tie-breaker;
- a real contact stores its depenetrated center at that fraction and advances
  only the remaining tick duration;
- final static colliders for flippers already covered by the animated sweep are
  excluded from the remainder integration.

GREEN: the same targeted command passed 1 test with 0 failures. The ball kept
velocity `(0, 1000)` and reached exactly `(0, 4.666666666666667)`.

The stationary-strike, faster-separating-ball, and adaptive anti-aliasing tests
were each rerun individually and passed.

### Targeted and full verification

- `--filter MechanismTests`: 20 tests passed, 0 failures;
- `--filter CollisionTests`: 12 tests passed, 0 failures;
- `--filter PinballSimulationTests`: 11 tests passed, 0 failures;
- full package suite: 44 tests in 3 suites passed, 0 failures, no warnings.

`rtk proxy git diff --check` exited `0`. Because this repository still has no
commits and remains wholly untracked, the source, test, and report touched by
this wave were also checked through the isolated index
`/private/tmp/apps-factory/NovaStationPinball/task3-fix3-019f8653/task3-index`;
`git diff --cached --check` exited `0`, and the real-index status was unchanged.

No commit, push, remote, release, browser, or App Store Connect operation was
performed.

## Review fix wave 4 — unified chronological collision timeline

Status: `DONE`

All commands in this wave ran from the repository root through `rtk proxy`
with the unique scratch path
`/private/tmp/apps-factory/NovaStationPinball/task3-fix4-019f8653/swiftpm`.

### Architectural RED

RED command:

```sh
rtk proxy swift test --package-path NovaStationCore --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix4-019f8653/swiftpm --filter staticRailPrecedesAnimatedFlipperOnOneTimeline
```

The reproduction sends a radius-`0.05` ball from `(0, 0.5)` at `(240, 0)`
toward a vertical rail at `x = 0.4`, with a rotating flipper pivoted behind it
at `(0.5, 0.5)`. The rail impact center must be `x = 0.35`, followed by a full
leftward rebound and final `x = -0.3`.

RED failed because the separate animated pre-pass reached the flipper first:
the frame ended at `x = 0.4611111111111111` with `vx = 4.800000000000011`
instead of `x = -0.3`, `vx = -240`.

### Correction

`advanceBall` now owns one chronological `remainingTime` loop for every
physical contact:

- each iteration computes the earliest continuous static candidate from rails,
  targets, bumpers, and non-animated flippers;
- the same iteration computes animated-flipper candidates at absolute substep
  fractions after the current elapsed fraction, predicting the ball from its
  current position and velocity over only that interval;
- `CollisionCandidate` compares both families by local impact time; exact ties
  deterministically prefer static table order, then flipper index;
- sensors are recorded only over the traveled portion before the chosen impact;
- static or animated contact is resolved, and the loop continues over only the
  remaining duration;
- the four-contact budget is global across both candidate families;
- moving-surface relative velocity and the validated adaptive subdivision are
  retained. There is no animated pre-pass or final-pose replay.

GREEN: the exact rail command passed 1 test with 0 failures. The ball hit the
rail first, retained `y = 0.5`, rebounded at `vx = -240`, and ended at
`x = -0.3` without tunneling.

### Regression and full verification

- `--filter MechanismTests`: 21 tests passed, 0 failures, including tangential,
  stationary, separating, time-aligned, anti-aliasing, sensor, and rail-order
  cases;
- `--filter CollisionTests`: 12 tests passed, 0 failures, including singular
  overlaps, thick arcs, contact budget, and high-speed tunneling;
- `--filter PinballSimulationTests`: 11 tests passed, 0 failures;
- full package suite: 45 tests in 3 suites passed, 0 failures, no warnings.

`rtk proxy git diff --check` exited `0`. Since the repository still has no
commits and remains wholly untracked, the source, test, and report touched by
this wave were also checked through the isolated index
`/private/tmp/apps-factory/NovaStationPinball/task3-fix4-019f8653/task3-index`;
`git diff --cached --check` exited `0`, and the real-index status was unchanged.

No commit, push, remote, release, browser, or App Store Connect operation was
performed.

---

## Review fix wave 5 — continuous ball sweep inside animated pose intervals

Status: `DONE`

All commands in this wave ran from the repository root through `rtk proxy`
with the unique scratch path
`/private/tmp/apps-factory/NovaStationPinball/task3-fix5-019f8653/swiftpm`.

### RED/GREEN evidence

RED command:

```sh
rtk proxy swift test --package-path NovaStationCore --scratch-path /private/tmp/apps-factory/NovaStationPinball/task3-fix5-019f8653/swiftpm --filter animatedFlipperIntervalsUseContinuousBallSweep
```

The reproduction deliberately requires only one curvature-derived flipper
interval: the flipper rotates from `0` to `0.01`, both radii are `0.01`, and a
ball travels from `(0.5, -0.5)` at velocity `(0, 240)`. RED left the ball at
`y = 0.5` with unchanged `vy = 240`, proving that endpoint overlap sampling
missed the crossing inside the interval.

Correction keeps the subdivision count driven only by flipper curvature. For
each remaining animated interval it now:

- computes the ball's exact interval start and linear displacement;
- performs continuous circle-versus-capsule sweep against the coherently
  interpolated interval-end flipper pose;
- converts the returned local hit fraction into the absolute tick fraction;
- interpolates the flipper again at that exact impact fraction and recomputes
  ball center, contact point, and normal there;
- applies the existing surface-minus-ball relative-velocity gate and reports
  the candidate to the unified chronological collision loop.

GREEN: the same one-interval test passed; the flipper reached exactly `0.01`,
the ball received a downward post-contact velocity, and remained below the
surface instead of tunneling through it.

### Regression and full verification

- `--filter MechanismTests`: 22 tests passed, 0 failures, including stationary,
  tangential, separating, time-aligned, rail-first, anti-aliasing, and the new
  fast-ball/slow-flipper CCD case;
- `--filter CollisionTests`: 12 tests passed, 0 failures;
- `--filter PinballSimulationTests`: 11 tests passed, 0 failures;
- full package suite: 46 tests in 3 suites passed, 0 failures, no warnings.

`rtk proxy git diff --check` exited `0`. Since the repository still has no
commits and remains wholly untracked, the source, test, and report touched by
this wave were also checked through the isolated index
`/private/tmp/apps-factory/NovaStationPinball/task3-fix5-019f8653/task3-index`;
`git diff --cached --check` exited `0`, and the real-index status was unchanged.

No commit, push, remote, release, browser, or App Store Connect operation was
performed.
