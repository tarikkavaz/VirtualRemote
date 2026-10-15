import Foundation
import Network
import Testing
@testable import VirtualRemoteCore

@Suite struct ConnectionFailureTests {
    @Test func wrongKeyHandshakeIsAKeyMismatch() {
        #expect(ConnectionFailure.classify(NWError.tls(-9820)) == .keyMismatch)
    }

    @Test(arguments: [Int32(-9805), -9806, -9816])
    func peerGoingAwayIsNotAKeyMismatch(status: Int32) {
        #expect(ConnectionFailure.classify(NWError.tls(status)) == .noAnswer)
    }

    @Test(arguments: [Int32(-65570), -65555])
    func policyDeniedIsLocalNetworkDenied(code: Int32) {
        #expect(ConnectionFailure.classify(NWError.dns(code)) == .localNetworkDenied)
    }

    @Test func otherErrorsAreNoAnswer() {
        #expect(ConnectionFailure.classify(NWError.dns(-65537)) == .noAnswer)
        #expect(ConnectionFailure.classify(NWError.posix(.ECONNREFUSED)) == .noAnswer)
        #expect(ConnectionFailure.classify(NWError.posix(.EHOSTUNREACH)) == .noAnswer)
        #expect(ConnectionFailure.classify(CancellationError()) == .noAnswer)
    }
}

@Suite struct ControllerStatusTests {
    private typealias Input = ControllerStatus.Input

    private func status(_ input: Input) -> ControllerStatus { ControllerStatus.derive(input) }

    @Test func connectedWinsOverEverything() {
        let input = Input(
            localNetworkDenied: true, selectedName: "Mini", selectedVisible: true, link: .connected)
        #expect(status(input) == .connected)
    }

    @Test func deniedBeatsGuessingWhenNotConnected() {
        let input = Input(localNetworkDenied: true, selectedName: "Mini", selectedVisible: true, link: .noAnswer)
        #expect(status(input) == .localNetworkDenied)
        #expect(status(Input(localNetworkDenied: true)) == .localNetworkDenied)
    }

    @Test func searchingThenNotVisibleWithARememberedReceiver() {
        #expect(status(Input(rememberedName: "Mini")) == .searching(name: "Mini"))
        #expect(status(Input(rememberedName: "Mini", searchGraceOver: true)) == .notVisible(name: "Mini"))
    }

    @Test func searchingThenNotVisibleWithNoReceiversAtAll() {
        #expect(status(Input()) == .searching(name: nil))
        #expect(status(Input(searchGraceOver: true)) == .notVisible(name: nil))
    }

    @Test func receiversFoundButNoneSelectedAsksToPick() {
        #expect(status(Input(anyReceivers: true)) == .needsReceiver)
    }

    @Test func connectingShowsTheReceiverAndItsKind() {
        let input = Input(selectedName: "Mini", selectedKind: .macMini, selectedVisible: true, link: .connecting)
        #expect(status(input) == .connecting(name: "Mini", kind: .macMini))
    }

    @Test func visibleButSilentIsNoAnswer() {
        let input = Input(selectedName: "Mini", selectedVisible: true, link: .noAnswer)
        #expect(status(input) == .noAnswer(name: "Mini"))
    }

    @Test func vanishedFromTheNetworkIsNotVisible() {
        for link in [LinkState.connecting, .idle, .noAnswer, .lost] {
            let input = Input(selectedName: "Mini", selectedVisible: false, link: link)
            #expect(status(input) == .notVisible(name: "Mini"))
        }
    }

    @Test func droppedConnectionOfAVisibleReceiverIsLost() {
        let input = Input(selectedName: "Mini", selectedVisible: true, link: .lost)
        #expect(status(input) == .lost(name: "Mini"))
    }

    @Test func keyMismatchIsReportedEvenIfTheReceiverIsHidden() {
        let input = Input(selectedName: "Mini", selectedVisible: false, link: .keyMismatch)
        #expect(status(input) == .keyMismatch(name: "Mini"))
    }
}
