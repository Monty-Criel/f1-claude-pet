// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "F1ClaudePet",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "F1ClaudePet",
            path: "Sources/F1ClaudePet"
        )
    ]
)
