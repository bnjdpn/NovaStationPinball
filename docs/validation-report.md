# Nova Station Pinball — rapport de validation locale

Date : 22 juillet 2026
Candidat média : `task12-final-v12-20260722`
Empreinte source : `cf8338a13e03bf500dc17dbcca134e3a141cd2c7ccac47f3509a83a6d1ac48f2`

## Résultat

Le jeu, ses contrôles, sa physique déterministe et sa surface média App Store sont validés localement. Aucune mutation App Store Connect, aucun commit et aucun push n'ont été effectués.

Le run v12 contient 36 screenshots PNG et 6 App Previews MOV : 2 langues × 3 appareils × 6 scénarios. Le contrat strict retourne `OK (36 cells, 0 pending)` et contrôle les dimensions, checksums, timestamps, provenance raw, UDID, langue, handshake, transformation attendue par appareil (`transpose=cclock` sur les iPhone, `transpose=clock` sur l'iPad), couverture visuelle, orientation PNG et caractéristiques vidéo Apple.

## Preuves fonctionnelles

- Swift Package : 112 tests Swift Testing, plus les groupes XCTest, tous verts.
- Xcode runtime : 73/73 tests sur iPhone 17 Pro Max, 73/73 sur iPhone SE 3 et 73/73 sur iPad Pro 13 pouces M5, soit 219/219.
- Layout et accessibilité après masquage du chrome système : 3/3 tests UI iPad, incluant les audits VoiceOver EN/FR.
- Contrat média Ruby final : 39 tests, 319 assertions, 0 échec.
- Réencodeur de provenance : 13 tests, 55 assertions, 0 échec, incluant les rejets de raw échangé, run/langue/appareil/UDID/handshake/xctestrun/trim incohérents et manifeste symbolique.
- Build iOS Simulator générique non signé : réussi.

Les résultats Xcode complets sont conservés sous `/private/tmp/apps-factory/NovaStationPinball/task12-final-20260722/runtime/` et le contrôle final layout/accessibilité sous `/private/tmp/apps-factory/NovaStationPinball/task12-final-v8-20260722/statusbar-green/LayoutAccessibility.xcresult`.

## QA visuelle et localisation

Les visuels sont des rasters ImageGen intégrés au jeu ; aucun SVG ni habillage CSS de substitution n'est utilisé. Les six planches de contrôle sont :

- `Builds/AppStore/NovaStationPinball/task12-final-v12-20260722/logs/qa-en-US-iphone-17-pro-max.png`
- `Builds/AppStore/NovaStationPinball/task12-final-v12-20260722/logs/qa-en-US-iphone-se-3.png`
- `Builds/AppStore/NovaStationPinball/task12-final-v12-20260722/logs/qa-en-US-ipad-pro-13-m5.png`
- `Builds/AppStore/NovaStationPinball/task12-final-v12-20260722/logs/qa-fr-FR-iphone-17-pro-max.png`
- `Builds/AppStore/NovaStationPinball/task12-final-v12-20260722/logs/qa-fr-FR-iphone-se-3.png`
- `Builds/AppStore/NovaStationPinball/task12-final-v12-20260722/logs/qa-fr-FR-ipad-pro-13-m5.png`

Les six planches ont été inspectées séparément. Le rendu final est en paysage et à l'endroit, sans étirement, cadre incomplet ni chrome système. Le HUD anglais affiche notamment `BALLS`, `LIVE`, `CLEARANCE`, `SYSTEM READY`; le HUD français affiche `BILLES`, `ACTIVES`, `HABILITATION`, `SYSTÈME PRÊT`. Les screenshots proviennent de frames déterministes à 0,5 / 4,5 / 8,5 / 12,5 / 16,5 / 20,5 secondes des previews exactes. Le run v12 réencode les six captures raw fraîches du run v8 après validation cryptographique et structurelle du manifeste source, du SHA raw réel, des six cellules, de l'UDID exact, de la langue, du token xctestrun, du handshake, du trim et de la géométrie. Aucun UDID de provenance n'est synthétisé à partir de la location courante.

## Performance

La simulation conserve les mêmes résultats aux cadences d'affichage testées 60, 120, 240 et 480 Hz. Le rendu local Simulator et les médias à 30 fps sont validés. Cette preuve ne mesure pas un affichage physique ProMotion à 120 fps : une confirmation matérielle avec trace de performance reste nécessaire pour revendiquer 120 fps réels sur appareil.

## Incidents écartés

- v4 : attachments XCTest tournés/incomplets — refusés.
- v5 : raws portrait scalés sans rotation — refusés.
- v6 : orientation corrigée mais locale EN non réellement appliquée — refusé.
- v7 : langues correctes mais chrome système iPad encore visible — refusé.
- v8 : recapture complète après correction du chrome et des langues ; raws frais conservés, mais inversion détectée ensuite sur les deux formats iPhone — médias dérivés refusés.
- v9 : réencodage avec nouveau verrou d'empreinte source, inversion iPhone encore présente — refusé.
- v10 : orientation SE corrigée mais iPhone 17 Pro Max encore inversé — refusé.
- v11 : transformation et visuels corrects, mais liaison entre raws et manifeste source insuffisamment forte — remplacé.
- v12 : même source raw validée, provenance renforcée en TDD, contrat strict et nouvelle inspection séparée des six planches — seul run retenu.
