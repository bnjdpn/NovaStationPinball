### Task 3: Collisions continues et mécanismes de table

**Files:**
- Create: `NovaStationCore/Sources/NovaStationCore/Collision.swift`
- Create: `NovaStationCore/Sources/NovaStationCore/TableElements.swift`
- Modify: `NovaStationCore/Sources/NovaStationCore/PinballSimulation.swift`
- Test: `NovaStationCore/Tests/NovaStationCoreTests/CollisionTests.swift`
- Test: `NovaStationCore/Tests/NovaStationCoreTests/MechanismTests.swift`

**Interfaces:**
- Produces: `SweepHit`, `CollisionShape`, `FlipperState`, `PlungerState`, capteurs et résolution continue segment/cercle/arc.
- Contract: aucune bille ne traverse un rail ou une cible aux vitesses maximales de la table.

- [ ] Écrire et faire échouer les tests de sweep cercle-segment, coins, restitution et tunneling.
- [ ] Implémenter le temps d’impact continu et la résolution minimale ; vérifier les tests.
- [ ] Écrire et faire échouer les tests de batteur au repos/actif et transfert d’impulsion.
- [ ] Implémenter les batteurs puis vérifier.
- [ ] Répéter RED/GREEN pour lanceur, bumpers, cibles, capteurs, friction, nudge et tilt.
- [ ] Lancer toute la suite SPM et `git diff --check`.
