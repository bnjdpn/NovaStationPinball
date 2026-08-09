### Task 4: Règles, missions et neuf habilitations

**Files:**
- Create: `NovaStationCore/Sources/NovaStationCore/GameRules.swift`
- Create: `NovaStationCore/Sources/NovaStationCore/MissionCatalog.swift`
- Create: `NovaStationCore/Sources/NovaStationCore/ScoreEngine.swift`
- Test: `NovaStationCore/Tests/NovaStationCoreTests/GameRulesTests.swift`
- Test: `NovaStationCore/Tests/NovaStationCoreTests/MissionCatalogTests.swift`
- Create: `docs/reference-behavior-matrix.md`

**Interfaces:**
- Produces: `GameRulesState`, `MissionID`, `MissionState`, `ClearanceLevel` (neuf valeurs), `ScoreAward`.
- Contract: trois billes, bonus, multiplicateurs, extra-ball, multiball, ball-save, tilt, mission start/complete/fail et promotion.

- [ ] Documenter dans la matrice chaque équivalent Nova, trigger, score, transition et tolérance, sans copier de ressource.
- [ ] Écrire et faire échouer un test isolé par transition de règles et par mission.
- [ ] Implémenter seulement les transitions couvertes et vérifier après chaque groupe.
- [ ] Ajouter des tests table-driven prouvant les neuf promotions et plafonds de score.
- [ ] Lancer la suite complète et vérifier qu’aucune mission n’est sans test.
