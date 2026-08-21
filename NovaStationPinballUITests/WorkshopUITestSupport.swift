import XCTest

extension XCTestCase {
    /// The Workshop list is taller than its own viewport, so a row has to be
    /// brought inside that viewport before it can be tapped. Dragging without
    /// a flick keeps every step small enough not to jump over the row.
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
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.9 : 0.1))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.1 : 0.9))
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
