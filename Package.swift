// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EyeCare",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "EyeCare",
            path: "Sources/EyeCare"
        )
    ]
)
