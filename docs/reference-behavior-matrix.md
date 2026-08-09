# Matrice comportementale — Nova Station Pinball

Cette matrice définit les règles déterministes de Nova Station Pinball. Les
libellés, missions, triggers et récompenses ci-dessous sont propres à Nova; elle
ne réemploie aucun texte, rang, visuel ou son d'une table de référence.

| Système Nova | Trigger | Score | Transition déterministe | Tolérance / plafond |
| --- | --- | ---: | --- | --- |
| Partie | nouvelle partie | 0 | `ballsRemaining = 3`, une bille en jeu, multiplicateurs à 1 | exactement 3 billes régulières |
| Impact de table | `awardTableScore(baseScore:)` | `baseScore × scoreMultiplier` | ajoute un `ScoreAward` | multiplicateur de score 1× à 4×; score plafonné à 999 999 999 |
| Banques de bonus | `addBonusUnit()` | 0 immédiatement | augmente la banque de 1 | 20 unités maximum |
| Multiplicateur de bonus | `increaseBonusMultiplier()` | 0 immédiatement | augmente la valeur de banque | 1× à 5× |
| Drain normal | `drainBall()` avec une seule bille | `bonusUnits × 1 000 × bonusMultiplier` | remet bonus et multiplicateurs à leur base, consomme une bille régulière | pas de bonus si tilt; fin après le troisième drain non protégé |
| Extra-bille | `awardExtraBall()` | 0 | ajoute une bille de remplacement au prochain drain | 2 extra-billes en réserve maximum |
| Multibille | `activateMultiball()` | 0 | passe de 1 à 3 billes actives | non cumulable; chaque drain retire une bille avant le drain régulier |
| Sauvetage de bille | `activateBallSave()` | 0 | le prochain drain relance la bille | fenêtre exacte de 2 400 ticks (10 s à 240 Hz), consommée au premier drain |
| Tilt | `tilt()` | 0 | désactive score et sauvetage, fait échouer la mission active | le drain de la bille tilted ne verse aucun bonus |
| Échec de mission | `failMission()`, `applyMissionAbort(.stationPowerDepleted)`, tilt ou drain de la dernière bille active | 0 | `active(id) → failed(id)` | aucune habilitation n'est attribuée |
| Validation de résultat | `acknowledgeMissionResult()` | 0 | `completed/failed → idle` | nécessaire avant la sélection suivante |

## Catalogue de missions et habilitations

Les contrôleurs examinés combinent collisions et une ressource rechargeable.
Le countdown du bargraph appelle la fin de mission dans l'oracle local
`control.cpp:L2308-L2318`; la ressource est alimentée par les événements de
couloir `L1636-L1735` et réinitialisée au lancement `L2617-L2626`. Son état de
départ et ses recharges variant avec le jeu, aucune baseline numérique fixe
n'est mesurable. La table transmet donc un trigger Nova stable au moteur de
règles quand la ressource est épuisée. Chaque mission ne peut démarrer que si
l'habilitation requise correspond exactement à l'habilitation active; seul son
trigger de complétion est accepté. Les entrées partageant un palier sont des
routes alternatives vers la même habilitation — elles n'ajoutent jamais un
dixième niveau.

`MissionTiming.resourceDriven(abortTrigger: .stationPowerDepleted)` encode ce
cas : baseline, durée Nova, delta et pourcentage sont `N/A` parce que la
ressource est rechargeable et variable. Lorsqu'une future mission possède une
fenêtre comparable, `MissionTiming.fixedWindow` conserve les deux valeurs en
ticks à 240 Hz et expose `deltaTicks`, `deltaPercentage` et la vérification
`isWithinFivePercent`.

| Mission Nova | Catégorie de tir | Habilitation requise | Trigger de complétion | Score sélection | Score complétion | Provenance comportementale | Baseline | Timing Nova | Abort Nova | Delta | Écart |
| --- | --- | --- | --- | ---: | ---: | --- | --- | --- | --- | --- | --- |
| Orbital Wake | chaîne de pare-chocs | aucune | `sensor:orbital-wake` | 10 000 | 500 000 | contrôleur de collision `control.cpp:L3710-L3754`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Relay Bloom | passages de rampe | `dockKey` | `sensor:relay-bloom` | 10 000 | 500 000 | contrôleur de collision `control.cpp:L3372-L3408`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Cargo Drift | trio de couloirs de retour | `relayKey` | `sensor:cargo-drift` | 10 000 | 500 000 | contrôleur de collision `control.cpp:L3822-L3866`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Prism Survey | grille de cibles | `cargoKey` | `sensor:prism-survey` | 10 000 | 750 000 | contrôleur de collision `control.cpp:L3987-L4054`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Ion Choir | banque de spots vers éjecteur | `prismKey` | `sensor:ion-choir` | 20 000 | 1 000 000 | contrôleur de collision `control.cpp:L4424-L4472`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Dusk Courier | pare-chocs puis poche | `ionKey` | `sensor:dusk-courier` | 20 000 | 1 000 000 | contrôleur de collision `control.cpp:L2998-L3059`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Helix Latch | banque de risques vers collecteur | `transitKey` | `sensor:helix-latch` | 20 000 | 1 000 000 | contrôleur de collision `control.cpp:L4368-L4418`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Polar Vane | balayage large de cibles | `shieldKey` | `sensor:polar-vane` | 20 000 | 750 000 | contrôleur de collision `control.cpp:L3061-L3152`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Nova Crown | finale de pare-chocs | `commandKey` | `sensor:nova-crown` | 20 000 | 750 000 | contrôleur de collision `control.cpp:L2912-L2943`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Harbor Ember | cibles puis porte d'éjection | `relayKey` | `sensor:ember-harbor` | 20 000 | 750 000 | contrôleur de collision `control.cpp:L3873-L3940`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Echo Spire | répétition de pare-chocs | `prismKey` | `sensor:echo-spire` | 20 000 | 1 250 000 | contrôleur de collision `control.cpp:L3944-L3981`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Lantern Route | balayage de rollovers | `transitKey` | `sensor:lantern-route` | 20 000 | 1 250 000 | contrôleur de collision `control.cpp:L3759-L3816`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Rift Containment | chaîne de couloirs externes | `shieldKey` | `sensor:rift-containment` | 20 000 | 1 250 000 | contrôleur de collision `control.cpp:L3229-L3268`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Aurora Quarantine | rythme de fanions | `commandKey` | `sensor:aurora-quarantine` | 30 000 | 1 750 000 | contrôleur de collision `control.cpp:L3155-L3224`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Vault Signal | route de collecteurs | `commandKey` | `sensor:vault-signal` | 30 000 | 1 500 000 | contrôleur de collision `control.cpp:L4121-L4149`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Phase Tide | course de rebonds | `commandKey` | `sensor:phase-tide` | 30 000 | 2 000 000 | contrôleur de collision `control.cpp:L4477-L4516`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |
| Station Tempest | tempête de cibles | `commandKey` | `sensor:station-tempest` | 30 000 | 5 000 000 | contrôleur de collision `control.cpp:L3415-L3460`; countdown partagé `L2308-L2318`; recharge `L1636-L1735` | ressource rechargeable, état variable, N/A | `resourceDriven` | `stationPowerDepleted → failed` | N/A | N/A, ressource non fixe |

Les neuf habilitations, dans leur ordre stable de persistance, sont :
`dockKey`, `relayKey`, `cargoKey`, `prismKey`, `ionKey`, `transitKey`,
`shieldKey`, `commandKey` et `novaKey`.
