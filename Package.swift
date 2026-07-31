// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "F1DockPet",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "F1DockPet",
            path: "Sources/F1DockPet"
        )
    ]
)
