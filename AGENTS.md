# Nova Station Pinball

> Isolation : `/private/tmp/apps-factory/NovaStationPinball/<execution_id>/`. Une
> isolation complète du daemon CoreSimulator requiert une VM macOS éphémère ou un runner macOS éphémère.
> Avant soumission, relire `fastlane/release_config.json.app_preview_policy`.

Jeu iOS Swift 6 / SpriteKit avec `NovaStationCore`; travailler dans ce dépôt,
via `rtk proxy`, `NovaStationPinball.xcodeproj` et le scheme homonyme.

- Garder règles de jeu, scoring et physique déterministes dans le core, avec
  tests indépendants de l'UI. Ne pas ajouter réseau, analytics, compte, pubs ou
  IAP non-tip.
- Maintenir les médias dans `Art/` et les artefacts retenus sous `Builds/`; ne
  pas confondre cache `.build` avec preuve de release.
- La preview est applicable : exécuter le générateur app-local défini dans
  `release_config.json` pour ses scénarios, avec au plus deux locales lourdes.
- Une release passe par Fastlane/ASC API, `release_contract`, puis readback
  complet avant commit/push. Support via Formspree, jamais email public;
  aucun workflow GitHub Actions ni secret Git.
