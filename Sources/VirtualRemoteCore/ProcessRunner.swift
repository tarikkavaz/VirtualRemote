import Foundation

enum ProcessRunner {
    /// Runs an executable and returns stdout. Reads stdout to EOF before
    /// waiting, so large output (e.g. base64 artwork) cannot fill the pipe
    /// and deadlock the child.
    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                } else {
                    continuation.resume(
                        throwing: RemoteError.processFailed(
                            executable: executable,
                            status: process.terminationStatus
                        )
                    )
                }
            }
        }
    }
}
