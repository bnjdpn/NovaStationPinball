import Foundation
import NovaStationCore
import XCTest

#if !SWIFT_PACKAGE
@testable import NovaStationPinball
#endif

final class LocalizationContractTests: XCTestCase {
    private var publicKeys: Set<String> { Set([
        "accessibility.action.launch_ball",
        "accessibility.action.left_flipper",
        "accessibility.action.nudge",
        "accessibility.action.pause",
        "accessibility.action.resume",
        "accessibility.action.right_flipper",
        "accessibility.console.label",
        "accessibility.console.value",
        "accessibility.frame.hint",
        "accessibility.frame.label",
        "accessibility.table.hint",
        "accessibility.table.label",
        "app.name",
        "drill.bonus-bank",
        "drill.bonus-multiplier",
        "drill.extra-ball",
        "drill.hud.exit",
        "drill.hud.failed",
        "drill.hud.remaining",
        "drill.hud.retry",
        "drill.hud.succeeded",
        "drill.hud.title",
        "drill.multiball",
        "drill.portal",
        "drill.ramp-left",
        "drill.ramp-right",
        "drill.return-center",
        "drill.return-left",
        "drill.return-right",
        "drill.rollover-center",
        "drill.score-multiplier",
        "drill.station-power",
        "drill.target-bank",
        "guide.close",
        "guide.controls.body",
        "guide.controls.title",
        "guide.missions.body",
        "guide.missions.title",
        "guide.next",
        "guide.open",
        "guide.previous",
        "guide.progress.body",
        "guide.progress.title",
        "guide.title",
        "hud.balls",
        "hud.clearance",
        "hud.clearance.none",
        "hud.mission.active",
        "hud.mission.completed",
        "hud.mission.failed",
        "hud.mission.idle",
        "hud.multipliers",
        "hud.phase.game_over",
        "hud.phase.launch",
        "hud.score",
        "hud.station_power",
        "hud.tilt",
        "paywall.body",
        "paywall.close",
        "paywall.feature.drills",
        "paywall.feature.review",
        "paywall.feature.rewind",
        "paywall.feature.stats",
        "paywall.free_forever",
        "paywall.link.privacy",
        "paywall.link.support",
        "paywall.link.terms",
        "paywall.loading",
        "paywall.one_time",
        "paywall.purchase.hint",
        "paywall.restore",
        "paywall.status.cancelled",
        "paywall.status.nothing_to_restore",
        "paywall.status.owned",
        "paywall.status.pending",
        "paywall.status.unavailable",
        "paywall.status.unverified",
        "paywall.title",
        "paywall.unavailable",
        "status.audio_interrupted",
        "status.ball_launched",
        "status.drill",
        "status.game_over",
        "status.gesture_cancelled",
        "status.mission",
        "status.multiball",
        "status.nudge",
        "status.paused",
        "status.plunger_charging",
        "status.promotion",
        "status.restored",
        "status.reviewing",
        "status.rewound",
        "status.system_ready",
        "status.tilt",
        "workshop.body.free",
        "workshop.body.owned",
        "workshop.close",
        "workshop.drills.body",
        "workshop.drills.record",
        "workshop.drills.title",
        "workshop.drills.untried",
        "workshop.founder",
        "workshop.message.no_keyframe",
        "workshop.open",
        "workshop.resume",
        "workshop.review.ball",
        "workshop.review.five",
        "workshop.review.hint",
        "workshop.review.speed",
        "workshop.review.speed.full",
        "workshop.review.speed.half",
        "workshop.review.title",
        "workshop.rewind.ball_start",
        "workshop.rewind.five",
        "workshop.rewind.hint",
        "workshop.rewind.remaining",
        "workshop.rewind.three",
        "workshop.rewind.title",
        "workshop.rewind.unlimited",
        "workshop.title",
        "workshop.unlock"
    ] + MissionID.allCases.map { "mission.\($0.rawValue)" }
      + ClearanceLevel.allCases.map { "clearance.\($0.rawValue)" }) }

    func testEveryPublicKeyHasExplicitTranslatedEnglishAndFrenchValues() throws {
#if SWIFT_PACKAGE
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        XCTAssertEqual(Set(strings.keys), publicKeys, "Every shipped string must be contract-owned.")
        XCTAssertEqual(catalog["sourceLanguage"] as? String, "en")

        for key in publicKeys.sorted() {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
            XCTAssertEqual(Set(localizations.keys), ["en", "fr"], key)

            for locale in ["en", "fr"] {
                let localization = try XCTUnwrap(localizations[locale] as? [String: Any], "\(key) [\(locale)]")
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any], "\(key) [\(locale)]")
                XCTAssertEqual(unit["state"] as? String, "translated", "\(key) [\(locale)] must not claim fallback coverage")
                let value = try XCTUnwrap(unit["value"] as? String, "\(key) [\(locale)]")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) [\(locale)]")
            }
        }
#else
        // A string that varies by grammatical number is compiled into
        // Localizable.stringsdict instead of Localizable.strings, so the
        // shipped key set is the union of both files.
        for locale in ["en", "fr"] {
            let compiled = try compiledLocalization(locale: locale)
            XCTAssertEqual(
                Set(compiled.strings.keys).union(compiled.plurals.keys),
                publicKeys,
                "Every shipped string must be contract-owned [\(locale)]."
            )
            for (key, value) in compiled.strings {
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) [\(locale)]")
            }
            for (key, entry) in compiled.plurals {
                let format = entry["NSStringLocalizedFormatKey"] as? String ?? ""
                XCTAssertFalse(format.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) [\(locale)]")
            }
        }
#endif
    }

    func testEnglishAndFrenchValuesAreNotFallbackKeyEchoes() throws {
#if SWIFT_PACKAGE
        let strings = try XCTUnwrap(try loadCatalog()["strings"] as? [String: Any])

        for key in publicKeys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for locale in ["en", "fr"] {
                let localization = try XCTUnwrap(localizations[locale] as? [String: Any])
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
                XCTAssertNotEqual(unit["value"] as? String, key, "\(key) [\(locale)] falls back to its key")
            }
        }
#else
        for locale in ["en", "fr"] {
            let compiled = try compiledLocalization(locale: locale)
            for key in publicKeys {
                XCTAssertNotEqual(compiled.strings[key], key, "\(key) [\(locale)] falls back to its key")
                XCTAssertNotEqual(
                    compiled.plurals[key]?["NSStringLocalizedFormatKey"] as? String,
                    key,
                    "\(key) [\(locale)] falls back to its key"
                )
            }
        }
#endif
    }

#if !SWIFT_PACKAGE
    @MainActor
    func testRasterHUDResolvesDynamicMissionAndClearanceKeys() {
        let renderer = RasterHUDRenderer()
        for mission in MissionID.allCases {
            let key = "mission.\(mission.rawValue)"
            XCTAssertNotEqual(renderer.localizedMission(mission), key, key)
        }
        for clearance in ClearanceLevel.allCases {
            let key = "clearance.\(clearance.rawValue)"
            let rendered = renderer.clearanceText(clearance)
            XCTAssertFalse(rendered.contains(key), rendered)
        }
    }

    /// Every string that prints a count has to be grammatical at one as well
    /// as at many, in both shipped locales. These are the strings a player
    /// reads on the very first attempt and on the last free rewind.
    func testCountStringsAreGrammaticalAtOneAndAtManyInEveryLocale() throws {
        let rewindsEN = try compiledFormat(locale: "en", key: "workshop.rewind.remaining")
        XCTAssertTrue(String.localizedStringWithFormat(rewindsEN, 1, 3).contains("1 free rewind left"))
        XCTAssertFalse(String.localizedStringWithFormat(rewindsEN, 1, 3).contains("rewinds"))
        XCTAssertTrue(String.localizedStringWithFormat(rewindsEN, 2, 3).contains("2 free rewinds left"))

        let rewindsFR = try compiledFormat(locale: "fr", key: "workshop.rewind.remaining")
        XCTAssertTrue(String.localizedStringWithFormat(rewindsFR, 1, 3).contains("1 rembobinage offert"))
        XCTAssertFalse(String.localizedStringWithFormat(rewindsFR, 1, 3).contains("rembobinages"))
        XCTAssertTrue(String.localizedStringWithFormat(rewindsFR, 2, 3).contains("2 rembobinages offerts"))

        let recordEN = try compiledFormat(locale: "en", key: "workshop.drills.record")
        XCTAssertTrue(String.localizedStringWithFormat(recordEN, 50, 1, 1).contains("1 attempt "))
        XCTAssertFalse(String.localizedStringWithFormat(recordEN, 50, 1, 1).contains("1 attempts"))
        XCTAssertTrue(String.localizedStringWithFormat(recordEN, 50, 4, 2).contains("4 attempts"))

        let recordFR = try compiledFormat(locale: "fr", key: "workshop.drills.record")
        XCTAssertTrue(String.localizedStringWithFormat(recordFR, 50, 1, 1).contains("1 tentative "))
        XCTAssertFalse(String.localizedStringWithFormat(recordFR, 50, 1, 1).contains("1 tentatives"))
        XCTAssertTrue(String.localizedStringWithFormat(recordFR, 50, 4, 2).contains("4 tentatives"))

        let attemptEN = try compiledFormat(locale: "en", key: "drill.hud.remaining")
        XCTAssertTrue(String.localizedStringWithFormat(attemptEN, 1).contains("1 second "))
        XCTAssertFalse(String.localizedStringWithFormat(attemptEN, 1).contains("1 seconds"))
        XCTAssertTrue(String.localizedStringWithFormat(attemptEN, 20).contains("20 seconds "))

        let attemptFR = try compiledFormat(locale: "fr", key: "drill.hud.remaining")
        XCTAssertTrue(String.localizedStringWithFormat(attemptFR, 1).contains("1 seconde restante"))
        XCTAssertFalse(String.localizedStringWithFormat(attemptFR, 1).contains("1 secondes"))
        XCTAssertTrue(String.localizedStringWithFormat(attemptFR, 20).contains("20 secondes restantes"))
    }

    /// The same three formats, resolved through the exact API the views use,
    /// in whichever language the run is executing.
    func testTheViewLookupResolvesCountFormatsInTheRunningLanguage() {
        let record = String(localized: "workshop.drills.record")
        XCTAssertNotEqual(record, "workshop.drills.record")
        let oneAttempt = String.localizedStringWithFormat(record, 50, 1, 1)
        XCTAssertFalse(oneAttempt.contains("1 attempts"), oneAttempt)
        XCTAssertFalse(oneAttempt.contains("1 tentatives"), oneAttempt)
        XCTAssertFalse(oneAttempt.contains("%#@"), oneAttempt)

        let rewinds = String(localized: "workshop.rewind.remaining")
        XCTAssertNotEqual(rewinds, "workshop.rewind.remaining")
        let oneRewind = String.localizedStringWithFormat(rewinds, 1, 3)
        XCTAssertFalse(oneRewind.contains("rewinds"), oneRewind)
        XCTAssertFalse(oneRewind.contains("rembobinages"), oneRewind)
        XCTAssertFalse(oneRewind.contains("%#@"), oneRewind)

        let attempt = String(localized: "drill.hud.remaining")
        XCTAssertNotEqual(attempt, "drill.hud.remaining")
        let oneSecond = String.localizedStringWithFormat(attempt, 1)
        XCTAssertFalse(oneSecond.contains("1 seconds"), oneSecond)
        XCTAssertFalse(oneSecond.contains("1 secondes"), oneSecond)
        XCTAssertFalse(oneSecond.contains("%#@"), oneSecond)
    }
#endif

#if SWIFT_PACKAGE
    private func loadCatalog() throws -> [String: Any] {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let catalogURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("NovaStationPinball/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
#else
    private func localizationBundle(locale: String) throws -> Bundle {
        let applicationBundle = Bundle(for: AppModel.self)
        let localizationPath = try XCTUnwrap(
            applicationBundle.path(forResource: locale, ofType: "lproj"),
            "Missing compiled \(locale) localization"
        )
        return try XCTUnwrap(Bundle(path: localizationPath))
    }

    private func compiledLocalization(
        locale: String
    ) throws -> (strings: [String: String], plurals: [String: [String: Any]]) {
        let bundle = try localizationBundle(locale: locale)
        var strings: [String: String] = [:]
        if let stringsURL = bundle.url(forResource: "Localizable", withExtension: "strings") {
            strings = try XCTUnwrap(NSDictionary(contentsOf: stringsURL) as? [String: String])
        }
        var plurals: [String: [String: Any]] = [:]
        if let pluralsURL = bundle.url(forResource: "Localizable", withExtension: "stringsdict") {
            plurals = try XCTUnwrap(NSDictionary(contentsOf: pluralsURL) as? [String: [String: Any]])
        }
        return (strings, plurals)
    }

    /// The format the app itself resolves at runtime, plural substitutions
    /// included.
    private func compiledFormat(locale: String, key: String) throws -> String {
        let bundle = try localizationBundle(locale: locale)
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        XCTAssertNotEqual(format, key, "\(key) [\(locale)] falls back to its key")
        return format
    }
#endif
}
