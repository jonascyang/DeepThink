// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThinkMyDay",
    platforms: [.macOS(.v14)],
    targets: [
        // Storage and domain types, no UI. Everything that can be tested without a window server lives here.
        .target(
            name: "ThinkMyDayCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // The menu-bar app.
        .executableTarget(
            name: "ThinkMyDay",
            dependencies: ["ThinkMyDayCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        // Development tool: writes records in a loop so scripts/crash-test.sh can kill it mid-write.
        .executableTarget(
            name: "tmd-store-stress",
            dependencies: ["ThinkMyDayCore"]
        ),
        .testTarget(
            name: "ThinkMyDayCoreTests",
            dependencies: ["ThinkMyDayCore"]
        ),
    ]
)
