### Task 9: Audio, haptique, Game Center et tip jar optionnels

**Files:**
- Create: `NovaStationPinball/Services/AudioEngine.swift`, `HapticsService.swift`, `GameCenterClient.swift`, `TipJarSupport.swift`
- Create: `NovaStationPinball/StoreKit/NovaStationPinball.storekit`
- Test: `NovaStationPinballTests/AudioEngineTests.swift`, `HapticsServiceTests.swift`, `GameCenterClientTests.swift`, `TipJarSupportTests.swift`

**Interfaces:**
- Produces: protocols injectables dont les implémentations nulles ne bloquent jamais une partie.

- [ ] Tester les adapters indisponibles et confirmer que gameplay/scores locaux continuent.
- [ ] Implémenter AVAudioEngine/Core Haptics/GameKit derrière protocoles.
- [ ] Tester que le catalogue contient exactement les trois tips et zéro feature gate.
- [ ] Ajouter la configuration StoreKit exclue du bundle release.
- [ ] Vérifier l’absence de dépendance réseau obligatoire.
