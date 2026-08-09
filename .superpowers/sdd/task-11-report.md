# Task 11 — Remédiation ASO, support et médias déterministes

Date : 22 juillet 2026

Statut : `REMEDIATED_WITH_RUNTIME_CAPTURE_PENDING`

Les six refus initiaux et les deux findings critiques de la contre-revue ont
été corrigés et verrouillés par tests. La matrice de
production reste volontairement à 36 cellules `pending` : cette remédiation n’a
utilisé, créé, booté, arrêté, effacé ou supprimé aucun simulateur, et n’a
effectué ni commit, ni push, ni mutation App Store Connect.

## Remédiations livrées

### Handshake explicite avant App Preview

Le protocole app/UI-test/générateur est isolé par token sous
`Library/Caches/NovaStationMediaHandshake/<token>/` :

1. le générateur exécute `build-for-testing`, copie le `.xctestrun` dans le
   scratch exact locale/appareil, y injecte le token, puis lance
   `test-without-building` sur l’UDID loué ;
2. l’app prépare son dossier et écrit `ready` ;
3. le générateur attend `ready`, démarre le PID exact de `recordVideo`, vérifie
   que ce PID est vivant et que son fichier régulier non symbolique est non vide
   puis en croissance, et écrit seulement alors `recording` ;
4. l’app attend `recording`, écrit `started` et commence alors seulement la
   timeline de jeu ;
5. après exactement 24 secondes de séquence, l’app écrit `complete` ;
6. le générateur attend `complete`, arrête uniquement le PID qu’il possède et
   attend le PID XCTest exact.

Le token doit être un hexadécimal minuscule de 32 caractères, la configuration
reste impossible sans `-ui-testing`, et les dossiers/protocoles symboliques sont
refusés. Le générateur interroge seulement le conteneur de l’app sur l’UDID exact
loué et tolère le délai normal entre lancement XCTest et disponibilité de ce
conteneur.

L’export shell autour de `xcodebuild` a été supprimé. La clé
`NOVA_MEDIA_HANDSHAKE_TOKEN` est injectée dans `EnvironmentVariables`,
`EnvironmentVariablesEnabled` et `TestingEnvironmentVariables` de l’unique
cible `NovaStationPinballUITests`. Les placeholders `__TESTROOT__` sont figés
vers les produits du build source avant la copie. Toute cible absente ou
dupliquée, clé étrangère, source/destination symbolique ou sortie hors du scratch
de l’exécution est refusée.

Le pré-roll n’utilise aucune constante : l’origine est horodatée avec l’horloge
monotone lors du premier contenu non vide du recorder, puis l’instant `started`
est observé avec la même horloge. La différence, arrondie à la milliseconde, est
la valeur exacte passée à `ffmpeg -ss`, persistée dans
`capture_trim_offset_seconds` sur les six segments du preview et validée entre
0 et 45 secondes. Les valeurs absentes, textuelles, hors fenêtre ou
incohérentes entre segments sont rejetées.

### Encodage conforme App Preview Apple

La référence autoritative est la page
[App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications).
Le pipeline `ffmpeg` produit :

- H.264 High Profile, niveau 4.0, progressif, `yuv420p` ;
- 30 fps CFR ;
- vidéo CBR 11 Mbit/s, dans la plage Apple 10–12 Mbit/s ;
- durée produit exacte de 24 secondes, dans la plage Apple 15–30 secondes ;
- AAC-LC stéréo à 48 kHz, cible 256 kbit/s ;
- dimensions paysage Apple exactes : 1920×886 pour iPhone 17 Pro Max,
  1334×750 pour iPhone SE 3 et 1600×1200 pour iPad Pro 13 M5.

Le validateur `ffprobe` refuse notamment JSON ou nombres invalides, stream
dupliqué/désactivé, HEVC, profil ou niveau H.264 incorrect, mauvais format de
pixel, entrelacement, débit vidéo hors plage, mauvais codec/profil/débit audio,
canaux ou fréquence incorrects, mauvaise résolution, durée ou cadence.

Un encodage réel de 24 secondes, sans simulateur, a été produit puis sondé :
1334×750, 24.0 s, 30 fps, H.264 High niveau 4.0, progressif `yuv420p`,
10 944 795 bit/s vidéo, AAC-LC stéréo 48 kHz et 240 087 bit/s audio. Le débit
audio mesuré est accepté dans une tolérance de payload de ±10 % autour de la
cible 256 kbit/s.

### Confidentialité UserDefaults

`PrivacyInfo.xcprivacy` déclare désormais
`NSPrivacyAccessedAPICategoryUserDefaults` avec la raison requise `CA92.1`.
Le contrat release vérifie la catégorie, la raison exacte et leur association.

### Texte public exact

Les textes promotionnels FR/EN annoncent maintenant les **17 missions** et les
neuf promotions, sans la formulation erronée « six mission states » et sans
marque concurrente :

- EN : `Master one complete retro-futuristic table: 17 original missions, nine
  promotions, multiball and responsive two-thumb controls, offline and
  ad-free.`
- FR : `Maîtrisez une table rétrofuturiste complète : 17 missions originales,
  neuf promotions, multibille et contrôles réactifs, hors ligne et sans
  publicité.`

### Pool fixe, UDID exacts et isolation

Les générateurs ne reçoivent plus trois UUID libres. Ils exigent un
`execution_id`, la configuration du pool fixe et les trois leases possédés par
l’exécution. Sont validés avant chaque `xcodebuild` :

- runtime exact `com.apple.CoreSimulator.SimRuntime.iOS-26-2` ;
- types exacts iPhone 17 Pro Max, iPhone SE 3 et iPad Pro 13 M5 ;
- correspondance appareil/rôle/type/runtime/UDID ;
- chemin de lock exact `<lock_root>/<device_id>.lock`, régulier et non
  symbolique ;
- schéma de lock AppsFactory, app `nova-station-pinball`, execution ID, device
  ID, UDID, token et PID propriétaire encore vivant ;
- contenu du lock inchangé juste avant chaque invocation Xcode.

Les destinations utilisent uniquement
`platform=iOS Simulator,id=<UDID exact>`. Aucun fallback `booted`, sélection par
nom, création/suppression de device ou nettoyage global n’existe. Scratch,
xcresult et intermédiaires sont isolés sous
`/private/tmp/apps-factory/NovaStationPinball/<execution_id>/...`.

### Matrice et assets physiques conservés

La matrice garde exactement 36 cellules : 2 locales × 3 appareils × 6
scénarios (`launch`, `mission`, `promotion`, `multiball`, `tilt`, `game-over`).
Les scripts continuent à capturer les vrais écrans et la vraie timeline de jeu
avec les assets raster ImageGen `final5`; aucun SVG, PDF ou dessin CSS n’a été
introduit.

Le manifeste de préparation frais est :

`Builds/AppStore/NovaStationPinball/task11-review-remediation-final-pending/logs/media-manifest.json`

Il porte l’empreinte source
`521f2c7faa121e9284003883480404269f7a3c47fe5e040955aa36d5f5fcf2e7`, contient
36 cellules uniques, 36 statuts `pending` et les 36 clés d’offset explicitement
à `null`. Le mode `--allow-pending` ne crée
jamais de preuve release ; le contrat strict continuera à échouer jusqu’aux
captures réelles.

## TDD et cas négatifs

Les cycles RED/GREEN ont couvert l’absence initiale de l’encodage, du handshake,
du modèle de pool, du parser `ffprobe`, du fingerprint sémantique, de la raison
PrivacyInfo et des nouvelles gardes release. Deux régressions supplémentaires
ont été reproduites en RED puis corrigées : attente du conteneur app avant le
handshake et refus d’un dossier de protocole symbolique.

La contre-revue a produit un nouveau RED précis : 22 runs, 190 assertions,
4 failures et 0 error pour les méthodes build/test séparées, le configurateur
`.xctestrun`, la readiness recorder et son ordre avant `recording`. Le contrat
release a simultanément échoué sur la nouvelle garde. Après le premier GREEN,
un second cycle RED a verrouillé l’impossibilité de sortir du scratch. Un
troisième cycle RED a couvert l’offset de pré-roll : trois failures sur timing
monotone variable, persistance manifest et validation des offsets.

`media_contract_test.rb` verrouille notamment :

- dimensions, durée, fps, codec, profil, niveau, pixel format et progressif ;
- débits vidéo/audio, codec/profil audio, stéréo et fréquence ;
- streams dupliqués ou désactivés ;
- JSON/nombres/rates `ffprobe` invalides ou forgés ;
- checksum altéré, chemin ou artefact symbolique ;
- fraîcheur sémantique source, y compris permissions de fichier ;
- polling handshake, ordre `ready → recording → started → complete` ;
- injection `.xctestrun` sur la seule cible UI, isolation et commandes
  `build-for-testing`/`test-without-building` ;
- readiness par PID vivant et fichier en croissance, timeout et cleanup exact ;
- latences monotones variables, persistance et cohérence du trim de pré-roll ;
- runtime/type/UDID/lease/ownership exacts et exclusion de l’usage concurrent ;
- matrice exacte de 36 cellules.

## Preuves fraîches

- `ruby scripts/app_store/media_contract_test.rb` : 27 runs, 265 assertions,
  0 failure, 0 error, 0 skip.
- `ruby scripts/release_contract_test.rb` : 5 runs, 424 assertions,
  0 failure, 0 error, 0 skip.
- `ruby scripts/verify_imagegen_assets_test.rb` : 27 runs, 220 assertions,
  0 failure, 0 error, 0 skip.
- `swift test` : 23 XCTest + 112 Swift Testing, soit 135 tests, 0 échec.
- `xcodegen generate` : succès.
- build générique iOS sans signature : `** BUILD SUCCEEDED **`.
- build-for-testing générique iOS sans signature :
  `** TEST BUILD SUCCEEDED **`, app, unit tests et UI tests compilés.
- build Release générique iOS sans signature : `** BUILD SUCCEEDED **`.
- `bundle exec fastlane release_contract` : `release_contract: OK`.
- `media_contract.rb --allow-pending` :
  `media_contract: OK (36 cells, 36 pending)`.

Les builds de preuve utilisent `generic/platform=iOS`, sans destination
CoreSimulator concrète. Une première passe sandboxée s’est arrêtée avant
compilation sur les caches Swift/Xcode interdits ; la même passe a ensuite été
relancée hors sandbox et les trois builds ont réussi. Aucun UDID n’a été ciblé,
booté ou modifié.

## Reste volontairement en attente

Une exécution autorisée devra louer les trois appareils du pool fixe, fournir
leurs locks exacts, produire les 36 PNG et les 6 App Previews, effectuer le QA
visuel sur les trois formats puis faire passer le contrat média strict. Aucun
fichier factice n’a remplacé cette preuve runtime.
