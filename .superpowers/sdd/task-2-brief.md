### Task 2: Types déterministes, table versionnée et pas fixe

**Files:**
- Create: `NovaStationCore/Sources/NovaStationCore/Geometry.swift`
- Create: `NovaStationCore/Sources/NovaStationCore/SimulationModels.swift`
- Create: `NovaStationCore/Sources/NovaStationCore/TableDefinition.swift`
- Create: `NovaStationCore/Sources/NovaStationCore/PinballSimulation.swift`
- Test: `NovaStationCore/Tests/NovaStationCoreTests/PinballSimulationTests.swift`

**Interfaces:**
- Produces: `Vector2`, `BallState`, `PlayerInput`, `GameEvent`, `SimulationFrame`, `SimulationSnapshot`, `TableDefinition`, `PinballSimulation.step(_:) -> SimulationFrame`.
- Contract: pas exact `1.0 / 240.0`, types publics `Sendable`, données de table indépendantes des pixels.

- [ ] Écrire les tests d’API, de gravité sur un tick, d’accumulation de temps et d’encodage stable de snapshot.
- [ ] Exécuter le test ciblé et confirmer que les types ou résultats manquent.
- [ ] Implémenter les modèles valeur et le pas fixe minimal.
- [ ] Exécuter `swift test` et confirmer le vert.
- [ ] Refactorer les constantes physiques dans `PhysicsTuning` sans changer les résultats.
