# Task 7 — Greybox SpriteKit et contrôles tactiles

## Statut

Terminé sans commit ni push. La racine SwiftUI, la scène SpriteKit fonctionnelle, l'interprétation tactile, le driver fixe à 240 Hz, le guide raster reproductible et les tests de ratio sont en place.

## Implémentation

- `AppModel` sépare désormais explicitement l'état continu (`ContinuousPlayerInput`) des commandes one-shot (`SimulationCommand`) et transmet chaque lot une seule fois au driver.
- `RootView` compose un cadre complet 4:3 letterboxé, table 70 % / console 30 %, sans recadrage sur les deux formats demandés.
- `PinballScene` fait tourner `NovaStationCore` via `SimulationDriver`, affiche balle, bumpers, cibles, flippers et lanceur, et marque chaque forme SpriteKit `greybox.*` ainsi que l'écran `NOT FINAL ART`.
- `TouchInterpreter.events(for:in:)` couvre les zones basses invisibles gauche/droite, le lanceur glisser-relâcher, le nudge horizontal court dans la zone haute et l'annulation d'un geste exclusif par un second toucher.
- `SimulationDriver.advance(elapsed:input:)` accumule à `PinballSimulation.fixedTimeStep` (240 Hz), conserve les commandes pendant un zéro-tick, applique le nudge une seule fois au premier tick et transforme une release en charge puis relâchement sur deux ticks déterministes.
- Aucun SVG ni PDF n'a été introduit. Les formes SwiftUI/SpriteKit restantes appartiennent explicitement au greybox, jamais à l'art final.

## TDD RED → GREEN

### Contrôles et driver

- RED : compilation attendue en échec, types `TouchInterpreter` et `SimulationDriver` absents.
  - Reçu : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/xcresult/task7-red.xcresult`
- GREEN : 7/7 tests ciblés passent (4 interpréteur + 3 driver).
  - Reçu : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/xcresult/task7-input-green-2.xcresult`

### Layout

- RED : le test UI frais échoue comme attendu car `greybox.frame.4x3` n'existe pas.
  - Reçu : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/xcresult/task7-layout-red-2.xcresult`
- GREEN final iPhone : 16/16 tests passent sur iPhone 17 Pro Max, iOS 26.2.
  - Reçu : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/xcresult/task7-iphone-final-green.xcresult`
- GREEN final iPad après correction de centrage, sans attente de capture : 17/17 tests passent sur iPad Pro 13-inch (M5), iOS 26.2.
  - Reçu : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/xcresult/task7-ipad-postfix-final.xcresult`
  - Résultat `xcresulttool` : `Passed`, 17 passés, 0 échec, 0 ignoré.

Le test UI mesure les cadres accessibles réels : ratio global 4:3, largeurs table/console 70/30, hauteurs identiques et inclusion complète dans la fenêtre.

### Revue corrective — entrées impulsionnelles et batch multitouch

- RED post-review, avant modification production : `xcodebuild build-for-testing` échoue avec exit 65 sur les nouvelles interfaces `SimulationInputBatch` et `takeSimulationInput` absentes.
  - DerivedData : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/review-red-derived`
- GREEN ciblé : 12/12 tests passent, soit 7 driver/intégration et 5 interpréteur.
  - Reçu : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/xcresult/task7-review-targeted-green.xcresult`
- Cas couverts : release avant update avec force exacte, nudge conservé si zéro tick, nudge jamais répété sur quatre pas de rattrapage, résultats identiques à 480/240/120/60 Hz, séparation AppModel continu/one-shot et deux permutations simultanées du même batch multitouch.
- La normalisation interne du batch trie les échantillons et pré-analyse les débuts simultanés : aucune permutation ne peut amorcer le lanceur avant l'annulation multitouch.

### Reçus finaux post-sources

- iPhone 17 Pro Max iOS 26.2 : 22/22, 0 échec, 0 ignoré.
  - Reçu : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/xcresult/task7-review-iphone-final.xcresult`
- iPad Pro 13-inch (M5) iOS 26.2 : 22/22, 0 échec, 0 ignoré.
  - Reçu : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/xcresult/task7-review-ipad-final.xcresult`
- Dernier mtime des sources de la correction : `2026-07-22T02:48:21+0200`. Reçu/captures iPhone puis iPad sont tous postérieurs.

## Build

- `xcodegen generate` : réussi.
- Build générique iOS Simulator non signé : `** BUILD SUCCEEDED **`.
  - DerivedData : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/generic-final-derived`

## Guide raster

- Fichier : `NovaStationPinball/Resources/Art/greybox-table-guide.png`
- Taille : 2048 × 1536, donc exactement 4:3.
- SHA-256 avant/après une nouvelle exécution de `scripts/export_greybox_guide.swift` : `33dbfa07d289b2e1011d138fdd12383f494e9b15e4855ad54f2d5f67e00d88fd`.
- Le guide marque la table, la zone mécanique, la zone sûre, les bumpers, les cibles, les flippers, le lanceur, la console et l'état `GREYBOX / NOT FINAL ART`.

## Captures inspectées

Les preuves finales post-sources qui remplacent les captures initiales sont :

- iPhone 17 Pro Max, iOS 26.2 : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/review-iphone-postsource-final.png`
  - 2868 × 1320 ; SHA-256 `1203bf83e33c228a706c2e0df51a4f2366541fab6a0b6861ce597b8525c254bd` ; mtime `2026-07-22T02:51:21+0200`.
- iPad Pro 13-inch (M5), iOS 26.2 : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/review-ipad-postsource-final.png`
  - 2752 × 2064 ; SHA-256 `0b17a36c79f235dee0c0a0590583693484ff479f1c1277d27849f02db485f8ed` ; mtime `2026-07-22T02:58:01+0200`.

Captures historiques antérieures à la revue :

- iPhone 17 Pro Max, iOS 26.2 : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/iphone-17-pro-max-landscape-final.png`
  - 2868 × 1320 ; SHA-256 `7a3d61adadd666939c968e8271a9a86214dacefb5874bef1d7c5de5ce67810ac`.
- iPad Pro 13-inch (M5), iOS 26.2 : `/private/tmp/apps-factory/NovaStationPinball/task7-greybox/ipad-pro-13-m5-landscape-final.png`
  - 2752 × 2064 ; SHA-256 `be4e01ee6a66a6d194df4900e07cd22b0cf15ed046875fc8eb4c50ee3c60c6c5`.

Inspection visuelle : scène entière visible, cadre 4:3, séparation table/console conforme, formes mécaniques visibles, labels greybox lisibles et absence de crop. Les captures `simctl` ont seulement été pivotées de 90° avec `sips` pour normaliser l'orientation physique du framebuffer ; aucun contenu n'a été retouché.

## Isolation et nettoyage

- iPhone possédé : `27E30781-6D33-4191-8E1A-245FE8ECBA60` (`NovaTask7-iPhone-20260722`) — supprimé et absence vérifiée.
- iPad possédé : `2C052FAE-8AAC-4E13-A472-3AD02E02A352` (`NovaTask7-iPad-20260722`) — supprimé et absence vérifiée.
- iPhone post-review : `283294B3-A44C-4089-A5D4-C2C2D4AB8383` (`NovaTask7Review-iPhone-20260722`) — supprimé et absence vérifiée.
- iPad post-review : `B09E9380-CC9B-4209-8042-A3DFC7C69E34` (`NovaTask7Review-iPad-20260722`) — supprimé et absence vérifiée.
- Aucun ciblage `booted`, par nom, ni nettoyage global n'a été utilisé.

## Auto-review

- Le redimensionnement SpriteKit utilise `.aspectFit`, ce qui conserve toute la table dans sa colonne.
- Le conteneur transparent de la composition fixe sa taille intrinsèque complète avant centrage ; la console ne peut plus déborder sur iPad.
- La temporisation temporaire utilisée uniquement pour les captures live a été retirée avant le reçu final.
- Le raster est reproductible et toutes les primitives visuelles produites sont explicitement du greybox.
- Préoccupation restante : aucune pour le périmètre Task 7.
