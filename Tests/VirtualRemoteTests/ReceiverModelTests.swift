import Foundation
import Testing
import VirtualRemoteCore
@testable import VirtualRemote

@MainActor
@Suite struct ReceiverModelTests {
    @Test func firstLaunchCreatesAndStoresAKey() {
        let store = MemoryKeyStore()

        let model = ReceiverModel(keyStore: store)

        #expect(store.keys["receiver"] == model.key)
        #expect(model.keychainWarning == nil)
        #expect(model.status == .stopped)
    }

    @Test func anExistingKeyIsReusedNotReplaced() {
        let store = MemoryKeyStore()
        let existing = PairingKey.generate()
        store.keys["receiver"] = existing

        let model = ReceiverModel(keyStore: store)

        #expect(model.key == existing)
        #expect(store.keys["receiver"] == existing)
    }

    @Test func aNewKeyReplacesTheOldOneEverywhere() {
        let store = MemoryKeyStore()
        let model = ReceiverModel(keyStore: store)
        let old = model.key

        model.regenerateKey()

        #expect(model.key != old)
        #expect(store.keys["receiver"] == model.key)
    }

    @Test func aKeychainThatCannotSaveShowsAWarningInsteadOfFailing() {
        let store = MemoryKeyStore()
        store.failSaves = true

        let model = ReceiverModel(keyStore: store)

        #expect(model.keychainWarning != nil)
        #expect(store.keys.isEmpty)
        #expect(model.key.displayString.count == 29)  // still usable for this session
    }

    @Test func aSuccessfulSaveClearsTheWarning() {
        let store = MemoryKeyStore()
        store.failSaves = true
        let model = ReceiverModel(keyStore: store)
        #expect(model.keychainWarning != nil)

        store.failSaves = false
        model.regenerateKey()

        #expect(model.keychainWarning == nil)
        #expect(store.keys["receiver"] == model.key)
    }

    @Test func startingWithoutTheBundledAdapterReportsIt() async {
        // The test process has no adapter in its bundle, like `swift run`.
        let model = ReceiverModel(keyStore: MemoryKeyStore())

        model.start()

        #expect(model.status == .starting)
        let expected = ReceiverModel.Status.failed("The media adapter is missing from the app bundle.")
        #expect(await eventually { model.status == expected })
    }

    @Test func stoppingResetsTheStatus() async {
        let model = ReceiverModel(keyStore: MemoryKeyStore())
        model.start()

        model.stop()

        #expect(model.status == .stopped)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.status == .stopped)  // a late start task must not bring it back
    }
}
