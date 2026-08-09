import Testing
@testable import NovaStationCore

@Suite("MissionCatalogTests")
struct MissionCatalogTests {
    @Test("Orbital Wake is the uncredentialed opening mission")
    func orbitalWake() {
        let mission = MissionCatalog.definition(for: .orbitalWake)
        #expect(mission.requiredClearance == nil)
        #expect(mission.awardedClearance == .dockKey)
    }

    @Test("Relay Bloom follows the dock key")
    func relayBloom() {
        let mission = MissionCatalog.definition(for: .relayBloom)
        #expect(mission.requiredClearance == .dockKey)
        #expect(mission.awardedClearance == .relayKey)
    }

    @Test("Cargo Drift follows the relay key")
    func cargoDrift() {
        let mission = MissionCatalog.definition(for: .cargoDrift)
        #expect(mission.requiredClearance == .relayKey)
        #expect(mission.awardedClearance == .cargoKey)
    }

    @Test("Prism Survey follows the cargo key")
    func prismSurvey() {
        let mission = MissionCatalog.definition(for: .prismSurvey)
        #expect(mission.requiredClearance == .cargoKey)
        #expect(mission.awardedClearance == .prismKey)
    }

    @Test("Ion Choir follows the prism key")
    func ionChoir() {
        let mission = MissionCatalog.definition(for: .ionChoir)
        #expect(mission.requiredClearance == .prismKey)
        #expect(mission.awardedClearance == .ionKey)
    }

    @Test("Dusk Courier follows the ion key")
    func duskCourier() {
        let mission = MissionCatalog.definition(for: .duskCourier)
        #expect(mission.requiredClearance == .ionKey)
        #expect(mission.awardedClearance == .transitKey)
    }

    @Test("Helix Latch follows the transit key")
    func helixLatch() {
        let mission = MissionCatalog.definition(for: .helixLatch)
        #expect(mission.requiredClearance == .transitKey)
        #expect(mission.awardedClearance == .shieldKey)
    }

    @Test("Polar Vane follows the shield key")
    func polarVane() {
        let mission = MissionCatalog.definition(for: .polarVane)
        #expect(mission.requiredClearance == .shieldKey)
        #expect(mission.awardedClearance == .commandKey)
    }

    @Test("Nova Crown completes the nine-clearance catalog")
    func novaCrown() {
        let mission = MissionCatalog.definition(for: .novaCrown)
        #expect(mission.requiredClearance == .commandKey)
        #expect(mission.awardedClearance == .novaKey)
    }

    @Test("Harbor Ember shares the cargo promotion tier")
    func harborEmber() {
        let mission = MissionCatalog.definition(for: .harborEmber)
        #expect(mission.requiredClearance == .relayKey)
        #expect(mission.awardedClearance == .cargoKey)
    }

    @Test("Echo Spire shares the ion promotion tier")
    func echoSpire() {
        let mission = MissionCatalog.definition(for: .echoSpire)
        #expect(mission.requiredClearance == .prismKey)
        #expect(mission.awardedClearance == .ionKey)
    }

    @Test("Lantern Route shares the shield promotion tier")
    func lanternRoute() {
        let mission = MissionCatalog.definition(for: .lanternRoute)
        #expect(mission.requiredClearance == .transitKey)
        #expect(mission.awardedClearance == .shieldKey)
    }

    @Test("Rift Containment shares the command promotion tier")
    func riftContainment() {
        let mission = MissionCatalog.definition(for: .riftContainment)
        #expect(mission.requiredClearance == .shieldKey)
        #expect(mission.awardedClearance == .commandKey)
    }

    @Test("Aurora Quarantine shares the final promotion tier")
    func auroraQuarantine() {
        let mission = MissionCatalog.definition(for: .auroraQuarantine)
        #expect(mission.requiredClearance == .commandKey)
        #expect(mission.awardedClearance == .novaKey)
    }

    @Test("Vault Signal shares the final promotion tier")
    func vaultSignal() {
        let mission = MissionCatalog.definition(for: .vaultSignal)
        #expect(mission.requiredClearance == .commandKey)
        #expect(mission.awardedClearance == .novaKey)
    }

    @Test("Phase Tide shares the final promotion tier")
    func phaseTide() {
        let mission = MissionCatalog.definition(for: .phaseTide)
        #expect(mission.requiredClearance == .commandKey)
        #expect(mission.awardedClearance == .novaKey)
    }

    @Test("Station Tempest shares the final promotion tier")
    func stationTempest() {
        let mission = MissionCatalog.definition(for: .stationTempest)
        #expect(mission.requiredClearance == .commandKey)
        #expect(mission.awardedClearance == .novaKey)
    }

    @Test("the catalog has one unique entry for every mission identifier")
    func completeCatalog() {
        #expect(MissionCatalog.all.count == 17)
        #expect(MissionCatalog.all.map(\.id) == MissionID.allCases)
        #expect(Set(MissionCatalog.all.map(\.completionTrigger)).count == MissionID.allCases.count)
        #expect(Set(MissionCatalog.all.map(\.awardedClearance)).count == ClearanceLevel.allCases.count)
        #expect(MissionCatalog.all.map(\.startScore) == [
            10_000, 10_000, 10_000, 10_000,
            20_000, 20_000, 20_000, 20_000, 20_000, 20_000, 20_000, 20_000, 20_000,
            30_000, 30_000, 30_000, 30_000
        ])
        #expect(MissionCatalog.all.map(\.completionScore) == [
            500_000, 500_000, 500_000, 750_000,
            1_000_000, 1_000_000, 1_000_000, 750_000, 750_000,
            750_000, 1_250_000, 1_250_000, 1_250_000,
            1_750_000, 1_500_000, 2_000_000, 5_000_000
        ])
        for mission in MissionCatalog.all {
            #expect(MissionCatalog.definition(for: mission.id) == mission)
            #expect(!mission.completionTrigger.isEmpty)
            #expect(mission.completionScore > 0)
        }
    }

    @Test("every catalog mission preserves the resource-driven timing baseline")
    func resourceDrivenTimingBaselines() {
        for mission in MissionCatalog.all {
            #expect(mission.timing == .resourceDriven(abortTrigger: .stationPowerDepleted))
            #expect(mission.timing.abortTrigger == .stationPowerDepleted)
            #expect(mission.timing.baselineTicks == nil)
            #expect(mission.timing.novaTicks == nil)
            #expect(mission.timing.deltaTicks == nil)
            #expect(mission.timing.deltaPercentage == nil)
            #expect(mission.timing.isWithinFivePercent == nil)
        }
    }

    @Test("fixed timing deltas use exact 240 Hz tick conversion and a five percent bound")
    func fixedTimingDeltaCalculation() {
        let cases = [
            (baselineSeconds: 10, novaTicks: 2_400, expectedDelta: 0, expectedPercent: 0.0),
            (baselineSeconds: 10, novaTicks: 2_520, expectedDelta: 120, expectedPercent: 5.0),
            (baselineSeconds: 10, novaTicks: 2_280, expectedDelta: -120, expectedPercent: -5.0)
        ]

        for testCase in cases {
            let baselineTicks = MissionTiming.ticks(seconds: testCase.baselineSeconds)
            let timing = MissionTiming.fixedWindow(
                baselineTicks: baselineTicks,
                novaTicks: testCase.novaTicks
            )

            #expect(baselineTicks == testCase.baselineSeconds * 240)
            #expect(timing.deltaTicks == testCase.expectedDelta)
            #expect(timing.deltaPercentage == testCase.expectedPercent)
            #expect(timing.isWithinFivePercent == true)
            #expect(abs(timing.deltaPercentage!) <= 5)
        }
    }
}
