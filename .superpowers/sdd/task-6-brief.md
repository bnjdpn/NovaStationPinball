### Task 6: Sauvegardes séparées et restauration unique

**Files:**
- Create: `NovaStationCore/Sources/NovaStationCore/PersistenceModels.swift`
- Create: `NovaStationPinball/Services/LocalGameStore.swift`
- Test: `NovaStationCore/Tests/NovaStationCoreTests/PersistenceModelsTests.swift`
- Test: `NovaStationPinballTests/LocalGameStoreTests.swift`

**Interfaces:**
- Produces: `SettingsState`, `HighScoreEntry`, `ActiveCheckpoint`, `CheckpointEnvelope`, `LocalGameStore.restoreCheckpointOnce()`.

- [ ] Tester séparément réglages, scores et checkpoint versionné.
- [ ] Tester que restaurer consomme le checkpoint une seule fois.
- [ ] Tester qu’un checkpoint corrompu est supprimé sans toucher aux high scores.
- [ ] Implémenter les modèles puis l’adapter UserDefaults/fichiers injectables.
- [ ] Vérifier SPM et XCTest app.
