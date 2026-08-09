import CoreGraphics
import Foundation

enum FlipperSide: Equatable {
    case left
    case right
}

enum PinballControlEvent: Equatable {
    case flipper(side: FlipperSide, isPressed: Bool)
    case plungerPull(Double)
    case plungerReleased(Double)
    case nudge(x: Double)
    case cancelGestures
}

struct TouchSample: Equatable {
    enum Phase: Equatable {
        case began
        case moved
        case ended
        case cancelled
    }

    let id: Int
    let phase: Phase
    let location: CGPoint
    let timestamp: TimeInterval

    static func began(id: Int, at location: CGPoint, time: TimeInterval) -> Self {
        Self(id: id, phase: .began, location: location, timestamp: time)
    }

    static func moved(id: Int, at location: CGPoint, time: TimeInterval) -> Self {
        Self(id: id, phase: .moved, location: location, timestamp: time)
    }

    static func ended(id: Int, at location: CGPoint, time: TimeInterval) -> Self {
        Self(id: id, phase: .ended, location: location, timestamp: time)
    }

    static func cancelled(id: Int, at location: CGPoint, time: TimeInterval) -> Self {
        Self(id: id, phase: .cancelled, location: location, timestamp: time)
    }
}

struct TouchInterpreter {
    private struct GestureStart {
        enum Kind {
            case plunger
            case nudge
        }

        let id: Int
        let location: CGPoint
        let timestamp: TimeInterval
        let kind: Kind
    }

    private var activeTouchIDs: Set<Int> = []
    private var activeFlippers: [Int: FlipperSide] = [:]
    private var gesture: GestureStart?
    private var latestPlungerPull = 0.0

    mutating func events(for samples: [TouchSample], in bounds: CGRect) -> [PinballControlEvent] {
        var events: [PinballControlEvent] = []
        let orderedSamples = samples.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id < $1.id
        }
        let beganSamples = orderedSamples.filter { $0.phase == .began }
        let projectedTouchCount = activeTouchIDs.union(beganSamples.map(\.id)).count
        let batchStartsExclusiveGesture = beganSamples.contains {
            flipperSide(at: $0.location, in: bounds) == nil
                && ($0.location.x >= bounds.minX + bounds.width * 0.88
                    || $0.location.y < bounds.minY + bounds.height * 0.60)
        }
        let suppressExclusiveGesture = projectedTouchCount > 1
            && (gesture != nil || batchStartsExclusiveGesture)

        if suppressExclusiveGesture {
            gesture = nil
            latestPlungerPull = 0
            events.append(.cancelGestures)
        }

        for sample in orderedSamples {
            switch sample.phase {
            case .began:
                activeTouchIDs.insert(sample.id)

                if let side = flipperSide(at: sample.location, in: bounds) {
                    activeFlippers[sample.id] = side
                    events.append(.flipper(side: side, isPressed: true))
                } else if suppressExclusiveGesture {
                    continue
                } else if sample.location.x >= bounds.minX + bounds.width * 0.88 {
                    gesture = GestureStart(
                        id: sample.id,
                        location: sample.location,
                        timestamp: sample.timestamp,
                        kind: .plunger
                    )
                    latestPlungerPull = 0
                    events.append(.plungerPull(0))
                } else if sample.location.y < bounds.minY + bounds.height * 0.60 {
                    gesture = GestureStart(
                        id: sample.id,
                        location: sample.location,
                        timestamp: sample.timestamp,
                        kind: .nudge
                    )
                }

            case .moved:
                guard let gesture, gesture.id == sample.id else { continue }
                if gesture.kind == .plunger {
                    latestPlungerPull = plungerPull(
                        from: gesture.location,
                        to: sample.location,
                        in: bounds
                    )
                    events.append(.plungerPull(latestPlungerPull))
                }

            case .ended, .cancelled:
                activeTouchIDs.remove(sample.id)
                if let side = activeFlippers.removeValue(forKey: sample.id) {
                    events.append(.flipper(side: side, isPressed: false))
                }
                guard let gesture, gesture.id == sample.id else { continue }
                self.gesture = nil
                if sample.phase == .cancelled {
                    latestPlungerPull = 0
                    events.append(.cancelGestures)
                } else {
                    switch gesture.kind {
                    case .plunger:
                        let pull = plungerPull(
                            from: gesture.location,
                            to: sample.location,
                            in: bounds
                        )
                        latestPlungerPull = 0
                        events.append(.plungerReleased(pull))
                    case .nudge:
                        let duration = sample.timestamp - gesture.timestamp
                        let deltaX = sample.location.x - gesture.location.x
                        let deltaY = sample.location.y - gesture.location.y
                        if duration >= 0, duration <= 0.25,
                           abs(deltaX) >= bounds.width * 0.04,
                           abs(deltaX) <= bounds.width * 0.12,
                           abs(deltaY) <= bounds.height * 0.04 {
                            events.append(.nudge(x: Double(deltaX / (bounds.width * 0.10))))
                        }
                    }
                }
            }
        }

        return events
    }

    private func flipperSide(at point: CGPoint, in bounds: CGRect) -> FlipperSide? {
        guard point.y >= bounds.minY + bounds.height * 0.60,
              point.x < bounds.minX + bounds.width * 0.88 else {
            return nil
        }
        return point.x < bounds.midX ? .left : .right
    }

    private func plungerPull(from start: CGPoint, to current: CGPoint, in bounds: CGRect) -> Double {
        let travel = max(1, bounds.height * 0.40)
        return min(1, max(0, Double((current.y - start.y) / travel)))
    }
}
