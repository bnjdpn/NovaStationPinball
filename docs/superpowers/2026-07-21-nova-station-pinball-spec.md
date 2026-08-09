# Nova Station Pinball — spécification approuvée

## Produit

Nova Station Pinball est un jeu iOS/iPadOS original, en paysage, inspiré du rythme,
de la profondeur et de la lisibilité de 3D Pinball: Space Cadet. Il possède une
table unique, trois billes par partie, neuf habilitations et des missions
équivalentes, mais aucun code, texte, son, fichier DAT ou asset de la référence.

La référence comportementale publique est
<https://github.com/k4zmu2a/SpaceCadetPinball>. Elle sert uniquement à mesurer les
transitions, scores, timings et trajectoires décrits dans
`docs/reference-behavior-matrix.md`.

## Plateformes et expérience

- iPhone et iPad, iOS/iPadOS 17+, Swift 6, paysage uniquement.
- Une composition 4:3 non recadrée : table environ 70 %, console CRT environ 30 %.
- Zones tactiles invisibles pour les batteurs, glisser-relâcher pour le lanceur,
  court geste horizontal pour le nudge.
- Jeu entièrement fonctionnel hors ligne ; Game Center est optionnel.
- App gratuite, sans publicité, tracking, compte ni paywall. Seuls les dons
  `tip.cafe`, `tip.merci` et `tip.soutien` sont autorisés et ne débloquent rien.
- Interface, aide, metadata, screenshots et App Preview en français et anglais.

## Architecture

- `NovaStationCore` est un Swift Package pur et `Sendable`. Il possède la
  simulation déterministe à pas fixe 240 Hz, la définition de table, les règles,
  les replays et les modèles persistants indépendants d’Apple.
- L’app utilise SpriteKit pour afficher les sprites bitmap et SwiftUI uniquement
  pour le conteneur et les réglages système.
- Les adapters Apple couvrent AVAudioEngine, Core Haptics, Game Center, StoreKit
  et la persistance. Toute indisponibilité doit être non bloquante.

## Contrat visuel

- ImageGen produit tous les visuels identitaires et marketing.
- Les masters et dérivés finaux sont uniquement des PNG bitmap.
- Aucun SVG, PDF vectoriel, emoji décoratif, illustration CSS, forme SwiftUI ou
  SpriteKit générique, ni assemblage de gradients ne peut constituer l’art final.
- Le CSS de la page support sert uniquement à sa mise en page accessible.
- Chaque master ImageGen est décrit dans `Art/imagegen-provenance.json` avec son
  prompt, sa date, ses dimensions, son rôle, son fichier source et son SHA-256.
- L’art respecte le guide raster 4:3 exporté du greybox et ne déplace aucun
  organe mécanique.

## Acceptation

- Physique, collisions continues, règles, replays et persistance testés en TDD.
- Dix replays identiques produisent le même hash ; soak déterministe de 30 min.
- Missions, promotions, bonus, drains, extra-ball, multiball, tilt et sauvetage
  couverts.
- Zéro `.svg`, zéro asset PDF vectoriel, provenance complète et exacte.
- Revue réelle des états lancement, mission, promotion, multiball, tilt et fin.
- Tests FR/EN, VoiceOver, contrastes, safe areas et zones de pouces.
- Validation séquentielle sur UDID éphémères possédés : iPhone 17 Pro Max,
  iPhone SE 3 et iPad Pro 13 pouces M5 sous iOS 26.2.
- 60 fps stable et 120 fps sur ProMotion quand disponible.
- Aucun push, remote, fiche ASC, upload ou soumission implicite.
