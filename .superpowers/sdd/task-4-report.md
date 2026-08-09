# Task 4 — Règles, missions et neuf habilitations

## Statut

**DONE**

## Fichiers modifiés

- Créé `NovaStationCore/Sources/NovaStationCore/GameRules.swift`
- Créé `NovaStationCore/Sources/NovaStationCore/MissionCatalog.swift`
- Créé `NovaStationCore/Sources/NovaStationCore/ScoreEngine.swift`
- Créé `NovaStationCore/Tests/NovaStationCoreTests/GameRulesTests.swift`
- Créé `NovaStationCore/Tests/NovaStationCoreTests/MissionCatalogTests.swift`
- Créé `docs/reference-behavior-matrix.md`
- Créé ce rapport `/.superpowers/sdd/task-4-report.md`

## Implémentation

- `GameRulesState` gère trois billes régulières, bonus et multiplicateurs
  plafonnés, extra-billes, multibille, fenêtre de ball-save de 2 400 ticks,
  tilt, drains et fin de partie.
- `ScoreEngine` produit des `ScoreAward` déterministes, normalise les entrées
  négatives et sature à 999 999 999 sans overflow.
- `MissionCatalog` contient neuf missions et neuf habilitations Nova originales,
  avec un trigger unique, des scores et un timeout fixe par mission.
- Une mission active ne se termine que sur son trigger; timeout, tilt et drain
  de la dernière bille active la font échouer. Sa complétion attribue exactement
  l'habilitation suivante.
- La matrice documente triggers, scores, transitions et tolérances, sans texte,
  rang, visuel ni son de la référence.

## Séquence TDD RED/GREEN

1. **RED — règles de partie et score.**
   `GameRulesTests.swift` a été écrit avant tout fichier de production. La
   commande ciblée a échoué sur les symboles attendus absents :
   `cannot find 'GameRulesState' in scope` et
   `cannot find 'ScoreEngine' in scope`.
2. **GREEN — règles de partie et score.**
   Après création de `GameRules.swift` et `ScoreEngine.swift`, les 10 tests
   `GameRulesTests` initiaux ont passé. Deux corrections de test ont été faites
   pendant ce cycle : les appels mutateurs ont été sortis de `#expect`, puis la
   vérification du tilt a été placée avant le drain (le tilt est bien limité à
   la bille courante).
3. **RED — catalogue, missions et promotions.**
   `MissionCatalogTests.swift`, les tests de missions et la table de plafonds
   ont été ajoutés avant la production. La commande ciblée a échoué comme
   attendu avec `cannot find 'MissionCatalog' in scope`,
   `cannot find 'ClearanceLevel' in scope` et les méthodes de mission absentes.
   Le test du drain de mission a ensuite été ajouté et le RED a été réobservé.
4. **GREEN — catalogue, missions et promotions.**
   Après création de `MissionCatalog.swift` et extension minimale de
   `GameRules.swift`, les 26 tests ciblés des deux suites ont passé.

## Commandes et résultats exacts

Scratch unique :
`/private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm`

| Commande | Résultat |
| --- | --- |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter GameRulesTests` | Première tentative sandbox : bloquée avant compilation par `error opening '/Users/benjamin/.cache/clang/ModuleCache/...': Operation not permitted`. |
| Même commande, hors sandbox autorisé | RED attendu : `GameRulesState` et `ScoreEngine` absents. |
| Même commande après production (et correction de la syntaxe des assertions) | GREEN : 10 tests `GameRulesTests` passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter 'GameRulesTests\|MissionCatalogTests'` | RED attendu : `MissionCatalog`, `MissionID`, `ClearanceLevel` et opérations de mission absents. |
| Même commande après production | GREEN : 26 tests dans `GameRulesTests` et `MissionCatalogTests` passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm` | GREEN : 72 tests dans 5 suites passés. |
| `rtk proxy git -C NovaStationPinball diff --check` | Sortie vide, code 0. |
| `rtk proxy git -C NovaStationPinball status --short` | Arbre initial entièrement non suivi (`## No commits yet on main`); aucun commit, push ou remote effectué. |

## Auto-revue

- Les neuf `MissionID` sont couverts individuellement dans
  `MissionCatalogTests` et parcourus par le test table-driven des promotions.
- Les plafonds de score sont couverts par une table de trois cas, dont les deux
  bords de saturation.
- Les plafonds de bonus, multiplicateurs, extra-billes, ball-save, multibille,
  tilt, drain, start/complete/fail/timeout mission sont couverts par tests.
- Les types publics sont `Sendable`, `Codable` et `Equatable` lorsque leur état
  est persistant ou comparé.
- Les fichiers de référence C++ ont servi uniquement à étudier des catégories
  de mécanique et non à copier des noms, textes, ressources ou sons.

## Préoccupations

Aucune pour cette task. La première exécution SwiftPM nécessitait l'accès hors
sandbox au cache de modules Swift; toutes les validations finales ont ensuite
été vertes. Le dépôt étant une initialisation sans commit, `git diff --check`
ne peut inspecter les fichiers non suivis; les sept fichiers créés ont donc été
relus explicitement avant ce rapport.

## Fix après revue

### Finding corrigé

La revue indépendante a identifié un écart critique : le catalogue initial ne
contenait que 9 `MissionID` alors que la surface comportementale de référence
comporte 17 sélections. Le catalogue Nova contient désormais 17 missions
originales et conserve exactement les 9 `ClearanceLevel` existants.

Les huit ajouts — Harbor Ember, Echo Spire, Lantern Route, Rift Containment,
Aurora Quarantine, Vault Signal, Phase Tide et Station Tempest — sont des noms,
triggers et textes Nova originaux. Ils couvrent les catégories de jeu
supplémentaires (enchaînement cible/porte, répétition de pare-chocs, balayage de
rollovers, couloirs externes, fanions, collecteurs, rebonds et tempête de
cibles), avec les scores de sélection 4×10 000, 9×20 000 et 4×30 000. Les routes
alternatives réemploient les paliers existants et n'introduisent pas de dixième
habilitation.

### RED puis GREEN

1. **RED.** Huit tests isolés ont été ajoutés dans `MissionCatalogTests`, un
   test explicite `MissionCatalog.all.count == 17`, et les assertions
   table-driven des 17 IDs, triggers, scores de sélection, scores de complétion
   et tolérances. Avant production, `MissionCatalogTests` a échoué comme attendu
   avec `type 'MissionID' has no member 'harborEmber'` (et les sept autres IDs
   absents).
2. **GREEN.** `MissionCatalog.swift` a reçu les huit `MissionID` et définitions,
   ainsi que les scores de complétion et de sélection alignés sur la matrice.
   `GameRulesTests` conserve la promotion déterministe des neuf habilitations
   en parcourant le chemin canonique de neuf missions; les huit autres sont des
   routes alternatives de leurs paliers respectifs.

### Fichiers du correctif

- Modifié `NovaStationCore/Sources/NovaStationCore/MissionCatalog.swift`
- Modifié `NovaStationCore/Tests/NovaStationCoreTests/GameRulesTests.swift`
- Modifié `NovaStationCore/Tests/NovaStationCoreTests/MissionCatalogTests.swift`
- Modifié `docs/reference-behavior-matrix.md`
- Append de ce rapport uniquement; aucun autre fichier Task 4, commit, push ou
  remote n'a été modifié.

### Commandes et sorties

Scratch conservé :
`/private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm`

| Commande | Sortie |
| --- | --- |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter MissionCatalogTests` avant production | RED : compilation échouée sur les 8 `MissionID` absents, notamment `harborEmber`. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter 'GameRulesTests\|MissionCatalogTests'` après production | GREEN : 34 tests, 2 suites, passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter GameRulesTests` | GREEN : 16 tests, 1 suite, passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter MissionCatalogTests` | GREEN : 18 tests, 1 suite, passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm` | GREEN : 80 tests, 5 suites, passés. |
| `rtk proxy git -C NovaStationPinball diff --check` | Sortie vide, code 0. |

### Auto-revue

- `MissionID.allCases` et `MissionCatalog.all` comptent exactement 17 entrées;
  chaque ID résout vers une définition identique, et chaque trigger est unique.
- Les tableaux de tests verrouillent les 17 scores de sélection, complétions et
  tolérances documentées; les neuf habilitations restent exactes.
- La matrice publique décrit chaque mapping par catégorie de mécanique, sans
  reprendre de nom, rang, texte, image ou son de la référence.
- Aucun problème restant identifié.

## Second fix timing proof

### Finding corrigé

La précédente matrice affichait des tolérances Nova sans baseline vérifiable, ce
qui rendait l'exigence ±5 % non auditable. L'analyse de l'oracle local
`/private/tmp/nova-spacecadet-control.cpp` a établi que les 17 contrôleurs de
mission sélectionnables passent par des collisions et états de sous-objectif,
sans timeout global de mission. Les appels temporisés présents dans le fichier
visent des lumières, collecteurs ou retours UI, pas la durée d'une mission.

Provenance examinée : les contrôleurs de mission sont aux lignes 2912, 2998,
3061, 3155, 3229, 3372, 3415, 3710, 3759, 3822, 3873, 3944, 3987, 4121,
4368, 4424 et 4477; `MissionControl` ne traite `ControlTimerExpired` que pour
le flux de barre de carburant/texte aux lignes 2308-2336. Les branches des
contrôleurs ne contiennent pas de limite globale de temps.

### Modèle et preuve

- `MissionTiming.eventDriven` remplace les 17 valeurs de timeout inventées :
  baseline, timing Nova, delta ticks et delta pourcentage sont explicitement
  `nil`/N/A pour ce mode non mesurable.
- `MissionTiming.fixedWindow(baselineTicks:novaTicks:)` fournit la voie typée
  pour une future fenêtre réellement comparable. `ticks(seconds:)` convertit
  exactement à 240 Hz; `deltaTicks`, `deltaPercentage` et
  `isWithinFivePercent` exposent publiquement la preuve ±5 %.
- `GameRulesState` conserve une mission événementielle active après une durée
  arbitraire; elle échoue seulement par les transitions documentées (tilt,
  drain de la dernière bille active ou échec explicite).
- La matrice publique documente chacune des 17 missions avec provenance de
  ligne non identitaire, baseline, timing Nova, delta et pourcentage. Tous les
  cas événementiels sont N/A de façon explicite, sans nombre fabriqué.

### RED puis GREEN

1. **RED.** Les tests ont d'abord demandé `MissionDefinition.timing`, les
   valeurs publiques de baseline/delta et `MissionTiming`. Le test ciblé a
   échoué comme attendu : `value of type 'MissionDefinition' has no member
   'timing'` et `cannot find 'MissionTiming' in scope`.
2. **GREEN.** Après ajout du modèle typé dans `MissionCatalog.swift`, retrait
   des timeouts inventés et adaptation de `GameRules.swift`, les tests prouvent
   les 17 baselines événementielles, l'absence de deadline artificielle et les
   trois cas table-driven de conversion 240 Hz à 0 %, +5 % et -5 %.

### Fichiers modifiés

- Modifié `NovaStationCore/Sources/NovaStationCore/MissionCatalog.swift`
- Modifié `NovaStationCore/Sources/NovaStationCore/GameRules.swift`
- Modifié `NovaStationCore/Tests/NovaStationCoreTests/GameRulesTests.swift`
- Modifié `NovaStationCore/Tests/NovaStationCoreTests/MissionCatalogTests.swift`
- Modifié `docs/reference-behavior-matrix.md`
- Append de ce rapport; aucun commit, push ou remote.

### Commandes et sorties

Scratch conservé :
`/private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm`

| Commande | Sortie |
| --- | --- |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter 'GameRulesTests\|MissionCatalogTests'` avant production | RED : compilation échouée sur `MissionDefinition.timing` et `MissionTiming` absents. |
| Même commande après production | GREEN : 36 tests, 2 suites, passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter GameRulesTests` | GREEN : 16 tests, 1 suite, passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter MissionCatalogTests` | GREEN : 20 tests, 1 suite, passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm` | GREEN : 82 tests, 5 suites, passés. |
| `rtk proxy git -C NovaStationPinball diff --check` | Sortie vide, code 0. |

### Auto-revue

- Les 17 définitions portent toutes `MissionTiming.eventDriven`; tests et
  matrice confirment baseline/delta/pourcentage N/A sans seuil fictif.
- Les calculs numériques futurs sont déterministes en ticks 240 Hz et bornés
  par `abs(deltaPercentage) <= 5` dans les cas table-driven.
- Aucun texte, nom, rang, image ou son de référence n'a été introduit.
- Aucun problème restant identifié.

## Third fix resource countdown

### Finding corrigé

L'absence de timeout global ne signifiait pas l'absence d'échec temporel : le
contrôleur de mission de l'oracle abandonne la mission lorsqu'un compte à rebours
de ressource partagé se vide. `MissionControl` traite
`TLightGroupCountdownEnded` aux lignes 2308-2318 de
`/private/tmp/nova-spacecadet-control.cpp`; cette ressource est alimentée dans
les flux 1636-1735 et réinitialisée aux lignes 2617-2626. Sa valeur étant
variable et rechargeable, il n'existe pas de baseline numérique honnête à
transposer pour les 17 missions.

### Modèle et preuve

- `MissionTiming.resourceDriven(abortTrigger: .stationPowerDepleted)` remplace
  le libellé trop imprécis `eventDriven` sur les 17 définitions. Les valeurs de
  baseline, timing Nova, delta ticks et pourcentage restent explicitement N/A.
- `GameRulesState.applyMissionAbort(_:)` échoue une mission active uniquement
  lorsque son déclencheur de ressource correspond; les appels pendant une
  mission inactive, terminée ou avec un autre déclencheur sont ignorés.
- Le modèle `fixedWindow` demeure disponible et ses trois cas à 240 Hz (0 %,
  +5 %, -5 %) restent couverts par test table-driven.

### RED puis GREEN

1. **RED.** Les tests ont d'abord requis
   `MissionTiming.resourceDriven`, `MissionTiming.abortTrigger` et
   `GameRulesState.applyMissionAbort(_:)`. La compilation a échoué comme
   attendu : `type 'MissionTiming' has no member 'resourceDriven'`,
   `GameRulesState` n'a pas de membre `applyMissionAbort`, et
   `MissionDefinition` n'a pas de membre `timing.abortTrigger`.
2. **GREEN.** Après ajout du déclencheur typé et de la transition d'abandon,
   les tests ciblés confirment les 17 ressources partageant le même abort, la
   poursuite au-delà d'un nombre arbitraire de ticks, et le refus de chaque
   déclencheur invalide.

### Fichiers modifiés

- Modifié `NovaStationCore/Sources/NovaStationCore/MissionCatalog.swift`
- Modifié `NovaStationCore/Sources/NovaStationCore/GameRules.swift`
- Modifié `NovaStationCore/Tests/NovaStationCoreTests/GameRulesTests.swift`
- Modifié `NovaStationCore/Tests/NovaStationCoreTests/MissionCatalogTests.swift`
- Modifié `docs/reference-behavior-matrix.md`
- Append de ce rapport; aucun commit, push ou remote.

### Commandes et sorties

Scratch conservé :
`/private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm`

| Commande | Sortie |
| --- | --- |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter 'GameRulesTests\|MissionCatalogTests'` avant production | RED : symboles `resourceDriven`, `abortTrigger` et `applyMissionAbort` absents. |
| Même commande après production | GREEN : 37 tests, 2 suites, passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter GameRulesTests` | GREEN : 17 tests, 1 suite, passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm --filter MissionCatalogTests` | GREEN : 20 tests, 1 suite, passés. |
| `rtk proxy swift test --package-path NovaStationPinball --scratch-path /private/tmp/apps-factory/NovaStationPinball/task4-rules/swiftpm` | GREEN : 83 tests, 5 suites, passés. |
| `rtk proxy git -C NovaStationPinball diff --check` | Sortie vide, code 0. |

### Auto-revue

- Chaque mission porte un déclencheur de déplétion explicitement vérifiable.
- Le compte à rebours partagé est représenté comme une ressource rechargeable,
  sans baseline numérique inventée.
- Aucun texte, nom, rang, image ou son de référence n'a été introduit.
- Aucun problème restant identifié.
