import StoreKitTest
import UIKit
import XCTest

/// App Review capture runbook for the single in-app purchase. Run this test
/// alone on the leased iPad Pro 13-inch (M5) simulator in landscapeRight —
/// `scripts/capture_paywall_review_screenshot.rb` does exactly that. The
/// resulting full-screen PNG is validated here for the 2752 x 2064 raster
/// before it ever reaches App Store Connect.
///
/// The capture deliberately runs WITHOUT the store bypass
/// (`-paywall-screenshot` disables it), so App Review sees the real locked
/// paywall: the offer name and price, the one-time-purchase disclosure,
/// Restore, and both legal links.
///
/// The offer comes from StoreKit itself, driven by `SKTestSession` loading
/// `NovaStationPinball.storekit` out of the UI test bundle and pinned to the
/// base territory of `fastlane/pro_products.json`. Two routes were tried and
/// rejected before this one:
///
///   * the scheme's `run.storeKitConfiguration` — `xcodebuild test` never
///     applies it (it belongs to the Run action alone), so the app under test
///     queried the live App Store catalogue and photographed whatever price
///     App Store Connect happened to carry;
///   * a DEBUG fixture backend with a hard-coded `$4.99` — a capture that
///     cannot disagree with the spec also cannot detect that it disagrees, and
///     it stated a currency the base territory does not use.
///
/// Sourcing the price from the `.storekit` file makes the capture a function
/// of this repository. Whether App Store Connect agrees with the repository is
/// a separate question, answered by the ASC readback, not by a screenshot.
@MainActor
final class PaywallReviewUITests: XCTestCase {
    private let productIdentifier = "com.bnjdpn.NovaStationPinball.workshop"
    private let offerName = "The Workshop"

    /// Attachment names read back by `scripts/capture_paywall_review_screenshot.rb`.
    static let screenshotAttachmentName = "iap-review-workshop-ipad-pro-13-m5-landscape"
    static let priceAttachmentName = "iap-review-workshop-price"

    /// `base_territory` in `fastlane/pro_products.json`. The base territory is
    /// the only storefront where the displayed price is the spec's
    /// `base_price` itself rather than an equalization of it.
    private static let baseTerritory = "FRA"

    private var storeSession: SKTestSession?

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeRight

        let session = try SKTestSession(configurationFileNamed: "NovaStationPinball")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = Self.baseTerritory
        storeSession = session
    }

    override func tearDownWithError() throws {
        // The session owns simulator-wide StoreKit state. Leaving it behind
        // would silently change what every later test on this simulator sees.
        storeSession?.resetToDefaultState()
        storeSession = nil
    }

    func testCapturesTheWorkshopPaywallForReviewWithoutPurchasing() {
        assertCaptureDestination()

        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-paywall-screenshot",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertEqual(XCUIDevice.shared.orientation, .landscapeRight)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let paywall = app.alerts["paywall"]
        XCTAssertTrue(paywall.waitForExistence(timeout: 8))
        XCTAssertEqual(paywall.label, offerName)

        let purchaseButton = app.buttons["paywallPurchase"]
        guard purchaseButton.waitForExistence(timeout: 30) else {
            // A capture published without the offer is a rejected in-app
            // purchase: App Review reports "we were unable to locate the
            // in-app purchase". When the offer never loads, say what was on
            // screen instead of leaving a bare boolean behind.
            attach(name: "paywall-capture-failure-hierarchy", string: app.debugDescription)
            attach(name: "paywall-capture-failure-screen", screenshot: XCUIScreen.main.screenshot())
            XCTFail(
                "The review capture must show the loaded StoreKit offer, never the loading or "
                + "unavailable state. Loading state on screen: "
                + "\(element(app, "paywallOfferLoading").exists), unavailable state on screen: "
                + "\(element(app, "paywallOfferUnavailable").exists)"
            )
            return
        }
        XCTAssertFalse(element(app, "paywallOfferLoading").exists, productIdentifier)
        XCTAssertFalse(element(app, "paywallOfferUnavailable").exists, productIdentifier)
        XCTAssertTrue(purchaseButton.isHittable, productIdentifier)
        XCTAssertTrue(purchaseButton.isEnabled, productIdentifier)
        XCTAssertTrue(purchaseButton.label.contains(offerName), purchaseButton.label)
        assertFullyVisible(purchaseButton, in: app)

        let restoreButton = app.buttons["paywallRestore"]
        XCTAssertTrue(restoreButton.exists)
        assertFullyVisible(restoreButton, in: app)

        let disclosure = app.staticTexts["paywallTerms"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        assertFullyVisible(disclosure, in: app)
        XCTAssertTrue(element(app, "paywallTermsLink").waitForExistence(timeout: 3))
        XCTAssertTrue(element(app, "paywallPrivacyLink").waitForExistence(timeout: 3))

        // `paywallStatus` is the "already owned" / purchase-outcome line. Its
        // absence is what proves the capture shows an offer to buy rather than
        // a purchase already made.
        XCTAssertFalse(app.staticTexts["paywallStatus"].exists)

        // The purchase button carries `Product.displayPrice` inside its
        // accessibility label, so this reads the exact string a buyer sees —
        // and the exact string rendered on the PNG below.
        let displayedPrice = priceFragment(of: purchaseButton.label)
        XCTAssertFalse(
            displayedPrice.isEmpty,
            "The purchase button must expose Product.displayPrice; without it the capture "
            + "cannot be checked against fastlane/pro_products.json. Label was "
            + purchaseButton.label
        )

        XCTContext.runActivity(named: "Review focus: \(productIdentifier)") { activity in
            let screenshot = XCUIScreen.main.screenshot()
            assertReviewRaster(screenshot)
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = Self.screenshotAttachmentName
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        attach(name: Self.priceAttachmentName, string: displayedPrice)

        // The capture flow never starts a purchase: the button is still armed
        // and no purchase status has been produced.
        XCTAssertTrue(purchaseButton.isEnabled)
        XCTAssertFalse(app.staticTexts["paywallStatus"].exists)
    }

    /// "The Workshop, €4.99" -> "€4.99". The label is built by the paywall as
    /// `"\(displayName), \(displayPrice)"`, and the display name comes from the
    /// same `.storekit` catalogue, so the tail after the last separator is the
    /// price and nothing else.
    private func priceFragment(of label: String) -> String {
        guard let separator = label.range(of: ", ", options: .backwards) else { return "" }
        let tail = label[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        return tail.rangeOfCharacter(from: .decimalDigits) == nil ? "" : tail
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func attach(name: String, screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(name: String, string: String) {
        let attachment = XCTAttachment(string: string)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
