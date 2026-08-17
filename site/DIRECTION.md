# Direction — Nova Station Pinball

## Ressenti

Une machine rare découverte dans la salle de repos d’une station, sombre, lourde et mécanique. Le site privilégie la table réelle et le silence autour d’elle.

## Langage visuel

Noir, laiton, acier et un filet de cyan. Serif éditoriale pour le récit, monospace pour les numéros de mission. Aucun mécanisme, flipper ou décor n’est simulé en CSS ou SVG.

## Traduction web

Le site sert `en-US` et `fr-FR` depuis les métadonnées du candidat 1.0. La racine est `en-US`. L’app n’étant pas publique, il n’y a ni badge App Store, ni Smart App Banner, ni CTA de téléchargement.

## Layout

Le titre et la proposition de valeur ouvrent comme une fiche de mission, immédiatement suivis du vrai key art en format cinéma. Une seule preuve UI réelle et un renvoi éditorial vers Vesper Drift complètent la page.

## Assets et provenance

- Source unique des visuels produit : les captures de jeu réelles du candidat courant, en paysage 2868 × 1320 px, suivies dans `marketing/shots/<locale>/`.
- Aucune illustration générée n'est publiée. Le dossier `marketing/art/` a été supprimé avec le raster éditorial qui s'y trouvait ; il ne représentait pas l'app.
- Dérivées servies : 860 et 1720 et 2868 px de large, en AVIF puis WebP, via `<picture>` + `srcset`/`sizes`. Les attributs `width`/`height` portent les dimensions réelles de la plus grande variante, donc aucun étirement ni réservation d'espace erronée.
- Couverture : 2 locale(s) × 3 capture(s), chacune mappée explicitement dans `marketing/site.json > local_assets`.
- Contrat de design : `hero_raster` = `assets/shots/en-US/01-2868.webp` (2868 × 1320), `hero_source` = `app-store-screenshot`. La page 404 et les métadonnées Open Graph pointent la même capture réelle.
- Carte sociale `marketing/web/social-card.jpg` : composition locale à partir de la vraie icône App Store, de la première capture et des couleurs déclarées par le thème. Aucun texte inventé.
- Icônes : `marketing/web/app-icon-*.png` et `marketing/web/related/*.png` sont dérivées des icônes App Store publiées, en 256 px minimum pour rester nettes en 2× et 3×.
- Aucun lien vers un CDN Apple : tout est auto-hébergé, donc rien ne casse quand une fiche App Store change.

Aucune fausse interface n'est publiée : la seule interface visible est une capture réelle de l'app.

## Différence et clichés évités

Pas de cyberpunk générique, pas de gradient violet, pas de mandala, pas de fausse machine, pas de score inventé, pas de cartes SaaS. La table montrée est l’asset produit réel.

## Exclusion Pages

Ce fichier est volontairement placé sous `site/DIRECTION.md` mais `.github/workflows/pages.yml` l’exclut explicitement de `_site` et vérifie son absence avant l’upload Pages.
