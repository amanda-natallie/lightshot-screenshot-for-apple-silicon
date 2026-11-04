// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Shotmark",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ShotmarkCore"),
        .executableTarget(name: "Shotmark", dependencies: ["ShotmarkCore"]),
        .testTarget(name: "ShotmarkCoreTests", dependencies: ["ShotmarkCore"]),
    ]
)
