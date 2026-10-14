import Foundation
import Testing
@testable import VirtualRemoteCore

@Suite struct LineFramerTests {
    private func lines(_ framer: inout LineFramer, _ text: String) throws -> [String] {
        try framer.append(Data(text.utf8)).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func splitsMultipleLines() throws {
        var f = LineFramer()
        #expect(try lines(&f, "a\nb\nc\n") == ["a", "b", "c"])
    }

    @Test func holdsPartialLineUntilNewline() throws {
        var f = LineFramer()
        #expect(try lines(&f, "hel").isEmpty)
        #expect(try lines(&f, "lo\nwor") == ["hello"])
        #expect(try lines(&f, "ld\n") == ["world"])
    }

    @Test func skipsEmptyLines() throws {
        var f = LineFramer()
        #expect(try lines(&f, "\n\na\n\n") == ["a"])
    }

    @Test func rejectsOversizedPartialLine() {
        var f = LineFramer(maxLineLength: 8)
        #expect(throws: LineFramer.FrameError.lineTooLong) {
            _ = try f.append(Data(repeating: 0x61, count: 9))
        }
    }

    @Test func rejectsOversizedCompleteLine() {
        var f = LineFramer(maxLineLength: 8)
        #expect(throws: LineFramer.FrameError.lineTooLong) {
            _ = try f.append(Data("aaaaaaaaaa\n".utf8))
        }
    }
}
