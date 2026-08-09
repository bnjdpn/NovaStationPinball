# Task 5 — Replays, déterminisme et soak

## Statut

DONE. Le replay est une valeur Swift 6 `Sendable`, `Codable` et `Equatable`, avec
JSON canonique, hash versionné reproductible et exécution stricte des inputs dans
l'ordre du tableau. Le soak obligatoire a réellement parcouru 432 000 ticks.

## Fichiers

- Créé : `NovaStationCore/Sources/NovaStationCore/Replay.swift`
- Créé : `NovaStationCore/Sources/NovaStationCore/StableHasher.swift`
- Créé : `NovaStationCore/Tests/NovaStationCoreTests/ReplayDeterminismTests.swift`
- Créé : `NovaStationCore/Tests/NovaStationCoreTests/SimulationSoakTests.swift`
- Créé : `.superpowers/sdd/task-5-report.md` (ce rapport requis)

## Design et interfaces

- `ReplayInput` encapsule un `PlayerInput`; `Replay` contient la version de table,
  le snapshot initial et la séquence ordonnée d'inputs.
- `Replay.stableJSON()` produit le même JSON sans `JSONEncoder` : clés et ordre
  fixes, valeurs `Double` codées par leurs 64 bits IEEE-754 en hexadécimal, et
  identifiants `UInt64` également sur 16 hexadécimaux. `init(stableJSON:)`,
  `encodedJSON()` et `decodeJSON(_:)` assurent le round-trip.
- `Replay.replay(on:)` exige la même version de table, rejoue exactement un tick
  à 240 Hz par input dans l'ordre du tableau, puis retourne `ReplayResult`
  (`snapshot`, `rules`, `hash`).
- `StableHasher` est un FNV-1a 64-bit, avec domaine, longueur des champs et
  version fixes. Le hash final porte le préfixe `nova-station-h1-`; il ne dépend
  ni de `Swift.Hasher`, ni du processus, ni de l'architecture d'exécution.

## TDD — RED puis GREEN

RED observé avant toute source de production :

```text
rtk proxy swift test --package-path . --scratch-path /private/tmp/apps-factory/NovaStationPinball/task5-replay/swiftpm --filter ReplayDeterminismTests
error: cannot find 'Replay' in scope
error: cannot find 'ReplayInput' in scope
```

GREEN ciblé après l'implémentation minimale :

```text
... --filter ReplayDeterminismTests
Test run with 1 test in 1 suite passed after 0.002 seconds.
```

Le premier essai de compilation de la source nouvelle a exposé deux erreurs de
syntaxe de chaînes et des appels statiques qualifiés manquants; elles ont été
corrigées avant le GREEN. Aucune logique de simulation existante n'a été
modifiée.

## Hash de dix replays

Les dix exécutions de la même séquence ont produit un seul hash identique :

```text
nova-station-h1-32ab4de50579238b
```

Le test vérifie aussi que le JSON canonique survit au decode/encode sans changer
et que renverser l'ordre des inputs produit un hash différent.

## Soak 432 000 ticks

Commande ciblée :

```text
rtk proxy swift test --package-path . --scratch-path /private/tmp/apps-factory/NovaStationPinball/task5-replay/swiftpm --filter SimulationSoakTests
```

Résultat : 432 000 ticks non conditionnels exécutés en `3.568527542 seconds`.
À chaque tick, le test vérifie le temps, positions et vitesses finis, les bornes
de la bille dans la table fermée, et les invariants publiquement observables de
`GameRulesState`. Le soak a été vert sans échec numérique : aucune protection
numérique supplémentaire n'a donc été ajoutée.

## Suite SwiftPM complète

```text
rtk proxy swift test --package-path . --scratch-path /private/tmp/apps-factory/NovaStationPinball/task5-replay/swiftpm
Test run with 85 tests in 7 suites passed after 3.490 seconds.
Simulation soak 432000 ticks duration: 3.488176792 seconds
```

## Auto-revue

- Le hash repose sur une représentation canonique explicite, pas sur l'ordre
  d'un dictionnaire JSON ou un hasher à clé aléatoire.
- Les valeurs non finies sont refusées avant sérialisation stable; les versions
  de table incompatibles échouent explicitement.
- Le soak réel n'est ni filtré par environnement ni raccourci et n'a pas exigé
  de changement dans le moteur numérique existant.
- Aucune dépendance externe, commit, push, accès réseau ou fichier de production
  hors du périmètre de la tâche n'a été introduit.

## Préoccupations

Pas de préoccupation bloquante. FNV-1a 64-bit est un fingerprint déterministe,
pas un hash cryptographique : il convient au contrôle de replay demandé, mais
ne doit pas devenir une primitive de sécurité ou d'anti-triche serveur sans un
hash cryptographique distinct.

## Fix après revue indépendante

### Statut

DONE. Cette section remplace les détails d'interface antérieurs : le format de
replay est maintenant `formatVersion: 2` afin de versionner explicitement la
séquence d'actions de règles.

### Findings corrigés

1. **Canonisation stricte.** `init(stableJSON:)` et `decodeJSON(_:)` utilisent
   désormais un parseur déterministe fermé au schéma, sans `JSONSerialization`.
   Il consomme les clés dans leur ordre canonique, refuse espaces, clés absentes,
   inattendues ou dupliquées, types/formes différents, hex majuscule et toute
   version différente de 2. Après parsing, le replay est re-sérialisé et doit
   être byte-for-byte égal à la source.
2. **Codable compatible.** `Replay`, `ReplayInput` et les représentations
   internes de snapshot/input encodent les `Double` par les mêmes chaînes hex
   IEEE-754 de 16 caractères que le JSON stable. Le `JSONEncoder`/`JSONDecoder`
   standard conservent donc la même valeur, sans prétendre que son ordre de clés
   est le contrat de bytes canoniques.
3. **Hasher versionné.** `StableHasher(version:)` est désormais throwable et
   conserve sa version d'instance dans son domaine et son préfixe. Version 1 et
   2 donnent respectivement `nova-station-h1-` et `nova-station-h2-`; 0 produit
   `StableHasherError.invalidVersion(0)`.
4. **Règles de replay non neutres.** `ReplayInput` conserve son initialiseur
   historique et ajoute `actions: [ReplayRuleAction]`. Les actions sont typées,
   ordonnées et explicitement appliquées : score/bonus, multiplicateurs,
   multiball/ball-save, tilt/drain, start/complete/fail mission et abort de
   ressource. La complétion de mission reçoit un `MissionID` typé et résout le
   trigger depuis le catalogue, sans mapping libre de `GameEvent.name`.
5. **Ordre physique.** Le test compare les snapshots finaux : une nudge au
   premier tick n'a pas la même position finale qu'exactement la même nudge au
   second tick.
6. **Soak actif.** Le soak utilise gravité, quatre rails, deux flippers, un
   plunger, un bumper et un senseur. Il applique périodiquement flippers,
   plunger et nudge; il score, accumule le bonus et termine les neuf missions de
   clearance sans drainer la partie. Les compteurs finaux exigent inputs actifs,
   événements physiques et transitions de règles. L'invariant reconnaît bien
   qu'une mission resource-driven active peut avoir `missionTicksRemaining == nil`.

### TDD — RED / GREEN

RED observé avant la production corrigée :

```text
rtk proxy swift test --package-path . --scratch-path /private/tmp/apps-factory/NovaStationPinball/task5-replay/swiftpm --filter ReplayDeterminismTests
error: argument passed to call that takes no arguments (StableHasher(version:))
error: cannot find 'StableHasherError' in scope
error: extra argument 'actions' in call (ReplayInput)
```

GREEN ciblé :

```text
... --filter ReplayDeterminismTests
Test run with 6 tests in 1 suite passed after 0.002 seconds.
```

GREEN soak actif :

```text
... --filter SimulationSoakTests
Simulation soak 432000 ticks duration: 5.938663958 seconds
Test run with 1 test in 1 suite passed after 5.939 seconds.
```

### Hash et suite finale

Les dix replays identiques ont produit :

```text
nova-station-h1-2a3faf04746fe733
```

Suite SwiftPM complète après correctif :

```text
rtk proxy swift test --package-path . --scratch-path /private/tmp/apps-factory/NovaStationPinball/task5-replay/swiftpm
Simulation soak 432000 ticks duration: 5.992324042 seconds
Test run with 90 tests in 7 suites passed after 5.994 seconds.
```

### Auto-revue et préoccupations

- Aucun `Swift.Hasher`, `JSONEncoder` comme preuve canonique, ou
  `JSONSerialization` n'est employé par l'API stable.
- Le parseur fermé rejette les doublons au point syntaxique plutôt que de laisser
  un dictionnaire les écraser.
- Aucune protection numérique de simulation n'a été ajoutée : le soak actif est
  passé après son RED d'interface sans défaut numérique à corriger.
- FNV-1a reste un fingerprint déterministe non cryptographique; il ne doit pas
  être utilisé comme primitive d'authenticité ou d'anti-triche.
