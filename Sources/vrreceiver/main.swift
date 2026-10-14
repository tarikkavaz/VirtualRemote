import Foundation
import VirtualRemoteCore

// Dev receiver: runs the real backends and prints the pairing key.
// usage: vrreceiver --adapter-dir DIR [--key XXXX-...] [--name NAME]
// DIR holds bin/mediaremote-adapter.pl and build/MediaRemoteAdapter.framework.

setvbuf(stdout, nil, _IOLBF, 0)

var adapterDir: String?
var keyString: String?
var name = Host.current().localizedName ?? "Mac"

var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--adapter-dir": adapterDir = args.next()
    case "--key": keyString = args.next()
    case "--name": name = args.next() ?? name
    default:
        FileHandle.standardError.write(Data("unknown argument: \(arg)\n".utf8))
        exit(2)
    }
}

guard let adapterDir else {
    FileHandle.standardError.write(Data("missing --adapter-dir\n".utf8))
    exit(2)
}

let key: PairingKey
if let keyString {
    guard let parsed = PairingKey(displayString: keyString) else {
        FileHandle.standardError.write(Data("invalid --key\n".utf8))
        exit(2)
    }
    key = parsed
} else {
    key = .generate()
}

let backend = AdapterNowPlayingBackend(
    scriptPath: adapterDir + "/bin/mediaremote-adapter.pl",
    frameworkPath: adapterDir + "/build/MediaRemoteAdapter.framework"
)
let executor = CommandExecutor(player: backend, volume: OsascriptVolumeBackend())
let server = RemoteServer(executor: executor, key: key, serviceName: name)
let port = try await server.start()

print("receiver \"\(name)\" listening on port \(port)")
print("pairing key: \(key.displayString)")

while true {
    try await Task.sleep(for: .seconds(3600))
}
