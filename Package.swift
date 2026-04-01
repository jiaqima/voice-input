// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            path: "Sources/VoiceInput",
            linkerSettings: [
                .unsafeFlags(["-framework", "Carbon"]),
            ]
        ),
    ]
)
