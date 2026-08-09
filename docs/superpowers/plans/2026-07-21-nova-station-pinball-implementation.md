# Nova Station Pinball Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer un repo iOS autonome App Store-ready contenant une table de pinball rétrofuturiste originale dont le gameplay, les règles, les contrôles, les médias et les preuves satisfont la spécification approuvée.

**Architecture:** `NovaStationCore` est un Swift Package déterministe et sans framework Apple. L’app iOS pilote ce cœur depuis une scène SpriteKit rendue par couches PNG ImageGen, avec une coque SwiftUI et des adapters Apple injectables. Les contrats Ruby vérifient art, support, metadata et release indépendamment du runtime.

**Tech Stack:** Swift 6, Swift Package Manager, SpriteKit, SwiftUI, AVAudioEngine, Core Haptics, GameKit, StoreKit 2, XcodeGen, XCTest, Ruby, Fastlane, ImageMagick, ImageGen.

## Global Constraints

- Root exact : `/Users/benjamin/Documents/Apps/NovaStationPinball`, repo autonome sur `main`.
- Bundle ID exact : `com.bnjdpn.NovaStationPinball` ; iPhone/iPad ; iOS 17+ ; paysage.
- Toutes les commandes shell passent par `rtk`; Git/Ruby/Swift/Xcode via `rtk proxy`.
- Tout état mutable de validation va sous `/private/tmp/apps-factory/NovaStationPinball/<execution_id>/`.
- Les tests simulateur utilisent un UDID éphémère possédé, jamais `booted` ni un nom, un worker unique.
- Aucun code ni asset de Space Cadet ; la référence publique est une oracle comportementale seulement.
- Toute logique de gameplay est testée RED puis GREEN dans `NovaStationCore`.
- Tous les visuels identitaires finaux sont de vrais PNG bitmap ImageGen avec provenance exacte.
- Zéro SVG, SVGZ, EPS, AI, PSD, PDF vectoriel, emoji décoratif ou illustration CSS.
- SwiftUI reste une coque système ; SpriteKit affiche les couches raster finales.
- Aucun GitHub Actions, TestFlight, tracking, compte, publicité, paywall ou IAP non-tip.
- L’app est gratuite ; seuls `tip.cafe`, `tip.merci`, `tip.soutien` sont permis et ne débloquent rien.
- Support : `https://bnjdpn.github.io/NovaStationPinball/#contact`, formulaire Formspree, aucun email public.
- Aucun remote, fiche ASC, commit, push, upload ou soumission sans demande explicite séparée.

---

### Task 1: Repo autonome et contrats exécutables

**Files:**
- Create: `AGENTS.md`, `.gitignore`, `README.md`, `project.yml`, `Package.swift`, `Gemfile`
- Create: `NovaStationPinball/Resources/PrivacyInfo.xcprivacy`, `NovaStationPinball/NovaStationPinball.entitlements`
- Create: `scripts/release_contract.rb`, `scripts/release_contract_test.rb`
- Create: `fastlane/Fastfile`, `fastlane/Appfile`, `fastlane/release_config.json`
- Create: `docs/index.html`, `docs/privacy.html`

**Interfaces:**
- Produces: XcodeGen targets `NovaStationPinball`, `NovaStationPinballTests`, `NovaStationPinballUITests`; SPM product `NovaStationCore`; Fastlane lane `release_contract`.

- [ ] Écrire `scripts/release_contract_test.rb` qui exige bundle ID, iOS 17, familles 1/2, paysage, FR/EN, les trois tips, Formspree, zéro workflow et toutes les lanes obligatoires.
- [ ] Exécuter `rtk proxy ruby scripts/release_contract_test.rb` et confirmer l’échec par fichiers manquants.
- [ ] Ajouter les fichiers de contrat et configuration minimaux, sans sources de gameplay.
- [ ] Exécuter le test Ruby puis `rtk proxy xcodegen generate` et confirmer leur réussite.
- [ ] Vérifier `rtk proxy git status --short --branch` sans toucher à un autre repo.

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

### Task 7: Greybox SpriteKit et contrôles tactiles

**Files:**
- Modify: `NovaStationPinball/App/NovaStationPinballApp.swift`
- Create: `NovaStationPinball/App/RootView.swift`, `NovaStationPinball/App/AppModel.swift`
- Create: `NovaStationPinball/Game/PinballScene.swift`, `SimulationDriver.swift`, `TouchInterpreter.swift`
- Create: `NovaStationPinball/Resources/Art/greybox-table-guide.png`
- Create: `scripts/export_greybox_guide.swift`
- Test: `NovaStationPinballTests/TouchInterpreterTests.swift`, `SimulationDriverTests.swift`
- Test: `NovaStationPinballUITests/LayoutUITests.swift`

**Interfaces:**
- Produces: `TouchInterpreter.events(for:in:)`, `SimulationDriver.advance(elapsed:input:)`, scène 4:3 letterboxée.

- [ ] Tester et faire échouer les zones invisibles gauche/droite, lanceur glisser-relâcher, nudge court et annulation multitouch.
- [ ] Implémenter l’interpréteur puis vérifier.
- [ ] Tester le rattrapage borné du driver 240 Hz et implémenter.
- [ ] Construire la scène greybox fonctionnelle en SpriteKit avec formes uniquement marquées `greybox`, jamais final art.
- [ ] Exporter un guide raster exact 4:3 avec zones mécaniques et sûres.
- [ ] Tester iPhone/iPad : aucun recadrage et ratio table/console conforme.

### Task 8: Pipeline ImageGen et intégration raster

**Files:**
- Create: `Art/ImageGen/*.png`, `Art/imagegen-provenance.json`
- Create: `scripts/build_imagegen_assets.rb`, `scripts/verify_imagegen_assets.rb`
- Test: `scripts/verify_imagegen_assets_test.rb`
- Create: `NovaStationPinball/Resources/Assets.xcassets/AppIcon.appiconset/*`
- Create: `NovaStationPinball/Resources/Art/*.png`
- Modify: `NovaStationPinball/Game/PinballScene.swift`

**Interfaces:**
- Produces: masters et dérivés PNG nommés, hachés, inspectés et liés aux rôles runtime.

- [ ] Écrire le contrat Ruby qui échoue en absence des masters, de provenance, de dimensions/alpha/profil et en présence de SVG/PDF.
- [ ] Exporter le guide greybox et l’utiliser comme référence ImageGen pour la composition maître 4:3.
- [ ] Générer par ImageGen icon, key art, table, CRT, panneaux, batteurs, bumpers, cibles, rampes, portails, lampes, menus, HUD et créatifs Store.
- [ ] Inspecter chaque master à taille réelle ; rejeter perspective, texte ou géométrie incompatibles.
- [ ] Inscrire prompt/date/dimensions/rôle/source/SHA-256 dans le manifeste.
- [ ] Normaliser les dérivés PNG de façon reproductible et faire passer le contrat.
- [ ] Remplacer tout nœud greybox visible par un sprite raster ; conserver seulement collisions, masques et VFX procéduraux invisibles/dynamiques.
- [ ] Vérifier la correspondance pixel/art mécanique par overlay du guide.

### Task 9: Audio, haptique, Game Center et tip jar optionnels

**Files:**
- Create: `NovaStationPinball/Services/AudioEngine.swift`, `HapticsService.swift`, `GameCenterClient.swift`, `TipJarSupport.swift`
- Create: `NovaStationPinball/StoreKit/NovaStationPinball.storekit`
- Test: `NovaStationPinballTests/AudioEngineTests.swift`, `HapticsServiceTests.swift`, `GameCenterClientTests.swift`, `TipJarSupportTests.swift`

**Interfaces:**
- Produces: protocols injectables dont les implémentations nulles ne bloquent jamais une partie.

- [ ] Tester les adapters indisponibles et confirmer que gameplay/scores locaux continuent.
- [ ] Implémenter AVAudioEngine/Core Haptics/GameKit derrière protocoles.
- [ ] Tester que le catalogue contient exactement les trois tips et zéro feature gate.
- [ ] Ajouter la configuration StoreKit exclue du bundle release.
- [ ] Vérifier l’absence de dépendance réseau obligatoire.

### Task 10: Localisation, accessibilité et cycle de vie

**Files:**
- Create: `NovaStationPinball/Resources/Localizable.xcstrings`
- Create: `NovaStationPinball/Services/LifecycleCoordinator.swift`
- Test: `NovaStationPinballTests/LocalizationContractTests.swift`, `LifecycleCoordinatorTests.swift`
- Test: `NovaStationPinballUITests/AccessibilityAuditUITests.swift`

**Interfaces:**
- Produces: clés FR/EN complètes, labels VoiceOver, pause/background/restore déterministes.

- [ ] Tester que toutes les clés publiques ont FR et EN sans valeur vide ni fallback prétendu.
- [ ] Tester pause, background, interruption audio et checkpoint.
- [ ] Implémenter le cycle de vie et les labels/accessibility actions.
- [ ] Exécuter les audits UI sur les trois classes d’appareils et corriger chevauchements/contraste/safe areas.

### Task 11: ASO, support et médias déterministes

**Files:**
- Create: `fastlane/metadata/en-US/*`, `fastlane/metadata/fr-FR/*`
- Create: `NovaStationPinballUITests/StoreScreenshotUITests.swift`, `AppPreviewUITests.swift`
- Create: `scripts/app_store/generate_screenshots.rb`, `generate_app_previews.rb`, `media_contract.rb`
- Test: `scripts/app_store/media_contract_test.rb`

**Interfaces:**
- Produces: matrice locale × device × scénario pour lancement, mission, promotion, multiball, tilt, fin de partie ; manifeste daté avec révision et checksums.

- [ ] Écrire et faire échouer le contrat média sur cellules manquantes/dupliquées/étrangères/obsolètes.
- [ ] Ajouter scénarios UI déterministes et générateurs à deux locales maximum.
- [ ] Produire metadata ASO FR/EN et textes support/privacy sans email ni `mailto:`.
- [ ] Capturer screenshots et App Preview réels depuis les assets intégrés.
- [ ] Faire passer contrat média, contrat release et audit Formspree du portefeuille.

### Task 12: Validation finale exhaustive

**Files:**
- Create: `docs/validation-report.md`
- Create: `Builds/AppStore/NovaStationPinball/<run_id>/{screenshots,app_previews,logs}`

**Interfaces:**
- Produces: preuves distinctes build, tests, runtime, art, médias, performance et état Git local.

- [ ] Exécuter `release_contract`, contrat artistique, contrats médias et audit support.
- [ ] Exécuter `swift test` dans un scratch unique puis XcodeGen et build générique non signé.
- [ ] Créer, enregistrer et utiliser séquentiellement trois UDID éphémères possédés sous iOS 26.2 ; un worker, aucun `booted`.
- [ ] Exécuter tous les XCTest/UI tests sur iPhone 17 Pro Max, iPhone SE 3 et iPad Pro 13 M5.
- [ ] Capturer les six états exigés et inspecter réellement chaque image/vidéo.
- [ ] Mesurer 60 fps et, si le simulateur/appareil le permet, 120 fps ProMotion ; consigner les limites de preuve.
- [ ] Vérifier absence totale d’assets interdits, de secrets, de workflows et de changements hors repo.
- [ ] Faire une revue de code finale indépendante et corriger toute finding importante.
- [ ] Consigner branche `main`, remote absent/non muté, statut et diff exact ; ne pas commit/push sans demande.
