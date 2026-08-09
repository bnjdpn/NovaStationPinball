import CoreGraphics
import XCTest
@testable import NovaStationPinball

final class TouchInterpreterTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 750)

    func testInvisibleLowerZonesPressAndReleaseTheirFlippers() {
        var interpreter = TouchInterpreter()

        XCTAssertEqual(
            interpreter.events(for: [.began(id: 1, at: CGPoint(x: 120, y: 650), time: 0)], in: bounds),
            [.flipper(side: .left, isPressed: true)]
        )
        XCTAssertEqual(
            interpreter.events(for: [.began(id: 2, at: CGPoint(x: 700, y: 650), time: 0)], in: bounds),
            [.flipper(side: .right, isPressed: true)]
        )
        XCTAssertEqual(
            interpreter.events(for: [.ended(id: 1, at: CGPoint(x: 120, y: 650), time: 0.1)], in: bounds),
            [.flipper(side: .left, isPressed: false)]
        )
        XCTAssertEqual(
            interpreter.events(for: [.ended(id: 2, at: CGPoint(x: 700, y: 650), time: 0.1)], in: bounds),
            [.flipper(side: .right, isPressed: false)]
        )
    }

    func testPlungerDragReportsPullThenReleaseStrength() {
        var interpreter = TouchInterpreter()

        XCTAssertEqual(
            interpreter.events(for: [.began(id: 7, at: CGPoint(x: 950, y: 420), time: 0)], in: bounds),
            [.plungerPull(0)]
        )
        XCTAssertEqual(
            interpreter.events(for: [.moved(id: 7, at: CGPoint(x: 950, y: 645), time: 0.15)], in: bounds),
            [.plungerPull(0.75)]
        )
        XCTAssertEqual(
            interpreter.events(for: [.ended(id: 7, at: CGPoint(x: 950, y: 645), time: 0.2)], in: bounds),
            [.plungerReleased(0.75)]
        )
    }

    func testShortHorizontalUpperGestureProducesNudge() {
        var interpreter = TouchInterpreter()

        XCTAssertEqual(
            interpreter.events(for: [.began(id: 3, at: CGPoint(x: 300, y: 200), time: 1)], in: bounds),
            []
        )
        XCTAssertEqual(
            interpreter.events(for: [.ended(id: 3, at: CGPoint(x: 380, y: 210), time: 1.18)], in: bounds),
            [.nudge(x: 0.8)]
        )
    }

    func testSecondTouchCancelsActivePlungerGesture() {
        var interpreter = TouchInterpreter()
        _ = interpreter.events(
            for: [.began(id: 7, at: CGPoint(x: 950, y: 420), time: 0)],
            in: bounds
        )

        XCTAssertEqual(
            interpreter.events(for: [.began(id: 8, at: CGPoint(x: 400, y: 200), time: 0.1)], in: bounds),
            [.cancelGestures]
        )
        XCTAssertEqual(
            interpreter.events(for: [.ended(id: 7, at: CGPoint(x: 950, y: 645), time: 0.2)], in: bounds),
            []
        )
    }

    func testSimultaneousGestureBeginsAreOrderInvariantAndNeverStartPlunger() {
        let plunger = TouchSample.began(
            id: 7,
            at: CGPoint(x: 950, y: 420),
            time: 2
        )
        let upperTouch = TouchSample.began(
            id: 8,
            at: CGPoint(x: 400, y: 200),
            time: 2
        )

        var forward = TouchInterpreter()
        var reversed = TouchInterpreter()
        let forwardEvents = forward.events(for: [plunger, upperTouch], in: bounds)
        let reversedEvents = reversed.events(for: [upperTouch, plunger], in: bounds)

        XCTAssertEqual(forwardEvents, [.cancelGestures])
        XCTAssertEqual(reversedEvents, [.cancelGestures])
        XCTAssertEqual(forwardEvents, reversedEvents)
    }
}
