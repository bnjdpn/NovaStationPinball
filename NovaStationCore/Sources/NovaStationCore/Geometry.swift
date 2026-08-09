public struct Vector2: Sendable, Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vector2(x: 0, y: 0)

    public static func + (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static prefix func - (value: Vector2) -> Vector2 {
        Vector2(x: -value.x, y: -value.y)
    }

    public static func * (lhs: Vector2, rhs: Double) -> Vector2 {
        Vector2(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public static func * (lhs: Double, rhs: Vector2) -> Vector2 {
        rhs * lhs
    }

    public static func / (lhs: Vector2, rhs: Double) -> Vector2 {
        Vector2(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    public func dot(_ other: Vector2) -> Double {
        x * other.x + y * other.y
    }

    public var lengthSquared: Double {
        dot(self)
    }

    public var length: Double {
        lengthSquared.squareRoot()
    }

    public func distance(to other: Vector2) -> Double {
        (self - other).length
    }

    public var normalized: Vector2 {
        let magnitude = length
        return magnitude > 0 ? self / magnitude : .zero
    }

    public var leftPerpendicular: Vector2 {
        Vector2(x: -y, y: x)
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite
    }
}
