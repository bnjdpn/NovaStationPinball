# Nova Station Pinball

> Isolation : `/private/tmp/apps-factory/NovaStationPinball/<execution_id>/`. Une
> isolation complète du daemon CoreSimulator requiert une VM macOS éphémère ou un runner macOS éphémère.
> Avant soumission, relire `fastlane/release_config.json.app_preview_policy`.

Jeu iOS Swift 6 / SpriteKit avec `NovaStationCore`; travailler dans ce dépôt,
via `rtk proxy`, `NovaStationPinball.xcodeproj` et le scheme homonyme.

- Garder règles de jeu, scoring et physique déterministes dans le core, avec
  tests indépendants de l'UI. Réseau, analytics, compte et publicité exigent
  un plan app-spécifique approuvé.
- Le modèle commercial approuvé peut inclure prix upfront, achat unique,
  abonnement, paywall ou pourboires, avec confiance, confidentialité,
  conformité Apple et migration loyale. La config décrit l'offre courante.
- Maintenir les médias dans `Art/` et les artefacts retenus sous `Builds/`; ne
  pas confondre cache `.build` avec preuve de release.
- La preview est applicable : exécuter le générateur app-local défini dans
  `release_config.json` pour ses scénarios, avec au plus deux locales lourdes.
- Une release passe par Fastlane/ASC API, `release_contract`, puis readback
  complet avant commit/push. Support via Formspree, jamais email public;
  aucun workflow GitHub Actions ni secret Git.


## Site marketing

- Le site GitHub Pages est une surface produit app-locale : sa direction est
  documentée dans `site/DIRECTION.md` et ne doit pas être remplacée par un
  template visuel commun au portefeuille.
- Toute évolution publique de fonctionnalité, version, localisation, support,
  confidentialité ou métadonnée doit mettre à jour les sources `marketing/`,
  régénérer la sortie publique avec `ruby scripts/marketing_site.rb`, puis
  réussir `ruby scripts/marketing_site.rb --check` avant release.
- Le workflow `.github/workflows/pages.yml` ne publie que l’artefact statique
  isolé. Il ne construit, ne teste, ne signe et ne livre jamais l’app native.
