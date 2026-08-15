// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LidAssistant",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LidAssistant",
            path: "Sources/LidAssistant"
        ),
        .testTarget(
            name: "LidAssistantTests",
            dependencies: ["LidAssistant"],
            path: "Tests/LidAssistantTests"
        )
    ]
)
