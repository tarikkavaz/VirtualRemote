import Foundation

/// Splits a byte stream into newline-terminated lines.
struct LineFramer {
    enum FrameError: Error, Equatable { case lineTooLong }

    private var buffer = Data()
    let maxLineLength: Int

    init(maxLineLength: Int = 1 << 20) {
        self.maxLineLength = maxLineLength
    }

    /// Returns the complete, non-empty lines in the data seen so far.
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.count > maxLineLength { throw FrameError.lineTooLong }
            if !line.isEmpty { lines.append(line) }
        }
        if buffer.count > maxLineLength { throw FrameError.lineTooLong }
        return lines
    }
}
