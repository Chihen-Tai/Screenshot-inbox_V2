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
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                // libsqlite3 ships with macOS; we use the C API via `import SQLite3`.
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ScreenshotInboxTests",
            dependencies: ["ScreenshotInbox"]
        )
    ]
)
