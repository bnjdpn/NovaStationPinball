### Task 1: Repo autonome et contrats exécutables

**Files:**
- Create: `AGENTS.md`, `.gitignore`, `README.md`, `project.yml`, `Package.swift`, `Gemfile`
- Create: `NovaStationPinball/Resources/PrivacyInfo.xcprivacy`, `NovaStationPinball/NovaStationPinball.entitlements`
- Create: `scripts/release_contract.rb`, `scripts/release_contract_test.rb`
- Create: `fastlane/Fastfile`, `fastlane/Appfile`, `fastlane/release_config.json`
- Create: `docs/index.html`, `docs/privacy.html`

**Interfaces:**
- Produces: XcodeGen targets `NovaStationPinball`, `NovaStationPinballTests`, `NovaStationPinballUITests`; SPM product `NovaStationCore`; Fastlane lane `release_contract`.

- [ ] Écrire `scripts/release_contract_test.rb` qui exige bundle ID, iOS 17, familles 1/2, paysage, FR/EN, les trois tips, Formspree, zéro workflow et toutes les lanes obligatoires.
- [ ] Exécuter `rtk proxy ruby scripts/release_contract_test.rb` et confirmer l’échec par fichiers manquants.
- [ ] Ajouter les fichiers de contrat et configuration minimaux, sans sources de gameplay.
- [ ] Exécuter le test Ruby puis `rtk proxy xcodegen generate` et confirmer leur réussite.
- [ ] Vérifier `rtk proxy git status --short --branch` sans toucher à un autre repo.
