# Nova Station Pinball

Jeu de flipper iOS Swift 6 / SpriteKit. `NovaStationPinball.xcodeproj`,
scheme `NovaStationPinball`, iOS 17+. Intention durable : gameplay
déterministe et rejouable — règles, scoring et physique vivent dans le core,
jamais dans l'UI.

## Commandes

- Projet généré par XcodeGen : éditer `project.yml` puis `xcodegen generate`
  (ne jamais éditer le `.pbxproj` à la main).
- Tests core SwiftPM (package racine `Package.swift`) :
  `swift test --scratch-path /private/tmp/apps-factory/NovaStationPinball/<execution_id>/spm`
- Contrat de release local : `ruby scripts/release_contract_test.rb` puis
  `bundle exec fastlane release_contract` (enchaîne aussi les tests Ruby ASC).
- Site : `ruby scripts/marketing_site.rb` puis `--check` avant release.
- Lanes ASC (via wrapper portefeuille) : `asc_status`, `metadata`,
  `screenshots`, `app_previews`, `adopt_media`, `media_contract`,
  `build_release`, `upload_release`, `submit_review`, `release_quick`,
  `pricing`, `iap_status`, `iap_sync`.

## Architecture (pointeurs)

- `NovaStationCore/` : lib SwiftPM — règles de jeu, scoring, physique
  déterministes, testés indépendamment de l'UI (`NovaStationCore/Tests/`).
- `NovaStationPinball/` : app SpriteKit/SwiftUI (cibles définies aussi comme
  targets SwiftPM `NovaStationLifecycle` pour testabilité).
- `scripts/app_store/` : pipeline ASC complet (client, adopt_media,
  generate_app_previews, readback, wait_for_state) avec ses tests `*_test.rb`.
- `scripts/final_validation_pool.rb` : pool/lease de simulateurs pour la
  validation finale (devices et runtime requis figés dans le script).
- `Art/` : sources médias ; `Builds/` : artefacts de release retenus — ne
  jamais confondre le cache `.build` avec une preuve de release.

## Contraintes apprises

- App preview APPLICABLE (`fastlane/release_config.json.app_preview_policy`) :
  générer via `scripts/app_store/generate_app_previews.rb` pour les scénarios
  configurés, au plus 2 locales en parallèle ; relire la policy avant chaque
  soumission.
- Le handshake preview ne doit pas dépendre d'un export shell autour de
  xcodebuild (vérifié par `scripts/release_contract.rb`).
- Release : `release_contract` → mutations ASC → readback complet avant
  commit/push.

## Site marketing

- Sortie générée dans `site/` (PAS `docs/` — `docs/` contient stratégie ASO
  et plans) ; ne jamais éditer la sortie à la main.
- `site/DIRECTION.md` : direction visuelle, provenance des assets, registre
  des prompts ImageGen et règles anti-cliché — à relire avant tout changement
  de page ; jamais remplacé par un template commun au portefeuille.
