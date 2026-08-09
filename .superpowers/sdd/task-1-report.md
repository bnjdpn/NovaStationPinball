# Task 1 — Repo autonome et contrats exécutables

## Résultat

Terminé. Le dépôt possède le socle XcodeGen, Swift Package, Fastlane, support,
confidentialité et contrat de release demandé. Aucun code de gameplay ou art de
jeu n'a été ajouté.

## Fichiers ajoutés

- Configuration et documentation : `AGENTS.md`, `.gitignore`, `README.md`,
  `project.yml`, `Package.swift`, `Gemfile`.
- App : `NovaStationPinball/Resources/PrivacyInfo.xcprivacy` et
  `NovaStationPinball/NovaStationPinball.entitlements`.
- Contrat : `scripts/release_contract.rb` et
  `scripts/release_contract_test.rb`.
- Fastlane : `fastlane/Fastfile`, `fastlane/Appfile` et
  `fastlane/release_config.json`.
- Support : `docs/index.html` et `docs/privacy.html`.
- Généré par XcodeGen : `NovaStationPinball.xcodeproj`.

## Preuve RED

Le test a été écrit avant tout fichier de production puis exécuté :

```sh
rtk proxy ruby scripts/release_contract_test.rb
```

Échec attendu, après correction d'une assertion Minitest incompatible avec la
version Ruby locale :

```text
1) Failure:
ReleaseContractTest#test_repository_contract_is_complete [...:20]:
missing required file: .../NovaStationPinball/AGENTS.md

1 runs, 1 assertions, 1 failures, 0 errors, 0 skips
```

Ce RED prouve que le contrat détectait bien le scaffold absent. Le premier essai
avait produit une erreur de harness (`assert_path_exists` indisponible), qui a
été corrigée avant de poursuivre afin que l'échec porte bien sur l'exigence.

## Preuve GREEN

```sh
rtk proxy ruby scripts/release_contract_test.rb
rtk proxy xcodegen generate
rtk proxy ruby scripts/release_contract.rb
```

Résultats :

```text
1 runs, 63 assertions, 0 failures, 0 errors, 0 skips
Created project at .../NovaStationPinball/NovaStationPinball.xcodeproj
release_contract: OK
```

Le test couvre le bundle `com.bnjdpn.NovaStationPinball`, iOS 17, Swift 6,
familles 1/2, paysage iPhone/iPad, cibles XcodeGen, produit SwiftPM
`NovaStationCore`, FR/EN, les trois tips, Formspree, l'absence de workflow et
toutes les lanes Fastlane obligatoires.

## Commandes et contrôles

```sh
rtk proxy ruby scripts/release_contract_test.rb
rtk proxy xcodegen generate
rtk proxy git status --short --branch
rtk proxy git diff --check
rtk proxy ruby scripts/release_contract.rb
```

La branche est `main` sans commit initial. Aucun remote, ASC, commit ou push
n'a été appelé. Le statut ne contient que les fichiers de NovaStationPinball ;
aucun autre dépôt n'a été modifié.

## Auto-revue

- `project.yml` déclare exclusivement l'app et les deux bundles de tests, iOS
  17, Swift 6, les familles iPhone/iPad et les deux orientations paysage.
- Le manifest de confidentialité déclare zéro tracking et zéro donnée collectée.
- La configuration de release ne contient que les trois dons consommables,
  tous non fonctionnels pour le coeur gratuit, avec les locales `en-US` et
  `fr-FR`.
- Les lanes Fastlane sont des stubs sûrs : aucune mutation ASC, archive,
  signature, upload ou soumission ne peut être déclenchée par ce lot.
- La page publique utilise le endpoint Formspree partagé et n'expose ni email
  ni lien `mailto:`. Aucun dossier `.github/workflows` n'existe.

## Concerns

- `NovaStationCore` est déclaré comme produit SwiftPM mais son implémentation
  est volontairement différée aux lots de simulation ; aucun `swift test` ou
  build iOS n'a été lancé car le brief de ce lot exige seulement le contrat
  Ruby et la génération XcodeGen, sans sources de gameplay.
- La politique App Preview annonce la génération future requise pour un jeu,
  mais le générateur et les médias sont hors périmètre de ce scaffold.

---

## Correctif reviewer — sources compilables et orientations plist

### RED ajouté avant l'implémentation

Le test Ruby a été étendu avant toute source Swift de production pour exiger :

- un target et un test target SwiftPM réels, avec leurs sources minimales ;
- une entrée SwiftUI `@main` et des bootstraps unit/UI test non vides ;
- les deux orientations sous forme de tableaux YAML ;
- les surfaces publiques et metadata support sans adresse email ni `mailto:`.

Commande :

```sh
rtk proxy ruby scripts/release_contract_test.rb
```

RED observé :

```text
1) Failure:
ReleaseContractTest#test_repository_contract_is_complete [...:21]:
missing required file: .../NovaStationPinball/App/NovaStationPinballApp.swift

1 runs, 9 assertions, 1 failures, 0 errors, 0 skips
```

L'échec porte donc bien sur le bootstrap requis absent, et non sur une erreur
de harness.

### Implémentation minimale

- `Package.swift` déclare maintenant `NovaStationCore` avec un path explicite
  et `NovaStationCoreTests`.
- `NovaStationCore/Sources/NovaStationCore/NovaStationCore.swift` expose
  seulement un marqueur de module ; son test `Testing` vérifie ce marqueur.
- `NovaStationPinball/App/NovaStationPinballApp.swift` contient l'entrée
  SwiftUI `@main` minimale ; les targets XCTest et UI XCTest ont chacun un
  bootstrap non vide.
- `project.yml` emploie des tableaux YAML pour les orientations iPhone et iPad
  et déclare les chemins de sources des deux bundles de test.
- Les metadata `en-US`/`fr-FR` contiennent l'URL de support Formspree sans
  contact public direct.
- Le plan Task 7 marque désormais
  `NovaStationPinball/App/NovaStationPinballApp.swift` comme **Modify** ; les
  nouveaux `RootView.swift` et `AppModel.swift` restent **Create**.

### GREEN et preuves d'exécution isolées

```sh
rtk proxy ruby scripts/release_contract_test.rb
rtk proxy swift test --package-path . --scratch-path /private/tmp/apps-factory/NovaStationPinball/task1-fix-20260721T123000Z/swiftpm
rtk proxy xcodegen generate
rtk proxy xcodebuild -project NovaStationPinball.xcodeproj -scheme NovaStationPinball -destination 'generic/platform=iOS Simulator' -derivedDataPath '/private/tmp/apps-factory/NovaStationPinball/task1-fix-20260721T123000Z/DerivedData' CODE_SIGNING_ALLOWED=NO build
rtk proxy ruby scripts/release_contract.rb
rtk proxy plutil -extract UISupportedInterfaceOrientations xml1 -o - NovaStationPinball/Info.plist
rtk proxy plutil -extract 'UISupportedInterfaceOrientations~ipad' xml1 -o - NovaStationPinball/Info.plist
```

Résultats :

- Contrat Ruby : `1 runs, 103 assertions, 0 failures, 0 errors, 0 skips`.
- SwiftPM : compilation complète et `moduleNameIsStable()` passé (1 test
  `Testing`).
- XcodeGen : projet généré avec succès.
- Build iOS générique, non signé : succès (`CODE_SIGNING_ALLOWED=NO`), avec
  DerivedData isolé dans le scratch du correctif.
- Contrat autonome : `release_contract: OK`.
- Les deux extractions `plutil` montrent explicitement `<array>` avec
  `UIInterfaceOrientationLandscapeLeft` et
  `UIInterfaceOrientationLandscapeRight`, jamais une chaîne unique.

Le build a émis des avertissements Xcode concernant des profils de provisioning
locaux malformés, mais aucun échec : la cible simulateur était non signée et la
commande a terminé avec succès.

### Auto-revue du correctif

- Aucune source ajoutée ne contient de règle, physique, table, asset ou art de
  gameplay : les fichiers sont des bootstraps compilables uniquement.
- Le contrat inspecte maintenant les sources non vides, les paths XcodeGen, les
  tableaux d'orientation, les metadata FR/EN et les contacts publics.
- Aucun workflow GitHub, remote, opération ASC, commit ou push n'a été lancé.
- `rtk proxy git diff --check` est propre ; le statut est toujours le dépôt
  initial non committé sur `main`.

### Dépendance inter-tâche

Le générateur App Preview et les médias ne sont volontairement pas ajoutés ici :
ils appartiennent explicitement à **Task 11**. Cette étape rend le scaffold
compilable mais ne prétend pas que l'app est prête pour l'App Store.
