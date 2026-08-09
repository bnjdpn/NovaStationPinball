# Task 7b — intégration runtime autoritative

Date : 22 juillet 2026

Statut : `DONE`

La remédiation runtime critique et la reprise des sept findings de revue sont
implémentées. La table versionnée, les règles, les missions, les billes
physiques, le replay, les checkpoints, la scène et le HUD passent par une seule
`GameSession` déterministe. Les tests iOS ont été compilés sur destination
générique, sans démarrer de simulateur.

## Livrables

- `TableVisualLayout` est le contrat pixel autoritatif 2048×1536 pour les 70 %
  gauches de la composition ImageGen. `NovaStationTable` v721 en dérive les
  ancres du lanceur, des batteurs, des trois bumpers, de la banque de quatre
  cibles et des mécaniques visibles. Chaque descripteur résout son vrai
  collider, capteur, cible, batteur ou lanceur.
- Les 17 anciens capteurs artificiels de mission sont supprimés. Chaque mission
  requiert une séquence ordonnée de bumpers, cibles, rampes, retours, rollovers,
  portails et voies réellement visibles. Chacune des 17 branches repart de
  `GameSession()` puis `startNewGame()` et s'achève uniquement par des
  `PlayerInput` passés à `GameSession.step`, sans restore, snapshot préparé,
  événement injecté, process ou fixture; une mission ne démarre que pour
  l'habilitation exactement active. Les trois commandes mission sont armées par
  trois forces de lanceur distinctes afin qu'un passage incident ne les valide pas.
- `GameSession` est le réducteur autoritatif unique entre la simulation 240 Hz
  et `GameRulesState`. Il gère score, bonus, multiplicateurs, énergie de station,
  sélection/démarrage/acquittement de mission, échec, promotions, extra-ball,
  multibille physique à trois billes, drains individuels, ball save de 10 s,
  respawn, tilt et game over.
- `SimulationDriver` agrège les événements et effets de tous les ticks de
  rattrapage sans perte ni double consommation, restaure snapshot et règles, et
  purge les commandes transitoires lors d'une pause, restauration ou nouvelle
  partie.
- Le replay canonique v3 contient uniquement les `PlayerInput` ordonnés de
  chaque tick. Son ancre contient désormais l'état mécanique complet : snapshot,
  angles et vitesses des batteurs, charge du lanceur, accumulation et état de
  tilt, règles, phase, prochain identifiant de bille et commande de voie armée.
  `ActiveCheckpoint` v3 conserve aussi l'ancre et les inputs d'enregistrement.
  Une restauration mi-lanceur, mi-course de batteur et sous le seuil de tilt
  poursuit 360 ticks avec égalité de chaque frame, état, JSON et hash.
- `PinballScene` consomme exclusivement la vraie session et la table de
  production. Toutes les billes sont rendues par identifiant dans un
  dictionnaire de `SKSpriteNode`; les overlays médias décoratifs ont été
  supprimés.
- Le plateau, les menus, la bille, les mécanismes et le fond du HUD utilisent
  les PNG ImageGen intégrés. Il n'existe aucun `SKShapeNode`, `SKLabelNode`, SVG,
  PDF vectoriel ou illustration CSS dans le rendu du jeu.
- L'écran launch utilise `key-art.png` et l'écran game over
  `store-creative.png`; leurs SHA-256 sont différents et les deux nœuds sont
  mutuellement exclusifs selon la phase.
- `RasterHUDRenderer` compose le texte dynamique dans une texture bitmap au
  dessus du master ImageGen `hud-overlay`, avec score, billes restantes et en
  jeu, mission, habilitation, multiplicateurs, énergie, tilt et phase.
- `AppModel` consomme les vraies règles de session, lance une partie depuis
  l'écran initial ou game over, sauvegarde le score local avant la soumission
  Game Center et utilise `GameCompletionGate` pour garantir une seule tentative
  par partie.
- `GameSessionCaptureFixture` et `captureFixture` sont entièrement supprimés.
  Les six `MediaScenario` utilisent les mêmes scripts publics de production et
  seulement `startNewGame`/`step(PlayerInput)` pour atteindre mission,
  promotion, multibille, tilt, drains, respawns et game over.
- Ces scripts restent strictement dans le domaine d'entrée de l'app : traction
  du lanceur entre 0 et 1, nudge vertical toujours nul, swipe horizontal entre
  0,4 et 1,2 ou impulsion d'accessibilité 0,35. Le retour au lanceur n'utilise
  aucun nudge : il suit la gravité, les outlanes, le drain et le respawn. Les
  tirs à rebond du couloir de lancement (dont la multibille et l'énergie de
  station) utilisent un unique swipe horizontal légal dès le relâchement.
- Le catalogue FR/EN contient 65 clés explicites, dont les 17 missions, les neuf
  habilitations et tous les états HUD.

## Reprise TDD de la revue indépendante

1. Le contrat géométrique échoue avant `TableVisualLayout`, puis valide les
   ancres réelles et les tirs légaux de toutes les mécaniques génériques.
2. Les missions échouent avec les triggers directs, puis 17 playthroughs de
   branches passent avec objectifs physiques et habilitation exacte.
3. Les tests replay échouent avant l'enregistrement des ticks, puis dix replays
   identiques et la continuation de checkpoint passent.
4. Le premier soak `startNewGame` ne touchait rien : le lanceur exact chevauchait
   le mur effectif et son corridor se refermait. La géométrie corrigée atteint
   bumpers, capteurs et drains sans téléportation.
5. Le soak durci révèle `isGameOver == true` avec `ballsInPlay == 1`; le reducer
   met désormais exactement zéro bille en jeu au dernier drain.
6. Le full gate renvoie d'abord exit 1 : trois échecs XCTest média, masqués par
   le résumé Swift Testing core. Les scénarios sont réécrits avec les scripts
   de contrôles ordinaires; la suite complète retourne ensuite réellement exit
   0 sans fixture ni état préparé.
7. Le contrat raster échoue avant la distinction launch/game-over, puis passe
   avec deux dérivés ImageGen existants et distincts.
8. Une revue isolée révèle qu'un ancien retour utilisait un nudge vertical et
   que six tirs attendaient trop longtemps avant leur premier swipe. Le retour
   repose désormais sur la physique seule et les six trajectoires utilisent un
   swipe horizontal d'ouverture réellement produit par `TouchInterpreter`.

## Preuves fraîches

- Deux suites SwiftPM complètes reconstruites dans deux scratchs neufs : exit 0
  à chaque fois, 22 XCTest + 112 tests Swift Testing, 0 échec.
- Soak de production : 432 000 ticks après une mission Orbital Wake entièrement
  terminée depuis `startNewGame`, uniquement par `PlayerInput`; bumpers, capteurs,
  score, drains, respawns et game over exercés, avec cohérence snapshot/règles
  contrôlée toutes les 120 frames.
- Replay/checkpoint : cinq tests ciblés, dont dix replays identiques, un ancien
  format rejeté et la continuation transitoire exacte sur 360 ticks.
- ImageGen : 27 runs, 220 assertions, 0 échec ; vérificateur direct : 7 masters
  et 17 dérivés.
- Release : 4 runs, 343 assertions, 0 échec ; `release_contract: OK`.
- Médias : 11 runs, 77 assertions, 0 échec.
- Nouveau manifeste média final : 36 cellules valides, 36 `pending`, sous
  `Builds/AppStore/NovaStationPinball/task7b-review-final5-20260722/`.
- `xcodegen generate` : succès.
- Build générique Debug sans signature : `BUILD SUCCEEDED`.
- Build générique Release sans signature : `BUILD SUCCEEDED`.
- Build générique `build-for-testing` : `TEST BUILD SUCCEEDED`; app, tests
  unitaires et tests UI compilés pour arm64 et x86_64.

## Limites conservées honnêtement

- Aucun simulateur concret n'a été créé, booté, adopté, ciblé ou nettoyé.
- Les `AppModelRuntimeIntegrationTests` sont compilés mais non exécutés sur iOS.
- Les 36 cellules média restent `pending`; aucune capture ou vidéo factice n'a
  été produite et aucune revue visuelle réelle n'est revendiquée.
- Aucun commit, push, upload, signature ou mutation App Store Connect n'a été
  effectué.
