# Task 10 — Localisation, accessibilité et cycle de vie

Date de validation : 2026-07-22

## Résultat

- Le catalogue `Localizable.xcstrings` possède exactement 21 clés publiques, chacune avec une valeur anglaise et française explicite, non vide, marquée `translated` et différente de sa clé.
- Les trois régions accessibles du rendu 4:3 ont des labels et hints localisés. Le plateau expose des actions VoiceOver pour les deux batteurs, le lancement et la secousse; le cadre expose pause/reprise; la console annonce score, billes restantes et statut.
- `LifecycleCoordinator` combine de manière idempotente activité app, pause utilisateur et interruption audio. Il sauvegarde une fois par entrée en arrière-plan et restaure une fois au démarrage.
- `SimulationDriver` possède une barrière de pause indépendante : aucune frame, commande ou durée d’arrière-plan ne peut avancer la simulation; la reprise repart sans catch-up.
- `AppModel` possède une barrière d’entrée et d’effets optionnels dérivée du même état : lancement et secousse, directs ou VoiceOver, ne créent ni commande, ni faux statut de réussite, ni `play` audio (et donc aucun `prepare` implicite), ni haptique pendant une pause, une inactivité, l’arrière-plan ou une interruption audio. Le statut accessible reste celui du bloqueur; la reprise revient à « système prêt » et rétablit les commandes, statuts et cues normaux.
- La capture de checkpoint conserve le snapshot, les règles et un replay canonique ancré sur ce snapshot. La restauration remet le driver, efface accumulateur et commandes transitoires, puis restitue les règles.
- Aucun simulateur n’a été créé, booté, adopté, installé, lancé, arrêté ou supprimé. Aucun commit, push ou accès App Store Connect n’a été effectué. Le ledger partagé n’a pas été modifié.

## Cycle TDD observé

1. RED app : après création des XCTest, `build-for-testing` échoue exactement sur `LifecycleCoordinator` et `LifecycleCheckpointStore` absents.
2. GREEN compilation : ajout de la machine d’état, du catalogue, des surfaces VoiceOver et de l’intégration `scenePhase` / `AVAudioSession`.
3. RED SwiftPM : la nouvelle cible interne de test échoue parce que le coordinateur dépend encore de `LocalGameStore` et `PinballAudioEngine`, donc de l’app.
4. GREEN SwiftPM : injection de closures audio et conformance du store déplacée à la frontière app; 8 tests lifecycle exécutés sans CoreSimulator.
5. GREEN localisation réelle : les 2 tests de catalogue sont rattachés à la même cible SwiftPM et valident le fichier source réellement livré.
6. RED pause driver : le test dédié échoue sur `SimulationDriver.setPaused` absent.
7. GREEN pause driver : le driver ignore 30 secondes simulées en pause, puis exécute exactement un tick à la reprise sans rattrapage.
8. RED contrat Ruby : les gates attendent encore l’ancien appel direct `model.startOptionalServices()` et produisent 3 runs, 141 assertions, 2 failures après mise à jour de l’attente test.
9. GREEN contrat Ruby : le contrat vérifie maintenant `RootView -> model.start() -> startOptionalServices() + lifecycleCoordinator.start()`; 3 runs, 143 assertions, 0 failure.
10. RED revue effets : le nouveau test SwiftPM échoue à la compilation sur `LifecycleCoordinator.allowsOptionalGameplayEffects` absent.
11. GREEN revue effets : l’autorisation dérivée couvre démarrage, pause utilisateur, inactive/background et interruption audio. Trois XCTest `AppModel` à spies couvrent les chemins directs et VoiceOver, l’absence d’audio/haptique pendant l’arrêt, l’effacement à la reprise et le retour des cues; ils sont compilés dans le bundle iOS sans lancement de simulateur.
12. RED revue statut : le test de permission échoue à la compilation sur `LifecycleCoordinator.allowsGameplayInput` absent; les nouveaux asserts `AppModel` formalisent aussi le statut pause/interruption avant et après les gestes bloqués.
13. GREEN revue statut : `AppModel.apply` refuse le lot entier avant toute mutation lorsque le cycle de vie bloque le gameplay. Les tests à spies exigent désormais input vide et statut inchangé en pause/inactive/background/interruption, « système prêt » après reprise, puis statuts launch/nudge et cues inchangés sur le chemin actif.

## Fichiers créés

- `NovaStationPinball/Resources/Localizable.xcstrings`
- `NovaStationPinball/Services/LifecycleCoordinator.swift`
- `NovaStationPinballTests/LocalizationContractTests.swift`
- `NovaStationPinballTests/LifecycleCoordinatorTests.swift`
- `NovaStationPinballTests/OptionalEffectsLifecycleTests.swift`
- `NovaStationPinballTests/AppModelTestSupport.swift`
- `NovaStationPinballUITests/AccessibilityAuditUITests.swift`
- `.superpowers/sdd/task-10-report.md`

## Fichiers modifiés

- `NovaStationPinball/App/AppModel.swift`
- `NovaStationPinball/App/RootView.swift`
- `NovaStationPinball/Game/PinballScene.swift`
- `NovaStationPinball/Game/SimulationDriver.swift`
- `NovaStationPinball/Services/LocalGameStore.swift`
- `NovaStationPinballTests/AudioEngineTests.swift`
- `NovaStationPinballTests/GameCenterClientTests.swift`
- `NovaStationPinballTests/HapticsServiceTests.swift`
- `NovaStationPinballTests/SimulationDriverTests.swift`
- `NovaStationPinballTests/TipJarSupportTests.swift`
- `NovaStationPinballUITests/BootstrapUITests.swift`
- `NovaStationPinballUITests/LayoutUITests.swift`
- `Package.swift`
- `scripts/release_contract.rb`
- `scripts/release_contract_test.rb`
- `NovaStationPinball.xcodeproj/` régénéré par XcodeGen

## Contrat déterministe du cycle de vie

- L’état initial est `inactive` et donc en pause.
- `start()` est idempotent : il consomme au plus une restauration, puis applique une seule fois l’état dérivé.
- L’état dérivé est en pause si l’app n’est pas active, si l’utilisateur a demandé la pause ou si une interruption audio est en cours.
- Les événements identiques répétés ne rejouent ni callback de pause, ni `prepare`, ni `suspend` audio.
- Une interruption terminée avec `shouldResume=false` devient une pause utilisateur explicite; seule une reprise utilisateur peut la lever.
- L’entrée en arrière-plan applique la pause avant capture et sauvegarde; un événement `background` dupliqué ne recrée pas de checkpoint.
- Une nouvelle transition active vers background crée un nouvel identifiant et une nouvelle sauvegarde.
- Toute erreur de capture, lecture, restauration ou écriture est contenue dans `.failed`; elle ne réactive jamais la simulation.
- `allowsOptionalGameplayEffects` et `allowsGameplayInput` restent faux avant `start()` et valent vrai uniquement lorsque tous les bloqueurs de simulation sont levés.
- `AppModel.apply` retourne avant son `switch` lorsque l’input est interdit : aucune mutation de contrôle continu, commande, statut, audio ou haptique n’est possible. Toute transition pause/reprise remet aussi `continuousInput` à zéro et vide `pendingCommands`, ce qui empêche un état antérieur d’être rejoué tardivement.
- `SimulationDriver.setPaused` vide accumulateur, nudges, releases de plongeur et phase de release. `advance` retourne zéro tick en pause.
- `restore(snapshot:)` reconstruit `PinballSimulation` sur la même table et efface tout état de frame transitoire.

## Localisation et VoiceOver

- Les 21 clés couvrent nom, huit statuts, labels/hints du cadre et du plateau, valeur de console, et six actions.
- `LocalizationContractTests` exige l’égalité exacte entre clés publiques et clés du catalogue; une clé ajoutée sans contrat ou une locale manquante échoue.
- Les valeurs compilées ont été relues dans le produit :
  - `Nova Station Pinball.app/en.lproj/Localizable.strings`
  - `Nova Station Pinball.app/fr.lproj/Localizable.strings`
- Les deux fichiers compilés contiennent les 21 valeurs attendues; aucun fallback clé n’est utilisé.
- `SpriteView` reste masqué de VoiceOver afin d’éviter les doublons. Les overlays transparents existants restent la seule surface accessible et conservent les identifiants `art.frame.4x3`, `art.table` et `art.console`.
- `AccessibilityAuditUITests` lance EN et FR, vérifie labels et valeur console non vide, puis appelle l’audit système complet `performAccessibilityAudit()`.

## Preuves finales fraîches

### SwiftPM sans simulateur

Commande :

`rtk proxy swift test --package-path . --scratch-path /private/tmp/apps-factory/NovaStationPinball/task10-status-full/swiftpm`

- XCTest lifecycle/localisation : 13 tests, 0 failure, 0 unexpected.
- Swift Testing core : 95 tests dans 8 suites, 0 échec.
- Soak : 432000 ticks, 6.233 s.
- Total exécuté : 108 tests.

### XcodeGen et compilations génériques

- `rtk proxy xcodegen generate` : succès.
- Debug générique iOS Simulator, scratch `task10-verify-debug-20260722` : exit 0.
- Release générique iOS Simulator, scratch `task10-verify-release-20260722` : exit 0.
- `build-for-testing` générique final, scratch `task10-status-bft` : exit 0 (`TEST BUILD SUCCEEDED`), sans boot ni mutation de simulateur.
- App, bundle XCTest et bundle UI XCTest compilés chacun pour `x86_64 arm64`.
- Le produit `build-for-testing` contient les deux ressources compilées `en.lproj/Localizable.strings` et `fr.lproj/Localizable.strings`.

### Contrat Ruby

- `rtk proxy ruby scripts/release_contract_test.rb` : 3 runs, 143 assertions, 0 failures, 0 errors, 0 skips.
- `rtk proxy ruby scripts/release_contract.rb` : `release_contract: OK`.

## Preuve runtime restant à acquérir

L’audit UI réel reste volontairement **en attente** pour les trois classes demandées : iPhone compact, iPhone large et iPad. Les tests UI et les trois nouveaux XCTest `AppModel` à spies sont écrits et compilés, mais n’ont pas été exécutés sur device dans ce run. Leur logique de permission sous-jacente est exécutée sans simulateur par les 11 tests de `LifecycleCoordinator`.

La raison est bornée : aucune autorisation utilisateur directe n’est disponible pour créer/booter un simulateur éphémère, et l’autorisation système précédente a été refusée. Le pool persistant n’a pas été adopté. En conséquence, ce rapport ne prétend pas avoir validé visuellement les chevauchements, le contraste, les safe areas ou les actions VoiceOver sur ces trois appareils. Cette preuve exige une future exécution avec trois UDID exactement possédés et verrouillés.
