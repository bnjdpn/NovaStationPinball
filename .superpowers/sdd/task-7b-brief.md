### Task 7b: Intégration runtime complète moteur ↔ règles ↔ rendu

**Cause:** la revue Task 11 a prouvé que le moteur déterministe, les règles et les fixtures média existaient séparément, mais que la partie ordinaire ne transmettait aucun `SimulationFrame.events` aux règles et que la table runtime ne contenait que les limites et trois bumpers. Les fonctionnalités annoncées n'étaient donc pas atteignables.

**Interfaces attendues:**
- une définition de table Nova versionnée, pure et testable, alignée sur le guide raster/ImageGen ;
- une session de jeu déterministe qui possède l'état de règles, consomme chaque frame/tick et retourne les mutations de snapshot/effets de présentation nécessaires ;
- `PinballScene` transmet chaque frame à la session et rend toutes les billes ; `AppModel` expose le vrai score, la vraie mission, l'habilitation et la fin de partie ;
- les scénarios média utilisent des états que le runtime réel sait atteindre, sans sprites décoratifs prétendant être une mécanique absente.

**Acceptation TDD:**
- [ ] Remplacer la mini-table runtime par une table complète : rails/arcs/rampe, drain ouvert, 3 bumpers, banques de cibles, voies/senseurs de mission, portail, bonus, multiplicateurs, extra-bille et multibille. Chaque organe interactif doit correspondre à une zone visible du raster et avoir un identifiant stable.
- [ ] Prouver par tests de table que chaque catégorie de tir et chaque trigger des 17 missions est porté par un capteur/cible atteignable dans le playfield, sans géométrie hors limites ni collision bloquant le drain.
- [ ] Consommer `stepsExecuted` et chaque `GameEvent` une fois exactement : score de table, bonus, multiplicateurs, sélection/démarrage/complétion/échec de mission, ressource rechargeable/épuisement, tilt.
- [ ] Rendre les 17 missions atteignables à leur habilitation (routes alternatives déterministes), les neuf habilitations atteignables, et exiger l'acquittement d'un résultat avant la mission suivante.
- [ ] Implémenter réellement sauvetage 10 s, trois billes, drains, extra-bille, multibille à trois billes, retrait individuel des billes, respawn au lanceur et fin de partie. Réinitialiser la physique/tilt au changement de bille sans perdre score/règles.
- [ ] Enregistrer le high score local avant la soumission Game Center best-effort exactement une fois à la fin ; une erreur externe ne doit pas bloquer une nouvelle partie.
- [ ] Rendre dynamiquement toutes les billes avec les PNG ImageGen et un HUD fonctionnel sur la console ImageGen (score, billes, mission/habilitation, multiplicateur/tilt/fin), sans SVG/PDF/CSS ni forme générique. Tout texte dynamique doit être rasterisé dans une texture sur le panneau ImageGen, pas dessiné comme illustration autonome.
- [ ] Ajouter un vrai état lancement/nouvelle partie et un vrai état fin de partie ; les commandes tactiles et VoiceOver doivent respecter ces états.
- [ ] Supprimer les overlays média décoratifs qui fabriquent portail/lampes/billes. Les six scénarios doivent piloter la vraie session/rendu ; un test doit échouer si `-ui-testing` est le seul chemin capable de produire mission, promotion, multibille, tilt ou game-over.
- [ ] Conserver déterminisme, checkpoints, replays, pause/interruption, exact-once input, art raster et ratio 70/30. Ajouter tests d'intégration et soak de session couvrant partie complète et tous les systèmes.
- [ ] Exécuter SwiftPM complet, contrats Ruby/ImageGen/media, XcodeGen et builds génériques Debug/Release/build-for-testing. Aucun simulateur tant que l'autorisation directe manque ; consigner la preuve runtime restante sans la fabriquer.

**Contraintes:** préserver tout travail non committé ; aucun commit/push/ASC ; aucun asset externe ou identité de la référence ; ne pas éditer le ledger partagé.
