import Foundation
import Security

/// 120-bit shared secret, shown as six groups of four Crockford base32
/// characters. Used as the TLS pre-shared key.
public struct PairingKey: Equatable, Sendable {
    public static let byteCount = 15  // 15 bytes = 120 bits = 24 base32 chars

    public let data: Data

    public init?(data: Data) {
        guard data.count == Self.byteCount else { return nil }
        self.data = data
    }

    public static func generate() -> PairingKey {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return PairingKey(data: Data(bytes))!
    }

    /// Parses user input. Ignores case, dashes and whitespace; accepts the
    /// Crockford aliases (I,L -> 1; O -> 0).
    public init?(displayString: String) {
        var bits: UInt64 = 0
        var bitCount = 0
        var bytes: [UInt8] = []
        var chars = 0
        for ch in displayString.uppercased() where ch != "-" && !ch.isWhitespace {
            guard let v = Self.decodeTable[ch] else { return nil }
            chars += 1
            bits = (bits << 5) | UInt64(v)
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                bytes.append(UInt8((bits >> UInt64(bitCount)) & 0xFF))
                bits &= (1 << UInt64(bitCount)) - 1
            }
        }
        guard chars == Self.byteCount * 8 / 5, bytes.count == Self.byteCount else { return nil }
        self.data = Data(bytes)
    }

    public var displayString: String {
        var out: [Character] = []
        var bits: UInt64 = 0
        var bitCount = 0
        for byte in data {
            bits = (bits << 8) | UInt64(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                out.append(Self.alphabet[Int((bits >> UInt64(bitCount)) & 0x1F)])
            }
            bits &= (1 << UInt64(bitCount)) - 1
        }
        return stride(from: 0, to: out.count, by: 4)
            .map { String(out[$0..<min($0 + 4, out.count)]) }
            .joined(separator: "-")
    }

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    private static let decodeTable: [Character: UInt8] = {
        var table: [Character: UInt8] = [:]
        for (i, ch) in alphabet.enumerated() { table[ch] = UInt8(i) }
        table["O"] = 0
        table["I"] = 1
        table["L"] = 1
        return table
    }()
}
