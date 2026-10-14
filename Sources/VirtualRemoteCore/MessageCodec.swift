import Foundation

/// Newline-delimited JSON. One message per line; framing of the byte stream
/// is the transport's job.
public enum MessageCodec {
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encode(_ message: RemoteMessage) throws -> Data {
        var data = try encoder.encode(message)
        data.append(0x0A)
        return data
    }

    public static func decode(_ line: Data) throws -> RemoteMessage {
        try decoder.decode(RemoteMessage.self, from: line)
    }
}
