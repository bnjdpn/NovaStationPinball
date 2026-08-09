/// Pixel-space contract shared by the ImageGen 2048×1536 guide, production
/// physics and SpriteKit rendering. Pixel coordinates use the same bottom-left
/// origin as the greybox exporter and the logical table is 1×2 units.
public struct TableVisualAnchor: Sendable, Codable, Equatable {
    public let id: String
    public let pixelX: Double
    public let pixelY: Double

    public init(id: String, pixelX: Double, pixelY: Double) {
        self.id = id
        self.pixelX = pixelX
        self.pixelY = pixelY
    }

    public var logicalPoint: Vector2 {
        Vector2(
            x: pixelX / TableVisualLayout.tablePixelWidth,
            y: pixelY / Double(TableVisualLayout.canvasHeight) * 2
        )
    }
}

public enum TableVisualLayout {
    public static let canvasWidth = 2_048
    public static let canvasHeight = 1_536
    public static let tablePixelWidth = 1_433.6

    // Exact anchors emitted by scripts/export_greybox_guide.swift.
    public static let bumpers = [
        TableVisualAnchor(id: "bumper-orbit", pixelX: 510, pixelY: 1_065),
        TableVisualAnchor(id: "bumper-relay", pixelX: 865, pixelY: 1_065),
        TableVisualAnchor(id: "bumper-core", pixelX: 687, pixelY: 800)
    ]
    public static let targetBank = [
        TableVisualAnchor(id: "mission-select", pixelX: 401, pixelY: 1_320),
        TableVisualAnchor(id: "mission-start", pixelX: 606, pixelY: 1_320),
        TableVisualAnchor(id: "mission-acknowledge", pixelX: 811, pixelY: 1_320),
        TableVisualAnchor(id: "target-bank", pixelX: 1_016, pixelY: 1_320)
    ]
    public static let leftFlipperPivot = TableVisualAnchor(id: "flipper-left", pixelX: 390, pixelY: 315)
    public static let rightFlipperPivot = TableVisualAnchor(id: "flipper-right", pixelX: 1_010, pixelY: 315)
    public static let plunger = TableVisualAnchor(id: "plunger", pixelX: 1_342.6, pixelY: 222.5)
    public static let missionSelectLane = TableVisualAnchor(id: "mission-select", pixelX: 1_342.6, pixelY: 368.64)
    public static let missionStartLane = TableVisualAnchor(id: "mission-start", pixelX: 1_342.6, pixelY: 522.24)
    public static let missionAcknowledgeLane = TableVisualAnchor(id: "mission-acknowledge", pixelX: 1_342.6, pixelY: 422.4)

    // Anchors inspected against Art/QA/table-guide-overlay.png. They describe
    // existing visible portal, ramps, lamps and lanes; they do not invent art.
    public static let portal = TableVisualAnchor(id: "portal", pixelX: 687, pixelY: 1_165)
    public static let rampLeft = TableVisualAnchor(id: "ramp-left", pixelX: 215, pixelY: 930)
    public static let rampRight = TableVisualAnchor(id: "ramp-right", pixelX: 1_225, pixelY: 930)
    public static let returnLeft = TableVisualAnchor(id: "return-left", pixelX: 310, pixelY: 610)
    public static let returnCenter = TableVisualAnchor(id: "return-center", pixelX: 687, pixelY: 625)
    public static let returnRight = TableVisualAnchor(id: "return-right", pixelX: 1_000, pixelY: 610)
    public static let rolloverLeft = TableVisualAnchor(id: "rollover-left", pixelX: 305, pixelY: 770)
    public static let rolloverCenter = TableVisualAnchor(id: "rollover-center", pixelX: 687, pixelY: 705)
    public static let rolloverRight = TableVisualAnchor(id: "rollover-right", pixelX: 1_070, pixelY: 770)
    public static let outerLeft = TableVisualAnchor(id: "outer-left", pixelX: 175, pixelY: 820)
    public static let outerRight = TableVisualAnchor(id: "outer-right", pixelX: 1_210, pixelY: 820)
    public static let bonus = TableVisualAnchor(id: "bonus-bank", pixelX: 380, pixelY: 690)
    public static let scoreMultiplier = TableVisualAnchor(id: "score-multiplier", pixelX: 995, pixelY: 690)
    public static let bonusMultiplier = TableVisualAnchor(id: "bonus-multiplier", pixelX: 380, pixelY: 615)
    public static let extraBall = TableVisualAnchor(id: "extra-ball", pixelX: 1_010, pixelY: 530)
    public static let multiball = TableVisualAnchor(id: "multiball", pixelX: 687, pixelY: 865)
    public static let stationPower = TableVisualAnchor(id: "station-power", pixelX: 687, pixelY: 990)
    public static let drain = TableVisualAnchor(id: "drain", pixelX: 687, pixelY: 105)

    public static let genericSensors: [TableVisualAnchor] = [
        portal, rampLeft, rampRight,
        returnLeft, returnCenter, returnRight,
        rolloverLeft, rolloverCenter, rolloverRight,
        outerLeft, outerRight,
        bonus, scoreMultiplier, bonusMultiplier, extraBall, multiball, stationPower,
        drain
    ]
}
