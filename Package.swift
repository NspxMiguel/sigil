// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sigil",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sigil",
            path: "Sources/Sigil"
        )
    ]
)
