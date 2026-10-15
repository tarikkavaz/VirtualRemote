import Foundation

/// Per-client queue between the network reader and the command runner.
/// Adjacent volume commands, and adjacent absolute seeks, are merged so a drag
/// cannot build a backlog in front of a later pause. Order of everything else is kept.
final class CommandQueue: @unchecked Sendable {
    /// Yields once per push; consume with `for await`, then drain with `pop()`.
    let signals: AsyncStream<Void>

    private let signal: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var items: [RemoteCommand] = []

    init() {
        (signals, signal) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func push(_ command: RemoteCommand) {
        lock.withLock {
            switch (items.last, command) {
            case (.setVolume, .setVolume):
                items[items.count - 1] = command
            case (.adjustVolume(let a), .adjustVolume(let b)):
                items[items.count - 1] = .adjustVolume(a + b)
            case (.seek, .seek):
                items[items.count - 1] = command
            default:
                items.append(command)
            }
        }
        signal.yield()
    }

    func pop() -> RemoteCommand? {
        lock.withLock { items.isEmpty ? nil : items.removeFirst() }
    }

    /// No more commands will arrive. Pending ones can still be popped.
    func finish() {
        signal.finish()
    }
}
