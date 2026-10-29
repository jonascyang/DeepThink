// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "M0bProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "M0bProbe",
            path: "Sources/M0bProbe",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
