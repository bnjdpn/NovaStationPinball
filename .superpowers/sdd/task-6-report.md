# Task 6 — Sauvegardes séparées et restauration unique

## Statut

DONE. Aucun réseau ni dépendance ajoutée.

## Design

- `SettingsState`, `HighScoreEntry`, `ActiveCheckpoint` et `CheckpointEnvelope`
  sont `Sendable`, `Codable` et `Equatable`. Chaque modèle écrit et valide son
  `formatVersion` v1.
- Le checkpoint comprend le `SimulationSnapshot`, le `GameRulesState` et le
  `Replay` nécessaires à la reprise complète d'une partie active.
- `LocalGameStore` reçoit sa suite `UserDefaults`, son répertoire de fichiers,
  son `FileManager` et sa limite de scores. Les réglages et les scores sont des
  payloads JSON sous deux clés distinctes; le checkpoint est le seul fichier,
  `active-checkpoint.json`.
- `saveCheckpoint` utilise `Data.WritingOptions.atomic`. La restauration lit le
  fichier et le supprime avant le décodage : un checkpoint ne peut donc être
  rendu qu'une fois. Les seules erreurs absorbées sont `DecodingError` et
  `ReplayError`, explicitement classées comme checkpoint corrompu; les erreurs
  de lecture, suppression ou écriture remontent.
- Les scores sont rangés par score décroissant, date croissante, nom puis
  identifiant, et limités de façon déterministe lors de leur sauvegarde.

## Fichiers

- Créé : `NovaStationCore/Sources/NovaStationCore/PersistenceModels.swift`
- Créé : `NovaStationPinball/Services/LocalGameStore.swift`
- Créé : `NovaStationCore/Tests/NovaStationCoreTests/PersistenceModelsTests.swift`
- Créé : `NovaStationPinballTests/LocalGameStoreTests.swift`
- Mis à jour : `project.yml` — dépendance locale au produit SwiftPM
  `NovaStationCore` (sans compilation du Core dans le module app), module app
  stable et réglages de bundles XCTest nécessaires à la validation.

## TDD — RED puis GREEN

1. RED modèles :
   `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task6-persistence/swiftpm-red-models --filter PersistenceModelsTests`
   a échoué avec `cannot find 'SettingsState'`, `HighScoreEntry`,
   `ActiveCheckpoint` et `CheckpointEnvelope` in scope.
2. GREEN modèles : même suite après l'implémentation, 4/4 tests verts.
3. RED store : après avoir retiré `LocalGameStore.swift`, XCTest sur l'UDID
   possédé a échoué (exit 65) avec
   `Build input file cannot be found: .../Services/LocalGameStore.swift`.
4. GREEN store : après recréation minimale, `LocalGameStoreTests` a passé 4/4
   tests (séparation settings/scores, tri/limite, consommation unique,
   suppression d'un checkpoint corrompu sans altérer les scores).

## Vérifications

- `rtk proxy swift test ... --filter PersistenceModelsTests` : exit 0, 4 tests.
- `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task6-persistence/swiftpm-full` : exit 0, 94 tests.
- `rtk proxy xcodegen generate` : exit 0.
- Build générique non signé avec package local : exit 0, `BUILD SUCCEEDED`;
  le graphe Xcode déclare explicitement `NovaStationPinball -> NovaStationCore`.
- XCTest final :
  `rtk proxy xcodebuild test -scheme NovaStationPinball -destination 'platform=iOS Simulator,id=A3426729-6E7A-40EA-9DA4-BE0C32C096F9' ... -only-testing:NovaStationPinballTests/LocalGameStoreTests -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -maximum-concurrent-test-simulator-destinations 1`
  : exit 0, 4 tests, reçu
  `/private/tmp/apps-factory/NovaStationPinball/task6-persistence/xcresult/task6-store-green-final.xcresult`.

## Simulateurs possédés et nettoyage

- `B53EDAB1-F2F0-43FF-8453-AAACF2F7332F` (`NovaTask6-20260722013858`, iPhone
  17 Pro, iOS 26.2) : validation XCTest unité initiale verte (5 tests), puis
  supprimé par son UDID exact.
- `A3426729-6E7A-40EA-9DA4-BE0C32C096F9` (`NovaTask6-20260722014445`, iPhone
  17 Pro, iOS 26.2) : cycle RED/GREEN final, puis supprimé par son UDID exact.
- Aucun device par nom/`booted`, aucun shutdown, erase, reset ou nettoyage
  global n'a été utilisé.

## Auto-revue

- Les données persistées sont isolées par clé/fichier et la corruption de
  checkpoint ne touche jamais les scores ou réglages.
- L'écriture checkpoint est atomique et les erreurs de stockage restent
  observables.
- La dépendance Xcode utilise le produit SwiftPM local `NovaStationCore`; les
  sources du Core ne sont pas ajoutées au target `NovaStationPinball`.
- Aucun point bloquant identifié.

## Fix après revue

### Findings corrigés

- `saveCheckpoint` crée désormais le répertoire injecté et ses intermédiaires
  avant son écriture atomique. Toute erreur de création ou d'écriture est
  propagée; le test couvre explicitement un chemin qui est un fichier plutôt
  qu'un répertoire.
- `LocalGameStore` est `@unchecked Sendable` uniquement parce qu'un `NSLock`
  privé sérialise toutes les opérations sur ses dépendances injectées. Le
  verrou couvre la séquence complète existence → lecture → suppression →
  décodage, ainsi qu'une écriture checkpoint concurrente; aucun callback
  externe n'est exécuté sous le verrou.
- Deux restaurations démarrées simultanément obtiennent exactement un
  checkpoint et un `nil`, sans erreur d'absence de fichier. Le collecteur du
  test est lui-même verrouillé.
- Les versions v2 de `HighScoreEntry`, `ActiveCheckpoint` et
  `CheckpointEnvelope` sont maintenant testées, en plus de `SettingsState`.
- La responsabilité d'appeler avec identifiants, noms et scores valides et
  dédoublonnés est documentée dans `LocalGameStore`; aucune règle produit
  supplémentaire n'a été introduite.

### RED puis GREEN

- RED ciblé : `LocalGameStoreTests` sur iOS 26.2 a échoué avec 1 échec attendu
  (5 réussites), `testSavingCheckpointCreatesMissingDirectoryThenRestoresIt`,
  erreur `NSCocoaErrorDomain Code=4` / `NSPOSIXErrorDomain Code=2` pour
  `missing/active-checkpoint.json`.
- GREEN ciblé : après création du répertoire via le `FileManager` injecté et
  sérialisation par verrou, la même suite a passé 7/7 tests, dont la création
  du répertoire, la propagation d'erreur et la restauration concurrente.

### Commandes et sorties

- `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task6-persistence/fix-swiftpm-targeted --filter PersistenceModelsTests` : exit 0, 5 tests.
- `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task6-persistence/fix-swiftpm-full` : exit 0, 95 tests.
- `rtk proxy xcodegen generate` : exit 0.
- Build générique non signé sous
  `/private/tmp/apps-factory/NovaStationPinball/task6-persistence/fix-generic-derived` : exit 0, `BUILD SUCCEEDED`.
- XCTest mono-worker : exit 0, 7 tests, bundle
  `/private/tmp/apps-factory/NovaStationPinball/task6-persistence/xcresult/task6-fix-green.xcresult`.

### UDID et nettoyage

- UDID possédé : `3C67B70D-4006-4F83-ACC5-E6BA35632092`,
  `NovaTask6Fix-20260722015045`, iPhone 17 Pro, iOS 26.2.
- Supprimé par cet UDID exact après lecture des reçus RED/GREEN. Aucun arrêt,
  effacement ou nettoyage global n'a été utilisé.

## Root warning fix

- RED runtime : le harness précédent utilisait deux queues
  `userInitiated` bloquées sur `start.wait`; la vérification racine a signalé
  `Thread Performance Checker` / priority inversion sur cette attente. Le
  rejeu a conservé le reçu
  `task6-root-warning-red.xcresult` avant toute modification du harness.
- GREEN : le test est maintenant `async throws` avec deux `async let` qui
  appellent simultanément `restoreCheckpointOnce()`. Il collecte
  déterministiquement un checkpoint et un `nil`, sans sémaphore, groupe ou
  attente de thread.
- Commande :
  `rtk proxy xcodebuild test -scheme NovaStationPinball -destination 'platform=iOS Simulator,id=11226672-2C91-4813-9133-5718B05C0E79' -derivedDataPath /private/tmp/apps-factory/NovaStationPinball/task6-persistence/root-warning-green-derived -resultBundlePath /private/tmp/apps-factory/NovaStationPinball/task6-persistence/xcresult/task6-root-warning-green.xcresult -only-testing:NovaStationPinballTests/LocalGameStoreTests -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -maximum-concurrent-test-simulator-destinations 1`.
- Résultat : exit 0, 7/7 tests. `xcresulttool` rapporte zéro échec et la
  recherche `Thread Performance Checker|priority inversion` dans le bundle
  de résultat a renvoyé exit 1 (aucune occurrence). La sortie Xcode finale ne
  contient pas ces diagnostics.
- UDID possédé : `11226672-2C91-4813-9133-5718B05C0E79`,
  `NovaTask6RootFix-20260722015818`, iPhone 17 Pro, iOS 26.2; supprimé par
  cet UDID exact après validation.
