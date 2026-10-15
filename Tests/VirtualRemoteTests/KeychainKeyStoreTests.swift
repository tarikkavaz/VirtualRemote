import Foundation
import Testing
import VirtualRemoteCore
@testable import VirtualRemote

/// These use the real login keychain, with a service name that only these tests use.
@Suite(.serialized) struct KeychainKeyStoreTests {
    private func makeStore() -> KeychainKeyStore {
        KeychainKeyStore(service: "org.kavaz.VirtualRemote.tests.\(UUID().uuidString)")
    }

    @Test func savedKeyLoadsBack() throws {
        let store = makeStore()
        defer { store.delete(account: "Mini") }
        let key = PairingKey.generate()

        try store.save(key, account: "Mini")

        #expect(store.load(account: "Mini") == key)
    }

    @Test func missingKeyLoadsAsNil() {
        #expect(makeStore().load(account: "Nobody") == nil)
    }

    @Test func savingAgainReplacesTheKeyInPlace() throws {
        let store = makeStore()
        defer { store.delete(account: "Mini") }
        let first = PairingKey.generate()
        let second = PairingKey.generate()

        try store.save(first, account: "Mini")
        try store.save(second, account: "Mini")  // updates the same item, no duplicate error

        #expect(store.load(account: "Mini") == second)
    }

    @Test func deletingRemovesOnlyThatAccount() throws {
        let store = makeStore()
        defer {
            store.delete(account: "Mini")
            store.delete(account: "Air")
        }
        try store.save(.generate(), account: "Mini")
        let airKey = PairingKey.generate()
        try store.save(airKey, account: "Air")

        store.delete(account: "Mini")

        #expect(store.load(account: "Mini") == nil)
        #expect(store.load(account: "Air") == airKey)
    }

    @Test func deletingAMissingKeyIsHarmless() {
        makeStore().delete(account: "Nobody")
    }

    @Test func servicesDoNotSeeEachOthersKeys() throws {
        let one = makeStore()
        let two = makeStore()
        defer { one.delete(account: "Mini") }

        try one.save(.generate(), account: "Mini")

        #expect(two.load(account: "Mini") == nil)
    }
}
