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
        "status.audio_interrupted",
        "status.ball_launched",
        "status.game_over",
        "status.gesture_cancelled",
        "status.mission",
        "status.multiball",
        "status.nudge",
        "status.paused",
        "status.plunger_charging",
        "status.promotion",
        "status.restored",
        "status.system_ready",
        "status.tilt"
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
        for locale in ["en", "fr"] {
            let strings = try compiledStrings(locale: locale)
            XCTAssertEqual(Set(strings.keys), publicKeys, "Every shipped string must be contract-owned [\(locale)].")
            for key in publicKeys {
                let value = try XCTUnwrap(strings[key], "\(key) [\(locale)]")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) [\(locale)]")
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
            let strings = try compiledStrings(locale: locale)
            for key in publicKeys {
                XCTAssertNotEqual(strings[key], key, "\(key) [\(locale)] falls back to its key")
            }
        }
#endif
    }

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
    private func compiledStrings(locale: String) throws -> [String: String] {
        let applicationBundle = Bundle(for: AppModel.self)
        let localizationPath = try XCTUnwrap(
            applicationBundle.path(forResource: locale, ofType: "lproj"),
            "Missing compiled \(locale) localization"
        )
        let localizationBundle = try XCTUnwrap(Bundle(path: localizationPath))
        let stringsURL = try XCTUnwrap(
            localizationBundle.url(forResource: "Localizable", withExtension: "strings")
        )
        return try XCTUnwrap(NSDictionary(contentsOf: stringsURL) as? [String: String])
    }
#endif
}
