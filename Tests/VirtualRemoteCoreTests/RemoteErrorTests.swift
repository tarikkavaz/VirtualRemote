import Foundation
import Testing
@testable import VirtualRemoteCore

@Suite struct RemoteErrorTests {
    @Test func everyErrorHasAReadableMessage() {
        let cases: [(RemoteError, String)] = [
            (.noActivePlayer, "Nothing is playing."),
            (.positionUnavailable, "This is a live stream or has no known length, so it cannot skip or seek."),
            (.processFailed(executable: "/usr/bin/perl", status: 1),
             "The media helper (perl) failed with status 1."),
            (.invalidAdapterOutput, "Could not read the media state."),
        ]
        for (error, expected) in cases {
            #expect(RemoteError.userMessage(for: error) == expected)
            #expect(error.localizedDescription == expected)
        }
    }

    @Test func noMessageLooksLikeACaseName() {
        let errors: [RemoteError] = [
            .noActivePlayer, .positionUnavailable,
            .processFailed(executable: "/usr/bin/osascript", status: 9), .invalidAdapterOutput,
        ]
        for error in errors {
            let text = RemoteError.userMessage(for: error)
            #expect(!text.contains("noActivePlayer"))
            #expect(!text.contains("processFailed"))
            #expect(!text.contains("invalidAdapterOutput"))
            #expect(!text.contains("executable:"))
        }
    }

    @Test func otherErrorsStillGetTheirSystemMessage() {
        struct Odd: Error {}
        let text = RemoteError.userMessage(for: Odd())
        #expect(!text.isEmpty)
        let cocoa = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "Custom text"])
        #expect(RemoteError.userMessage(for: cocoa) == "Custom text")
    }
}
