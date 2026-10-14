import Foundation
import Testing
@testable import VirtualRemoteCore

@Suite struct PairingKeyTests {
    @Test func generatedKeyHasExpectedShape() {
        let key = PairingKey.generate()
        #expect(key.data.count == 15)
        let groups = key.displayString.split(separator: "-")
        #expect(groups.count == 6)
        #expect(groups.allSatisfy { $0.count == 4 })
    }

    @Test func generatedKeysDiffer() {
        #expect(PairingKey.generate() != PairingKey.generate())
    }

    @Test func displayStringRoundTrips() throws {
        for _ in 0..<50 {
            let key = PairingKey.generate()
            let parsed = try #require(PairingKey(displayString: key.displayString))
            #expect(parsed == key)
        }
    }

    @Test func knownVector() throws {
        let key = try #require(PairingKey(data: Data(repeating: 0, count: 15)))
        #expect(key.displayString == "0000-0000-0000-0000-0000-0000")
        let all = try #require(PairingKey(data: Data(repeating: 0xFF, count: 15)))
        #expect(all.displayString == "ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ-ZZZZ")
    }

    @Test func parsingIsForgiving() throws {
        let key = PairingKey.generate()
        let messy = " " + key.displayString.lowercased().replacingOccurrences(of: "-", with: " ") + "\n"
        #expect(PairingKey(displayString: messy) == key)
    }

    @Test func crockfordAliases() throws {
        let zero = try #require(PairingKey(displayString: "0000-0000-0000-0000-0000-0000"))
        #expect(PairingKey(displayString: "OOOO-OOOO-OOOO-OOOO-OOOO-OOOO") == zero)
    }

    @Test(arguments: [
        "",
        "0000-0000-0000-0000-0000-000",
        "0000-0000-0000-0000-0000-00000",
        "0000-0000-0000-0000-0000-000U",
        "0000-0000-0000-0000-0000-000!",
    ])
    func invalidInputRejected(input: String) {
        #expect(PairingKey(displayString: input) == nil)
    }

    @Test func wrongByteCountRejected() {
        #expect(PairingKey(data: Data(repeating: 1, count: 14)) == nil)
        #expect(PairingKey(data: Data(repeating: 1, count: 16)) == nil)
    }
}
