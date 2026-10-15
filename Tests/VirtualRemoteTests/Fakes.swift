import Foundation
import VirtualRemoteCore
@testable import VirtualRemote

/// A thread-safe counter for closures that run off the main actor.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// A stand-in for Bonjour discovery: the test decides which events arrive.
final class FakeBrowser: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<BrowserEvent>.Continuation?
    private var started = 0
    private var terminated = 0

    /// How many times the model asked for a new event stream.
    var startCount: Int { lock.withLock { started } }
    /// How many of those streams have since been cancelled.
    var terminatedCount: Int { lock.withLock { terminated } }

    func stream() -> AsyncStream<BrowserEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: BrowserEvent.self)
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { self?.terminated += 1 }
        }
        lock.withLock {
            started += 1
            self.continuation = continuation
        }
        return stream
    }

    func send(_ event: BrowserEvent) {
        let continuation = lock.withLock { self.continuation }
        continuation?.yield(event)
    }
}

/// A login item that records what the app asked for.
final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var failure: Error?
    private var registerCalls = 0
    private var unregisterCalls = 0

    var isEnabled: Bool { lock.withLock { enabled } }
    var registers: Int { lock.withLock { registerCalls } }
    var unregisters: Int { lock.withLock { unregisterCalls } }

    func failNext(with error: Error) { lock.withLock { failure = error } }

    func register() throws {
        try lock.withLock {
            registerCalls += 1
            if let error = failure {
                failure = nil
                throw error
            }
            enabled = true
        }
    }

    func unregister() throws {
        try lock.withLock {
            unregisterCalls += 1
            if let error = failure {
                failure = nil
                throw error
            }
            enabled = false
        }
    }
}

extension ReceiverEnvironment {
    /// A receiver environment with no adapter, no Bonjour and no system calls.
    static func fake(
        paths: AdapterPaths? = AdapterPaths(directory: URL(fileURLWithPath: "/nonexistent")),
        selfTest: @escaping @Sendable (AdapterPaths) async -> Bool = { _ in true },
        executors: Counter = Counter(),
        pathLookups: Counter = Counter(),
        info: NowPlayingInfo? = .sample()
    ) -> ReceiverEnvironment {
        ReceiverEnvironment(
            adapterPaths: {
                pathLookups.increment()
                return paths
            },
            selfTest: selfTest,
            makeExecutor: { _ in
                executors.increment()
                return CommandExecutor(player: StubPlayer(info: info), volume: StubVolume())
            },
            detectKind: { .macMini },
            computerName: { "Test Mac" },
            advertise: false)
    }
}
