### Task 11: ASO, support et médias déterministes

**Files:**
- Create: `fastlane/metadata/en-US/*`, `fastlane/metadata/fr-FR/*`
- Create: `NovaStationPinballUITests/StoreScreenshotUITests.swift`, `AppPreviewUITests.swift`
- Create: `scripts/app_store/generate_screenshots.rb`, `generate_app_previews.rb`, `media_contract.rb`
- Test: `scripts/app_store/media_contract_test.rb`

**Interfaces:**
- Produces: matrice locale × device × scénario pour lancement, mission, promotion, multiball, tilt, fin de partie ; manifeste daté avec révision et checksums.

- [ ] Écrire et faire échouer le contrat média sur cellules manquantes/dupliquées/étrangères/obsolètes.
- [ ] Ajouter scénarios UI déterministes et générateurs à deux locales maximum.
- [ ] Produire metadata ASO FR/EN et textes support/privacy sans email ni `mailto:`.
- [ ] Capturer screenshots et App Preview réels depuis les assets intégrés.
- [ ] Faire passer contrat média, contrat release et audit Formspree du portefeuille.
