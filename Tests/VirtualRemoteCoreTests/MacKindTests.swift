import Testing
@testable import VirtualRemoteCore

@Suite struct MacKindTests {
    @Test(arguments: [
        ("Mac mini", MacKind.macMini),
        ("Mac Studio", .macStudio),
        ("Mac Pro", .macPro),
        ("MacBook Air", .macBook),
        ("MacBook Pro", .macBook),
        ("iMac", .iMac),
        ("iMac Pro", .iMac),
        ("Something New", .generic),
    ])
    func marketingNameMapsToFamily(name: String, expected: MacKind) {
        #expect(MacKind(machineName: name) == expected)
    }

    @Test func missingNameIsGeneric() {
        #expect(MacKind(machineName: nil) == .generic)
        #expect(MacKind(machineName: "") == .generic)
    }

    @Test func rawValueRoundTripsThroughTheTxtRecord() {
        for kind in [MacKind.macMini, .macStudio, .macPro, .macBook, .iMac, .generic] {
            #expect(MacKind(rawValue: kind.rawValue) == kind)
        }
    }

    @Test func everyKindHasASymbol() {
        for kind in [MacKind.macMini, .macStudio, .macPro, .macBook, .iMac, .generic] {
            #expect(!kind.symbolName.isEmpty)
        }
    }

    @Test func detectFindsAKindOnThisMac() async {
        // Any real Mac reports a name; on one we do not know it falls back to generic.
        let kind = await MacKind.detect()
        #expect(MacKind.allKnown.contains(kind))
    }
}

extension MacKind {
    fileprivate static let allKnown: [MacKind] = [.macMini, .macStudio, .macPro, .macBook, .iMac, .generic]
}
