import UIKit
import XCTest

/// App Review capture runbook using the fixture DEBUG path, not live StoreKit
/// proof. Run this test alone on the leased iPad Pro 13-inch (M5) simulator in
/// landscapeRight. The resulting full-screen PNGs must be checked externally
/// for a 2752 x 2064 raster before ASC upload.
@MainActor
final class TipJarReviewUITests: XCTestCase {
    private struct ReviewOffer {
        let id: String
        let accessibilityIdentifier: String
        let productIdentifier: String
        let name: String
        let price: String
    }

    private let reviewOffers = [
        ReviewOffer(
            id: "tip.cafe",
            accessibilityIdentifier: "tipJarPurchase.tip.cafe",
            productIdentifier: "com.bnjdpn.NovaStationPinball.tip.cafe",
            name: "Coffee",
            price: "$0.99"
        ),
        ReviewOffer(
            id: "tip.merci",
            accessibilityIdentifier: "tipJarPurchase.tip.merci",
            productIdentifier: "com.bnjdpn.NovaStationPinball.tip.merci",
            name: "Big thanks",
            price: "$2.99"
        ),
        ReviewOffer(
            id: "tip.soutien",
            accessibilityIdentifier: "tipJarPurchase.tip.soutien",
            productIdentifier: "com.bnjdpn.NovaStationPinball.tip.soutien",
            name: "Strong support",
            price: "$5.99"
        )
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeRight
    }

    func testCapturesThreeOptionalTipReviewScreenshotsWithoutPurchasing() {
        assertCaptureDestination()

        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["NOVA_TIP_JAR_FIXTURE"] = "available"
        app.launch()

        XCTAssertEqual(XCUIDevice.shared.orientation, .landscapeRight)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let openTipJar = app.buttons["tipJarOpen"]
        XCTAssertTrue(openTipJar.waitForExistence(timeout: 5))
        XCTAssertTrue(openTipJar.isHittable)
        openTipJar.tap()

        let tipJar = app.alerts["tipJar"]
        XCTAssertTrue(tipJar.waitForExistence(timeout: 3))
        XCTAssertEqual(tipJar.label, "Optional tips")

        let optionalCopy = app.staticTexts[
            "Tips are optional and repeatable. They unlock no features or gameplay content."
        ]
        XCTAssertTrue(optionalCopy.waitForExistence(timeout: 3))
        assertFullyVisible(optionalCopy, in: app)

        for offer in reviewOffers {
            let purchaseButton = app.buttons[offer.accessibilityIdentifier]
            XCTAssertTrue(purchaseButton.waitForExistence(timeout: 5), offer.productIdentifier)
            XCTAssertTrue(purchaseButton.isHittable, offer.productIdentifier)
            XCTAssertTrue(purchaseButton.isEnabled, offer.productIdentifier)
            XCTAssertTrue(purchaseButton.label.contains(offer.name), purchaseButton.label)
            XCTAssertTrue(purchaseButton.label.contains(offer.price), purchaseButton.label)
            assertFullyVisible(purchaseButton, in: app)
        }

        XCTAssertFalse(app.staticTexts["tipJarStatus"].exists)

        // XCUI has no non-activating accessibility-focus API on iOS. Keep all
        // three offers visible and emit one truthful full-screen attachment per
        // IAP instead of tapping a purchase button merely to alter its state.
        for offer in reviewOffers {
            let purchaseButton = app.buttons[offer.accessibilityIdentifier]
            XCTAssertTrue(purchaseButton.isHittable, offer.productIdentifier)

            XCTContext.runActivity(named: "Review focus: \(offer.productIdentifier)") { activity in
                let screenshot = XCUIScreen.main.screenshot()
                assertReviewRaster(screenshot)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "iap-review-\(offer.id)-ipad-pro-13-m5-landscape"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }

        XCTAssertFalse(app.staticTexts["tipJarStatus"].exists)
        for offer in reviewOffers {
            XCTAssertTrue(
                app.buttons[offer.accessibilityIdentifier].isEnabled,
                "The capture flow must not start a purchase for \(offer.productIdentifier)"
            )
        }
    }

    private func assertCaptureDestination() {
        XCTAssertEqual(
            UIDevice.current.userInterfaceIdiom,
            .pad,
            "Run the IAP review capture on the leased iPad Pro 13-inch (M5)."
        )

    }

    private func assertReviewRaster(_ screenshot: XCUIScreenshot) {
        guard let image = screenshot.image.cgImage else {
            XCTFail("The full-screen review screenshot must expose a pixel raster.")
            return
        }

        let nativeDimensions = [image.width, image.height].sorted()
        XCTAssertEqual(
            nativeDimensions,
            [2064, 2752],
            "The capture runbook requires the iPad Pro 13-inch 2752 x 2064 raster."
        )
    }

    private func assertFullyVisible(_ element: XCUIElement, in app: XCUIApplication) {
        let appFrame = app.frame.standardized.insetBy(dx: -1, dy: -1)
        let elementFrame = element.frame.standardized
        XCTAssertFalse(elementFrame.isEmpty, "\(element) has no visible frame")
        XCTAssertTrue(appFrame.contains(elementFrame), "\(element) is clipped outside the app frame")
    }
}
