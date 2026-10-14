import Foundation
import Security
import VirtualRemoteCore

/// Stores one pairing key per receiver in the login keychain.
struct KeychainKeyStore {
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

    func save(_ key: PairingKey, account: String) throws {
        delete(account: account)
        var query = base(account)
        query[kSecValueData as String] = key.data
        let status = SecItemAdd(query as CFDictionary, nil)
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
