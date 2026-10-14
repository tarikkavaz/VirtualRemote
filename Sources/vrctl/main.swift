import Foundation
import VirtualRemoteCore

// Dev client: connect by address, print the first state, optionally send one command.
// usage: vrctl HOST PORT KEY [toggle|next|previous|skip:SECONDS|volume:0-1]

setvbuf(stdout, nil, _IOLBF, 0)

let args = CommandLine.arguments
guard args.count >= 4, let port = UInt16(args[2]), let key = PairingKey(displayString: args[3]) else {
    FileHandle.standardError.write(Data("usage: vrctl HOST PORT KEY [command]\n".utf8))
    exit(2)
}

let client = RemoteClient(host: args[1], port: port, key: key)
do {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            try await client.connect()
            print("connected")
        }
        group.addTask {
            try await Task.sleep(for: .seconds(10))
            throw URLError(.timedOut)
        }
        try await group.next()
        group.cancelAll()
    }
} catch {
    print("connect failed: \(error)")
    exit(1)
}

if args.count >= 5 {
    let parts = args[4].split(separator: ":").map(String.init)
    let command: RemoteCommand?
    switch parts[0] {
    case "toggle": command = .togglePlayPause
    case "next": command = .next
    case "previous": command = .previous
    case "skip": command = Double(parts.last ?? "").map { .skip(seconds: $0) }
    case "volume": command = Double(parts.last ?? "").map { .setVolume($0) }
    default: command = nil
    }
    guard let command else {
        print("unknown command \(args[4])")
        exit(2)
    }
    try await client.send(command)
    print("sent \(command)")
}

var seen = 0
for try await message in client.messages {
    print(message)
    seen += 1
    if seen >= 2 { break }
}
client.close()
