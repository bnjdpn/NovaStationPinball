public enum StableHasherError: Error, Sendable, Equatable {
    case invalidVersion(Int)
}

public struct StableHasher: Sendable {
    public static let currentVersion = 1

    private static let offsetBasis: UInt64 = 0xcbf29ce484222325
    private static let prime: UInt64 = 0x100000001b3
    private let version: Int
    private var state: UInt64

    public init(version: Int = StableHasher.currentVersion) throws {
        guard version > 0 else { throw StableHasherError.invalidVersion(version) }
        self.version = version
        var initial = Self.offsetBasis
        Self.append(bytes: Array("NovaStationPinball.StableHasher".utf8), to: &initial)
        Self.append(integer: UInt64(version), to: &initial)
        self.state = initial
    }

    public mutating func combine(_ value: String) {
        combine(bytes: Array(value.utf8))
    }

    public mutating func combine(bytes: [UInt8]) {
        Self.append(integer: UInt64(bytes.count), to: &state)
        Self.append(bytes: bytes, to: &state)
    }

    public func finalize() -> String {
        let hexadecimal = String(state, radix: 16)
        let padded = String(repeating: "0", count: max(0, 16 - hexadecimal.count)) + hexadecimal
        return "nova-station-h\(version)-\(padded)"
    }

    private static func append(integer: UInt64, to state: inout UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            append(byte: UInt8(truncatingIfNeeded: integer >> UInt64(shift)), to: &state)
        }
    }

    private static func append(bytes: [UInt8], to state: inout UInt64) {
        for byte in bytes { append(byte: byte, to: &state) }
    }

    private static func append(byte: UInt8, to state: inout UInt64) {
        state ^= UInt64(byte)
        state &*= prime
    }
}
