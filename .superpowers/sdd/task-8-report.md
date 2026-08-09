# Task 8 — Pipeline ImageGen et intégration raster

Date de validation : 2026-07-22

## Résultat

Le pipeline raster de Nova Station Pinball est en place sans SVG, PDF ou art procédural visible. Sept masters natifs ImageGen, dont un intermédiaire conservé uniquement pour la provenance, alimentent dix-sept dérivés PNG reproductibles. Le runtime SpriteKit affiche le fond 4:3 final et les seuls éléments mobiles nécessaires : deux batteurs, le plongeur et la bille.

Aucun commit ni push n'a été effectué.

## Cycle TDD observé

- RED initial : `ruby scripts/verify_imagegen_assets_test.rb` a produit 8 runs, 22 assertions, 8 failures et 0 errors parce que le vérificateur et les artefacts n'existaient pas encore.
- RED d'intégration : les tests ont ensuite détecté l'absence de builder, l'ancien rendu greybox et la superposition de composants statiques.
- RED alpha vert : le test pixel ajouté pour les douze dérivés chroma a échoué sur le halo vert résiduel de `flipper-left`. Le défaut était reproductible sur fonds clair et sombre.
- RED defringe : après la première correction chroma, une inspection parent a encore rejeté un liseré magenta de 1 px. Le nouveau test de bord a compté 301 pixels magenta à faible alpha dans `flipper-left` et a produit 17 runs, 148 assertions, 1 failure.
- RED synchronisation : la porte finale a rejeté les quatre nouvelles opérations `defringe` comme inconnues. Le test de recette bornée a reproduit ce défaut avec 18 runs, 155 assertions et 1 failure, avant l'ajout de la validation exacte côté contrat.
- RED runtime XCUI : la gate root sur l'iPhone possédé `C3B0…` a passé 20/20 tests unitaires mais `LayoutUITest` a échoué avec plusieurs éléments `art.table`. Le test Ruby ciblé a reproduit la collision exacte entre le node SpriteKit `art.table` et l'overlay SwiftUI `art.table` : 1 run, 3 assertions, 1 failure.
- GREEN ciblé namespace : après le renommage des cinq nodes SpriteKit sous `sprite.*`, le test ciblé a produit 1 run, 4 assertions, 0 failure.
- RED review portal : le test sémantique attendait `210x210+860+325` mais a trouvé `226x215+578+499`, exactement le crop du CRT; 1 run, 1 assertion, 1 failure.
- RED review alpha : le test élargi aux douze PNG alpha a compté 484 pixels de frange magenta faible-alpha sur `bumper.png`; 1 run, 11 assertions, 1 failure.
- RED contrat : les tests exact-recipe, iCCP arbitraire, confinement et ordre temporel ont confirmé que l'ancien vérificateur ne produisait pas les refus dédiés attendus.
- RED Fastlane cwd : la commande contractuelle lancée depuis le root app, `rtk proxy /opt/homebrew/bin/ruby -S bundle exec fastlane release_contract`, échouait avec `ruby: No such file or directory -- scripts/release_contract.rb`. Le test ciblé a reproduit la lane réelle : 1 run, 1 assertion, 1 failure.
- GREEN Fastlane cwd : le `Fastfile` résout maintenant le script via `File.expand_path("../scripts/release_contract.rb", __dir__)` et l'exécute avec `RbConfig.ruby`; le test ciblé passe avec 1 run, 3 assertions.
- RED ICC spoof/mixte : deux PNG Tempfile contournaient le premier garde. Un faux iCCP portant un nom/payload `sRGB` était classé `sRGB`, et un PNG combinant chunk `sRGB` avec iCCP Display P3 était aussi classé `sRGB`; 2 runs, 2 assertions, 2 failures.
- GREEN ICC spoof/mixte : les deux Tempfile sont maintenant classés respectivement `non-sRGB-icc` et `ambiguous-rgb-profile`; 2 runs, 2 assertions, 0 failure.
- GREEN final frais : 26 runs, 196 assertions, 0 failures, 0 errors, 0 skips.

Le test alpha interdit tout pixel visible dominé par le vert et exige un bord à alpha partiel pour chaque dérivé détouré.

## Masters ImageGen

| Master | Dimensions | Rôle |
| --- | ---: | --- |
| `table-master.png` | 1448×1086 | composition maître 4:3 et référence d'identité |
| `table-background-master.png` | 1448×1086 | fond runtime statique, batteurs et plongeur retirés par édition ImageGen |
| `components-checker-master.png` | 1536×1024 | parent de provenance uniquement, jamais source runtime |
| `components-master.png` | 1536×1024 | atlas chroma unique pour les crops de composants |
| `app-icon-master.png` | 1254×1254 | AppIcon |
| `key-art-master.png` | 1536×1024 | écran titre / key art |
| `store-creatives-master.png` | 1774×887 | créatif Store panoramique |

Les sept fichiers natifs sont conservés octet pour octet sous `Art/ImageGen/`. Le manifeste `Art/imagegen-provenance.json` enregistre pour chacun le prompt exact, la date, les dimensions, les rôles, le fichier source ImageGen, les références ou le parent d'édition, le SHA-256 et la revue visuelle. Les masters ImageGen sont volontairement `untagged-rgb`; les dérivés sont normalisés en sRGB.

## Dérivés reproductibles

| Dérivé | Dimensions | Alpha | Source |
| --- | ---: | :---: | --- |
| AppIcon | 1024×1024 | non | app-icon master |
| table-composition | 2048×1536 | non | table-background master |
| crt-console | 460×430 | oui | components master |
| station-panels | 732×464 | oui | components master |
| flipper-left / flipper-right | 272×156 | oui | components master |
| bumper | 192×192 | oui | components master |
| target | 104×182 | oui | components master |
| ramp | 210×353 | oui | components master |
| portal | 226×226 | oui | components master |
| lamp | 80×80 | oui | components master |
| plunger | 330×104 | oui | components master |
| ball | 96×96 | oui | components master |
| menu-background | 1536×1024 | non | key-art master |
| hud-overlay | 412×608 | oui | components master |
| key-art | 1536×1024 | non | key-art master |
| store-creative | 1774×887 | non | store-creatives master |

`scripts/build_imagegen_assets.rb` n'invente aucun dessin : il applique seulement crop, resize, normalisation sRGB, suppression des métadonnées et extraction alpha déterministe. Deux exécutions consécutives ont donné des SHA-256 identiques.

L'extraction chroma utilise `distance_decontaminate` avec seuil 0,2. Elle calcule une couverture alpha douce puis reconstruit les canaux de l'objet à partir de la composition sur vert, ce qui retire la contamination verte sans produire de bord binaire. Pour les douze crops alpha, un defringe post-resize érode l'alpha d'un pixel (`Diamond:1`), applique un feather de sigma 0,45 et neutralise les canaux de bord sous alpha 0,76. Les masters et détails centraux ne sont pas modifiés.

Les planches exhaustives `Art/QA/all-alpha-black.png` et `Art/QA/all-alpha-white.png` montrent, dans le même ordre, batteurs, bumper, cible, rampe, portail, lampe, plongeur, bille, CRT, panneaux et HUD. Elles ont été inspectées à taille originale : aucune frange verte ou magenta visible, aucun détail central dégradé. `portal.png` a également été inspecté seul à taille originale : il représente le véritable anneau orbital circulaire central. `ramp.png` est maintenant la rampe droite complète, sans fragment voisin ni coupe mécanique.

## Contrat sémantique renforcé

- Le vérificateur contient une table indépendante et exacte des 17 recettes : rôle, chemin de sortie, `source_master` et liste ordonnée complète des opérations avec géométrie/paramètres.
- Modifier une géométrie puis relancer le builder peut rafraîchir SHA/dimensions, mais ne peut plus rendre la recette valide : le verifier refuse `invalid exact recipe`.
- Tous les chemins manifestés, sources, parents, références, sorties, overlays et éventuels masques sont confinés au root du repo; les chemins `../` sont refusés.
- Un chunk PNG `iCCP` n'est plus assimilé automatiquement à sRGB. Il doit se décompresser en ICC `acsp` / `RGB ` et son SHA-256 doit correspondre à l'empreinte sRGB système connue `2b3aa164…af7e`; un profil forgé même nommé `sRGB` est refusé. La présence simultanée de `sRGB` et `iCCP` est ambiguë et refusée avant toute branche simplifiée.
- Le `generated_at` du manifeste (`2026-07-22T03:30:00+02:00`) est postérieur au dernier master et à la dernière inspection. Le contrat refuse un header antérieur ou une review antérieure au master.

## Alignement mécanique et runtime

- `Art/QA/table-guide-overlay.png` superpose le guide 4:3 au fond final et confirme le split 70/30 ainsi que l'alignement des cibles, bumpers, pivots de batteurs et voie du plongeur.
- `PinballScene.Layout` définit une seule fois la taille 1024×768, la largeur de playfield 70 %, les pivots des deux batteurs et la position du plongeur.
- Les mêmes constantes alimentent les `FlipperDefinition` / `PlungerDefinition` de la simulation et les positions des `SKSpriteNode` de rendu.
- Le fond `table-composition` vient exclusivement du master édité sans objets mobiles. Le runtime ne superpose donc pas de crops statiques déjà peints dans le fond.
- Les noms de nodes SpriteKit utilisent exclusivement `sprite.table.background`, `sprite.flipper.left`, `sprite.flipper.right`, `sprite.plunger` et `sprite.ball`. Ils ne peuvent plus entrer en collision dans la hiérarchie XCUI avec les overlays SwiftUI `art.frame.4x3`, `art.table` et `art.console`.
- Le scan de `PinballScene.swift` et `RootView.swift` ne trouve ni `SKShapeNode`, ni `SKLabelNode`, ni nom greybox. Les rectangles SwiftUI restants sont transparents et servent seulement aux identifiants d'accessibilité des tests UI.

## Vérifications finales fraîches

- `rtk proxy ruby scripts/verify_imagegen_assets.rb` → `ImageGen asset contract verified: 7 masters, 17 derivatives`.
- `rtk proxy ruby scripts/verify_imagegen_assets_test.rb` → 26 runs, 196 assertions, 0 failures, 0 errors.
- `rtk proxy ruby scripts/release_contract_test.rb` → 2 runs, 106 assertions, 0 failures, 0 errors.
- `rtk proxy /opt/homebrew/bin/ruby -S bundle exec fastlane release_contract` depuis le root app → `release_contract: OK`, Fastlane terminé avec succès. Cette preuve remplace la précédente exécution directe du script comme gate de lane.
- `rtk proxy git diff --check` → exit 0.
- Scan SVG/SVGZ/PDF sous `Art` et `NovaStationPinball/Resources` → aucun résultat.
- Scan `SKShapeNode|SKLabelNode|greybox` dans les vues runtime → aucun résultat.
- `rtk proxy xcodebuild ... -destination 'generic/platform=iOS Simulator' ... CODE_SIGNING_ALLOWED=NO -quiet build` → exit 0 après relance hors sandbox, puis de nouveau exit 0 après le correctif de namespace SpriteKit. La première tentative sandboxée avait seulement échoué sur les accès de caches SwiftPM/CoreSimulator.
- Build générique finale post-review crops/alpha/contrat, DerivedData isolé `task-8-review-final` → exit 0.
- Deux rebuilds réels consécutifs supplémentaires après correction review → `h0 == h1 == h2` pour les 17 SHA-256.

## Preuve runtime root post-correctif

- iPhone possédé : `C3B0C31A-F6C0-4AA1-B72F-FB4CE91F56E1` (`NovaTask8Root-iPhone-20260722`), iPhone 17 Pro Max sous iOS 26.2.
- Reçu frais : `/private/tmp/apps-factory/NovaStationPinball/task8-root-runtime-fix-20260722/xcresult/task8-root-runtime-fix.xcresult`.
- Résultat : 20/20 tests unitaires et 2/2 tests UI, `** TEST SUCCEEDED **`.
- Capture live `simctl` post-correctif, seulement pivotée de 90 degrés pour normaliser l'orientation physique du framebuffer : `Art/QA/runtime-iphone-raster.png`.
- Dimensions : 2868×1320 ; SHA-256 : `d1fd224d17f488f5f22288a49dfe110905deaec973929b5e497c79ed4d2c4d17`.
- Inspection root : cadre 4:3 entier, playfield 70 % / console 30 %, aucun crop, aucune superposition statique, pièces mobiles nettes et alignées, aucune frange verte ou magenta, aucun art greybox visible.

Les autres simulateurs visibles sans verrou de possession n'ont été ni adoptés, ni arrêtés, ni nettoyés. L'UDID root a été arrêté puis supprimé exactement après conservation de la preuve ; `simctl list devices` confirme son absence.
