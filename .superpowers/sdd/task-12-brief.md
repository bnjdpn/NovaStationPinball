### Task 12: Validation finale exhaustive

**Files:**
- Create: `docs/validation-report.md`
- Create: `Builds/AppStore/NovaStationPinball/<run_id>/{screenshots,app_previews,logs}`

**Interfaces:**
- Produces: preuves distinctes build, tests, runtime, art, médias, performance et état Git local.

- [ ] Exécuter `release_contract`, contrat artistique, contrats médias et audit support.
- [ ] Exécuter `swift test` dans un scratch unique puis XcodeGen et build générique non signé.
- [ ] Louer et verrouiller séquentiellement les trois UDID exacts du pool fixe sous iOS 26.2 (iPhone compact, iPhone large, iPad), sans création/suppression/adoption ; un worker, aucune destination `booted` ou par nom.
- [ ] Exécuter tous les XCTest/UI tests sur iPhone 17 Pro Max, iPhone SE 3 et iPad Pro 13 M5.
- [ ] Capturer les six états exigés et inspecter réellement chaque image/vidéo.
- [ ] Mesurer 60 fps et, si le simulateur/appareil le permet, 120 fps ProMotion ; consigner les limites de preuve.
- [ ] Vérifier absence totale d’assets interdits, de secrets, de workflows et de changements hors repo.
- [ ] Faire une revue de code finale indépendante et corriger toute finding importante.
- [ ] Consigner branche `main`, remote absent/non muté, statut et diff exact ; ne pas commit/push sans demande.
