# Direction — Nova Station Pinball

## Ressenti

Une machine rare découverte dans la salle de repos d’une station, sombre, lourde et mécanique. Le site privilégie la table réelle et le silence autour d’elle.

## Langage visuel

Noir, laiton, acier et un filet de cyan. Serif éditoriale pour le récit, monospace pour les numéros de mission. Aucun mécanisme, flipper ou décor n’est simulé en CSS ou SVG.

## Traduction web

Le site sert `en-US` et `fr-FR` depuis les métadonnées du candidat 1.0. La racine est `en-US`. L’app n’étant pas publique, il n’y a ni badge App Store, ni Smart App Banner, ni CTA de téléchargement.

## Layout

Le titre et la proposition de valeur ouvrent comme une fiche de mission, immédiatement suivis du vrai key art en format cinéma. Une seule preuve UI réelle et un renvoi éditorial vers Vesper Drift complètent la page.

## Assets publiés

- Hero source réel : `Art/ImageGen/key-art-master.png`.
- Hero final : `marketing/art/hero-editorial.jpg` vers `site/assets/hero-editorial.jpg`.
- Preuve UI réelle : premier screenshot localisé de `marketing/site.json > screenshots.<locale>[0]`, copié depuis `Builds/AppStore/NovaStationPinball/20260810-nova-100-official-3890f8ce-019fe558/screenshots/`.
- Favicon : vraie icône de l’app vers `site/assets/app-icon.png`.
- Cross-promo : vraie icône Vesper locale au dépôt.

## ImageGen

Mode utilisé pendant l’exploration : built-in ImageGen. Résumé du prompt testé : photographier une table Nova physique dans une salle de station, en verrouillant matériaux et table des références. Le résultat a inventé une autre table : il a été rejeté et supprimé. Aucun raster ImageGen inventé n’est publié ; le hero final est une dérivation JPEG directe du vrai key art.

## Différence et clichés évités

Pas de cyberpunk générique, pas de gradient violet, pas de mandala, pas de fausse machine, pas de score inventé, pas de cartes SaaS. La table montrée est l’asset produit réel.

## Exclusion Pages

Ce fichier est volontairement placé sous `site/DIRECTION.md` mais `.github/workflows/pages.yml` l’exclut explicitement de `_site` et vérifie son absence avant l’upload Pages.
