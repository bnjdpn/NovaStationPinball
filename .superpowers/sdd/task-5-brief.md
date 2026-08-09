### Task 5: Replays, déterminisme et soak

**Files:**
- Create: `NovaStationCore/Sources/NovaStationCore/Replay.swift`
- Create: `NovaStationCore/Sources/NovaStationCore/StableHasher.swift`
- Test: `NovaStationCore/Tests/NovaStationCoreTests/ReplayDeterminismTests.swift`
- Test: `NovaStationCore/Tests/NovaStationCoreTests/SimulationSoakTests.swift`

**Interfaces:**
- Produces: `Replay`, `ReplayInput`, `ReplayResult.hash`, encode/décode JSON stable.

- [ ] Écrire un test faisant rejouer la même séquence dix fois et exigeant un hash unique identique.
- [ ] Confirmer l’échec faute de replay/hash stable, implémenter, puis vérifier.
- [ ] Écrire un soak de 432 000 ticks (30 minutes à 240 Hz) avec invariants valeurs finies, bille bornée, règles valides.
- [ ] Implémenter les protections numériques nécessaires uniquement après échec observé.
- [ ] Mesurer et consigner la durée du soak sans désactiver le test.
