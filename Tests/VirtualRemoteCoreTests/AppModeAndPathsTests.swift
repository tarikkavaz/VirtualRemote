import Foundation
import Testing
@testable import VirtualRemoteCore

@Suite struct AppModeAndPathsTests {
    @Test func modeFlags() {
        #expect(AppMode.controller.isController && !AppMode.controller.isReceiver)
        #expect(!AppMode.receiver.isController && AppMode.receiver.isReceiver)
        #expect(AppMode.both.isController && AppMode.both.isReceiver)
    }

    @Test func modeRawValueRoundTrip() {
        for mode in AppMode.allCases {
            #expect(AppMode(rawValue: mode.rawValue) == mode)
        }
        #expect(AppMode(rawValue: "nonsense") == nil)
    }

    @Test func pathsAreDerivedFromDirectory() {
        let paths = AdapterPaths(directory: URL(fileURLWithPath: "/x/adapter"))
        #expect(paths.script == "/x/adapter/mediaremote-adapter.pl")
        #expect(paths.framework == "/x/adapter/MediaRemoteAdapter.framework")
        #expect(paths.testClient == "/x/adapter/MediaRemoteAdapterTestClient")
        #expect(!paths.allExist)
    }

    @Test func allExistNeedsEveryFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vr-adapter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = AdapterPaths(directory: dir)
        try Data().write(to: URL(fileURLWithPath: paths.script))
        try FileManager.default.createDirectory(
            atPath: paths.framework, withIntermediateDirectories: true)
        #expect(!paths.allExist)
        try Data().write(to: URL(fileURLWithPath: paths.testClient))
        #expect(paths.allExist)
    }

    @Test func selfTestIsFalseWhenFilesAreMissing() async {
        let paths = AdapterPaths(directory: URL(fileURLWithPath: "/nonexistent"))
        #expect(await paths.selfTest() == false)
    }
}
