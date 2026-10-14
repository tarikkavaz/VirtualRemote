// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VirtualRemote",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VirtualRemoteCore", targets: ["VirtualRemoteCore"]),
        .executable(name: "VirtualRemote", targets: ["VirtualRemote"]),
        .executable(name: "vrreceiver", targets: ["vrreceiver"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(name: "VirtualRemoteCore"),
        .executableTarget(
            name: "VirtualRemote",
            dependencies: [
                "VirtualRemoteCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .executableTarget(
            name: "vrreceiver",
            dependencies: ["VirtualRemoteCore"]
        ),
        .executableTarget(
            name: "vrctl",
            dependencies: ["VirtualRemoteCore"]
        ),
        .testTarget(
            name: "VirtualRemoteCoreTests",
            dependencies: ["VirtualRemoteCore"]
        ),
    ]
)
