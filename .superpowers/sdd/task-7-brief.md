### Task 7: Greybox SpriteKit et contrôles tactiles

**Files:**
- Modify: `NovaStationPinball/App/NovaStationPinballApp.swift`
- Create: `NovaStationPinball/App/RootView.swift`, `NovaStationPinball/App/AppModel.swift`
- Create: `NovaStationPinball/Game/PinballScene.swift`, `SimulationDriver.swift`, `TouchInterpreter.swift`
- Create: `NovaStationPinball/Resources/Art/greybox-table-guide.png`
- Create: `scripts/export_greybox_guide.swift`
- Test: `NovaStationPinballTests/TouchInterpreterTests.swift`, `SimulationDriverTests.swift`
- Test: `NovaStationPinballUITests/LayoutUITests.swift`

**Interfaces:**
- Produces: `TouchInterpreter.events(for:in:)`, `SimulationDriver.advance(elapsed:input:)`, scène 4:3 letterboxée.

- [ ] Tester et faire échouer les zones invisibles gauche/droite, lanceur glisser-relâcher, nudge court et annulation multitouch.
- [ ] Implémenter l’interpréteur puis vérifier.
- [ ] Tester le rattrapage borné du driver 240 Hz et implémenter.
- [ ] Construire la scène greybox fonctionnelle en SpriteKit avec formes uniquement marquées `greybox`, jamais final art.
- [ ] Exporter un guide raster exact 4:3 avec zones mécaniques et sûres.
- [ ] Tester iPhone/iPad : aucun recadrage et ratio table/console conforme.
