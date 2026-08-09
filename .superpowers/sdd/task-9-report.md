# Task 9 — Audio, haptique, Game Center et tip jar optionnels

## Résultat

- Quatre interfaces injectables isolent AVAudioEngine, Core Haptics, GameKit et StoreKit 2.
- Chaque domaine possède une implémentation nulle sans erreur, attente ni effet sur la simulation.
- `AppModel` émet seulement les cues audio/haptiques après avoir conservé la commande déterministe. L’authentification Game Center démarre une seule fois depuis la tâche de cycle de vie SwiftUI, sans bloquer le jeu.
- Le catalogue contient exactement `tip.cafe`, `tip.merci` et `tip.soutien`. Les trois produits sont consommables, facultatifs et ne débloquent aucun contenu.
- La configuration StoreKit de développement est référencée par le scheme Xcode mais exclue des sources et du bundle applicatif.
- L’adapter GameKit est activé par l’entitlement `com.apple.developer.game-center`. Son presenter par défaut résout la fenêtre de la scène active; le seam injectable reste disponible pour les tests.
- Un résultat terminé est trié et sauvegardé localement avant toute soumission Game Center. Une entrée écartée du top local n’est pas soumise; l’échec ou l’absence d’authentification ne touche jamais le score local.
- Aucun client `URLSession` ou `NWConnection` n’est introduit.

## Cycle TDD

1. RED initial: `build-for-testing` échoue sur les types attendus absents (`PinballAudioEngine`, `PinballAudioCue`, `PinballHapticsService`, `PinballHapticCue`).
2. GREEN compilation: ajout minimal des protocoles/adapters, injection `AppModel`, catalogue et configuration StoreKit.
3. Premier XCTest réel: erreur de test `await` dans un autoclosure XCTest; les valeurs asynchrones sont matérialisées avant assertion.
4. Deuxième XCTest réel: les tests tentaient de lire le repo hôte depuis la sandbox iOS. Le contrat est replacé à la bonne frontière: comportement offline dans XCTest, structure JSON/projet/réseau dans le contrat Ruby.
5. RED entitlement: le contrat Ruby échoue car l’entitlement Game Center manque; ajout de la clé puis GREEN.
6. RED remediation Game Center: les tests de compilation échouent sur l’absence de presenter de production, du démarrage lifecycle et du chemin local-first de fin de partie.
7. GREEN remediation: presenter UIKit sur scène active, authentification idempotente, hook `.task` SwiftUI et `recordCompletedGame` qui persiste avant la soumission best-effort.

## Fichiers

Créés:

- `NovaStationPinball/Services/AudioEngine.swift`
- `NovaStationPinball/Services/HapticsService.swift`
- `NovaStationPinball/Services/GameCenterClient.swift`
- `NovaStationPinball/Services/TipJarSupport.swift`
- `NovaStationPinball/StoreKit/NovaStationPinball.storekit`
- `NovaStationPinballTests/AudioEngineTests.swift`
- `NovaStationPinballTests/HapticsServiceTests.swift`
- `NovaStationPinballTests/GameCenterClientTests.swift`
- `NovaStationPinballTests/TipJarSupportTests.swift`

Modifiés:

- `NovaStationPinball/App/AppModel.swift`
- `NovaStationPinball/App/RootView.swift`
- `NovaStationPinball/Services/LocalGameStore.swift`
- `NovaStationPinball/NovaStationPinball.entitlements`
- `project.yml`
- `NovaStationPinball.xcodeproj/` (régénéré par XcodeGen)
- `scripts/release_contract.rb`
- `scripts/release_contract_test.rb`

## Preuves fraîches

- SwiftPM core:
  - commande: `rtk proxy swift test --package-path . --scratch-path /private/tmp/apps-factory/NovaStationPinball/task9-gc-final-20260722/swiftpm`
  - résultat: 95 tests, 0 échec; soak déterministe 432000 ticks en 6.106 s.
- Tests app, révision courante:
  - `xcodebuild ... -destination 'generic/platform=iOS Simulator' ... build-for-testing`: succès; les nouveaux tests Game Center compilent pour arm64 et x86_64.
  - aucune exécution XCTest sur simulateur pour cette remediation: la création ou le boot d’un device aurait muté l’état CoreSimulator, action explicitement exclue de ce run. La preuve XCTest éphémère de la révision courante reste donc bloquée en attente d’une autorisation directe de l’utilisateur.
  - le reçu historique `/private/tmp/apps-factory/NovaStationPinball/task9-tests-20260722/xcresult/task9-services-final.xcresult` prouve 30/30 tests avant cette remediation uniquement; il n’est pas présenté comme preuve du code courant.
- Contrat Ruby:
  - `rtk proxy ruby scripts/release_contract_test.rb`: 3 runs, 135 assertions, 0 échec.
  - `rtk proxy ruby scripts/release_contract.rb`: `release_contract: OK`.
  - lane exacte `rtk proxy /opt/homebrew/bin/ruby -S bundle exec fastlane release_contract`: succès, `release_contract: OK`.
- Build:
  - `xcodebuild ... -configuration Release -destination 'generic/platform=iOS Simulator' ... build`: succès.
  - produit: `/private/tmp/apps-factory/NovaStationPinball/task9-gc-release-20260722/DerivedData/Build/Products/Release-iphonesimulator/Nova Station Pinball.app`.
  - recherche `*.storekit` dans ce bundle: aucun résultat.
- Configuration:
  - JSON StoreKit lu avec succès; exactement trois IDs attendus, tous `Consumable`.
  - scheme généré contient `StoreKitConfigurationFileReference` vers le fichier de développement.
  - recherche `URLSession|NWConnection` dans les quatre services: aucun résultat.

## Hors périmètre

- Aucun commit, push, remote ou mutation App Store Connect.
- Aucun changement du ledger partagé `.superpowers/sdd/progress.md`.
- Aucun simulateur créé, booté, installé, lancé ou nettoyé pendant la remediation Game Center.
