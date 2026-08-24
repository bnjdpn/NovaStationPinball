import XCTest

extension XCTestCase {
    /// The Workshop list is taller than its own viewport, so a row has to be
    /// brought inside that viewport before it can be tapped. Dragging without
    /// a flick keeps every step deterministic. Each move is exactly half of
    /// the viewport: a tall Dynamic Type row can therefore cross either edge
    /// without oscillating from wholly above to wholly below the viewport.
    @MainActor
    func scrollIntoView(
        _ element: XCUIElement,
        in scroll: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "no scroll view", file: file, line: line)
        for _ in 0..<30 {
            let viewport = scroll.frame
            let centre = CGPoint(x: element.frame.midX, y: element.frame.midY)
            if viewport.contains(centre) { return }
            let below = centre.y > viewport.midY
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.75 : 0.25))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.25 : 0.75))
            from.press(forDuration: 0.08, thenDragTo: to)
        }
        XCTFail(
            "\(element.identifier) never came into view: \(element.frame) in \(scroll.frame)",
            file: file,
            line: line
        )
    }

    /// Opens the Workshop and starts one attempt of `drillIdentifier`.
    @MainActor
    func startDrill(_ drillIdentifier: String, in app: XCUIApplication) {
        let open = app.buttons["workshopOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let drill = app.buttons["workshopDrill.\(drillIdentifier)"]
        XCTAssertTrue(drill.waitForExistence(timeout: 5))
        scrollIntoView(drill, in: app.scrollViews["workshopScroll"])
        drill.tap()
        XCTAssertTrue(app.otherElements["workshopDrillHUD"].waitForExistence(timeout: 5))
    }
}
