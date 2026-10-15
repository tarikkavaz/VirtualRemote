import Foundation
import Security
import VirtualRemoteCore

/// Where pairing keys are kept. The Keychain in the app, a dictionary in tests.
protocol KeyStoring {
    func load(account: String) -> PairingKey?
    func save(_ key: PairingKey, account: String) throws
    func delete(account: String)
}

/// Stores one pairing key per receiver in the login keychain.
struct KeychainKeyStore: KeyStoring {
    let service: String

    func load(account: String) -> PairingKey? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return PairingKey(data: data)
    }

    /// Updates the item in place when it exists, so macOS keeps its access list
    /// (and the "Always Allow" choice) instead of seeing a brand new item.
    func save(_ key: PairingKey, account: String) throws {
        var status = SecItemUpdate(
            base(account) as CFDictionary,
            [kSecValueData as String: key.data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = base(account)
            query[kSecValueData as String] = key.data
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func delete(account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    private func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
