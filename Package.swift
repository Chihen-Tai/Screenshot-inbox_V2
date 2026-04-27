// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScreenshotInbox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ScreenshotInbox", targets: ["ScreenshotInbox"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenshotInbox",
            path: "ScreenshotInbox",
            exclude: ["Resources"]
        )
    ]
)
