import Foundation
import Network
import Security

enum TLSConfig {
    static let serviceType = "_virtualremote._tcp"
    private static let pskIdentity = Data("virtualremote".utf8)

    /// TLS 1.2 with a PSK cipher suite. Both sides must hold the same key;
    /// a mismatch fails the handshake.
    static func parameters(key: PairingKey) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(
            options,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        )
        let psk = key.data.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = pskIdentity.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(
            options,
            psk as __DispatchData,
            identity as __DispatchData
        )
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        return NWParameters(tls: tls, tcp: tcp)
    }
}
