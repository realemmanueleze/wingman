// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Wingman",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Wingman",
            path: "Sources/Wingman",
            swiftSettings: [
                // Swift 5 language mode: the app follows Clicky's @MainActor
                // conventions but does not yet adopt strict Swift 6 concurrency.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
