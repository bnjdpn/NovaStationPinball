import Foundation

public struct SweepHit: Sendable, Codable, Equatable {
    public var time: Double
    public var center: Vector2
    public var point: Vector2
    public var normal: Vector2
    public var startedOverlapping: Bool

    public init(
        time: Double,
        center: Vector2,
        point: Vector2,
        normal: Vector2,
        startedOverlapping: Bool = false
    ) {
        self.time = time
        self.center = center
        self.point = point
        self.normal = normal
        self.startedOverlapping = startedOverlapping
    }
}

public struct SegmentCollider: Sendable, Codable, Equatable {
    public var start: Vector2
    public var end: Vector2
    public var radius: Double
    public var restitution: Double

    public init(start: Vector2, end: Vector2, radius: Double, restitution: Double = 1) {
        self.start = start
        self.end = end
        self.radius = radius
        self.restitution = restitution
    }
}

public struct CircleCollider: Sendable, Codable, Equatable {
    public var center: Vector2
    public var radius: Double
    public var restitution: Double

    public init(center: Vector2, radius: Double, restitution: Double = 1) {
        self.center = center
        self.radius = radius
        self.restitution = restitution
    }
}

public struct ArcCollider: Sendable, Codable, Equatable {
    public var center: Vector2
    public var radius: Double
    public var startAngle: Double
    public var endAngle: Double
    public var thickness: Double
    public var restitution: Double

    public init(
        center: Vector2,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        thickness: Double,
        restitution: Double = 1
    ) {
        self.center = center
        self.radius = radius
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.thickness = thickness
        self.restitution = restitution
    }
}

public enum CollisionShape: Sendable, Codable, Equatable {
    case segment(SegmentCollider)
    case circle(CircleCollider)
    case arc(ArcCollider)

    public var restitution: Double {
        switch self {
        case .segment(let collider): collider.restitution
        case .circle(let collider): collider.restitution
        case .arc(let collider): collider.restitution
        }
    }
}

public enum ContinuousCollision {
    private static let epsilon = 1e-12

    public static func sweepCircle(
        from start: Vector2,
        displacement: Vector2,
        radius: Double,
        against shape: CollisionShape
    ) -> SweepHit? {
        switch shape {
        case .segment(let segment):
            return sweepSegment(from: start, displacement: displacement, radius: radius, segment: segment)
        case .circle(let circle):
            return sweepStaticCircle(
                from: start,
                displacement: displacement,
                movingRadius: radius,
                center: circle.center,
                staticRadius: circle.radius
            )
        case .arc(let arc):
            return sweepArc(from: start, displacement: displacement, radius: radius, arc: arc)
        }
    }

    public static func resolvedVelocity(
        _ velocity: Vector2,
        normal: Vector2,
        restitution: Double
    ) -> Vector2 {
        let unitNormal = normal.normalized
        let incomingSpeed = velocity.dot(unitNormal)
        guard incomingSpeed < 0 else { return velocity }
        let clampedRestitution = min(max(restitution, 0), 1)
        return velocity - unitNormal * ((1 + clampedRestitution) * incomingSpeed)
    }

    private static func sweepSegment(
        from start: Vector2,
        displacement: Vector2,
        radius: Double,
        segment: SegmentCollider
    ) -> SweepHit? {
        let axis = segment.end - segment.start
        let length = axis.length
        guard length > epsilon else {
            return sweepStaticCircle(
                from: start,
                displacement: displacement,
                movingRadius: radius,
                center: segment.start,
                staticRadius: segment.radius
            )
        }

        let tangent = axis / length
        let perpendicular = tangent.leftPerpendicular
        let expandedRadius = max(0, radius) + max(0, segment.radius)
        let initialOffset = start - segment.start
        let initialDistance = initialOffset.dot(perpendicular)
        let normalSpeed = displacement.dot(perpendicular)
        var candidates: [SweepHit] = []

        if abs(normalSpeed) > epsilon {
            for signedRadius in [-expandedRadius, expandedRadius] {
                let time = (signedRadius - initialDistance) / normalSpeed
                guard time >= 0, time <= 1 else { continue }
                let center = start + displacement * time
                let along = (center - segment.start).dot(tangent)
                guard along >= 0, along <= length else { continue }
                let normal = signedRadius >= 0 ? perpendicular : -perpendicular
                let axisPoint = segment.start + tangent * along
                candidates.append(
                    SweepHit(
                        time: time,
                        center: center,
                        point: axisPoint + normal * max(0, segment.radius),
                        normal: normal
                    )
                )
            }
        }

        for endpoint in [segment.start, segment.end] {
            if let hit = sweepStaticCircle(
                from: start,
                displacement: displacement,
                movingRadius: radius,
                center: endpoint,
                staticRadius: segment.radius
            ) {
                candidates.append(hit)
            }
        }

        if let overlap = segmentOverlap(
            center: start,
            movingRadius: radius,
            segment: segment,
            tangent: tangent,
            length: length
        ) {
            candidates.append(overlap)
        }

        return candidates.min { lhs, rhs in
            if abs(lhs.time - rhs.time) <= epsilon {
                return lhs.point.x == rhs.point.x ? lhs.point.y < rhs.point.y : lhs.point.x < rhs.point.x
            }
            return lhs.time < rhs.time
        }
    }

    private static func segmentOverlap(
        center: Vector2,
        movingRadius: Double,
        segment: SegmentCollider,
        tangent: Vector2,
        length: Double
    ) -> SweepHit? {
        let projection = min(max((center - segment.start).dot(tangent), 0), length)
        let axisPoint = segment.start + tangent * projection
        let offset = center - axisPoint
        let expandedRadius = max(0, movingRadius) + max(0, segment.radius)
        let distance = offset.length
        guard expandedRadius - distance > epsilon else { return nil }
        let stableNormal = distance > epsilon ? offset / distance : tangent.leftPerpendicular
        return SweepHit(
            time: 0,
            center: axisPoint + stableNormal * expandedRadius,
            point: axisPoint + stableNormal * max(0, segment.radius),
            normal: stableNormal,
            startedOverlapping: true
        )
    }

    private static func sweepStaticCircle(
        from start: Vector2,
        displacement: Vector2,
        movingRadius: Double,
        center staticCenter: Vector2,
        staticRadius: Double
    ) -> SweepHit? {
        let combinedRadius = max(0, movingRadius) + max(0, staticRadius)
        let offset = start - staticCenter
        let c = offset.lengthSquared - combinedRadius * combinedRadius

        if c < -epsilon {
            let normal = offset.length > epsilon ? offset.normalized : Vector2(x: 1, y: 0)
            return SweepHit(
                time: 0,
                center: staticCenter + normal * combinedRadius,
                point: staticCenter + normal * max(0, staticRadius),
                normal: normal,
                startedOverlapping: true
            )
        }

        if abs(c) <= epsilon {
            let normal = offset.length > epsilon ? offset.normalized : Vector2(x: 1, y: 0)
            guard displacement.dot(normal) < -epsilon else { return nil }
            return SweepHit(
                time: 0,
                center: start,
                point: staticCenter + normal * max(0, staticRadius),
                normal: normal
            )
        }

        let a = displacement.lengthSquared
        guard a > epsilon else { return nil }
        let b = 2 * offset.dot(displacement)
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return nil }
        let time = (-b - discriminant.squareRoot()) / (2 * a)
        guard time >= 0, time <= 1 else { return nil }
        let movingCenter = start + displacement * time
        let normal = (movingCenter - staticCenter).normalized
        return SweepHit(
            time: time,
            center: movingCenter,
            point: staticCenter + normal * max(0, staticRadius),
            normal: normal
        )
    }

    private static func sweepArc(
        from start: Vector2,
        displacement: Vector2,
        radius: Double,
        arc: ArcCollider
    ) -> SweepHit? {
        var candidates: [SweepHit] = []
        let halfThickness = max(0, arc.thickness) / 2
        let expandedHalfThickness = halfThickness + max(0, radius)
        let radialOffset = start - arc.center
        let radialDistance = radialOffset.length
        let fallbackAngle = arc.startAngle + (arc.endAngle - arc.startAngle) / 2
        let radial = radialDistance > epsilon
            ? radialOffset / radialDistance
            : Vector2(x: cos(fallbackAngle), y: sin(fallbackAngle))
        if expandedHalfThickness - abs(radialDistance - arc.radius) > epsilon,
           angle(radial, isWithin: arc) {
            let hasInnerFreeRegion = expandedHalfThickness < arc.radius
            let useOuterFace = !hasInnerFreeRegion || radialDistance >= arc.radius
            let normal = useOuterFace ? radial : -radial
            let resolvedRadius = useOuterFace
                ? arc.radius + expandedHalfThickness
                : max(0, arc.radius - expandedHalfThickness)
            candidates.append(
                SweepHit(
                    time: 0,
                    center: arc.center + radial * resolvedRadius,
                    point: arc.center + radial * arc.radius,
                    normal: normal,
                    startedOverlapping: true
                )
            )
        }
        let outerRadius = max(0, arc.radius) + halfThickness + max(0, radius)
        candidates.append(contentsOf: radialBoundaryHits(
            from: start,
            displacement: displacement,
            boundaryRadius: outerRadius,
            arc: arc,
            outwardNormal: true
        ))
        let innerRadius = max(0, max(0, arc.radius) - halfThickness - max(0, radius))
        if innerRadius > epsilon {
            candidates.append(contentsOf: radialBoundaryHits(
                from: start,
                displacement: displacement,
                boundaryRadius: innerRadius,
                arc: arc,
                outwardNormal: false
            ))
        }

        let startPoint = arc.center + Vector2(x: cos(arc.startAngle), y: sin(arc.startAngle)) * arc.radius
        let endPoint = arc.center + Vector2(x: cos(arc.endAngle), y: sin(arc.endAngle)) * arc.radius
        for endpoint in [startPoint, endPoint] {
            if let hit = sweepStaticCircle(
                from: start,
                displacement: displacement,
                movingRadius: radius,
                center: endpoint,
                staticRadius: halfThickness
            ) {
                candidates.append(hit)
            }
        }

        return candidates.min { $0.time < $1.time }
    }

    private static func radialBoundaryHits(
        from start: Vector2,
        displacement: Vector2,
        boundaryRadius: Double,
        arc: ArcCollider,
        outwardNormal: Bool
    ) -> [SweepHit] {
        let offset = start - arc.center
        let a = displacement.lengthSquared
        guard a > epsilon else { return [] }
        let b = 2 * offset.dot(displacement)
        let c = offset.lengthSquared - boundaryRadius * boundaryRadius
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return [] }
        let root = discriminant.squareRoot()
        return [(-b - root) / (2 * a), (-b + root) / (2 * a)].compactMap { time in
            guard time >= 0, time <= 1 else { return nil }
            let center = start + displacement * time
            let radial = (center - arc.center).normalized
            guard radial != .zero, angle(radial, isWithin: arc) else { return nil }
            let normal = outwardNormal ? radial : -radial
            guard displacement.dot(normal) < -epsilon else { return nil }
            return SweepHit(
                time: time,
                center: center,
                point: arc.center + radial * arc.radius,
                normal: normal
            )
        }
    }

    private static func angle(_ vector: Vector2, isWithin arc: ArcCollider) -> Bool {
        let fullTurn = 2 * Double.pi
        func normalized(_ value: Double) -> Double {
            let remainder = value.truncatingRemainder(dividingBy: fullTurn)
            return remainder >= 0 ? remainder : remainder + fullTurn
        }
        let candidate = normalized(atan2(vector.y, vector.x))
        let start = normalized(arc.startAngle)
        let end = normalized(arc.endAngle)
        return start <= end ? candidate >= start && candidate <= end : candidate >= start || candidate <= end
    }
}
