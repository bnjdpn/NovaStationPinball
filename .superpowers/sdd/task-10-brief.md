### Task 10: Localisation, accessibilité et cycle de vie

**Files:**
- Create: `NovaStationPinball/Resources/Localizable.xcstrings`
- Create: `NovaStationPinball/Services/LifecycleCoordinator.swift`
- Test: `NovaStationPinballTests/LocalizationContractTests.swift`, `LifecycleCoordinatorTests.swift`
- Test: `NovaStationPinballUITests/AccessibilityAuditUITests.swift`

**Interfaces:**
- Produces: clés FR/EN complètes, labels VoiceOver, pause/background/restore déterministes.

- [ ] Tester que toutes les clés publiques ont FR et EN sans valeur vide ni fallback prétendu.
- [ ] Tester pause, background, interruption audio et checkpoint.
- [ ] Implémenter le cycle de vie et les labels/accessibility actions.
- [ ] Exécuter les audits UI sur les trois classes d’appareils et corriger chevauchements/contraste/safe areas.
