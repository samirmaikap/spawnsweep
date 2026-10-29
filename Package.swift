// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SpawnSweep",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SpawnSweep",
            path: "Sources/SpawnSweep",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
