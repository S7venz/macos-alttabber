// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AltTabber",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AltTabber",
            path: "Sources/AltTabber",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
                // SkyLight is a private framework — needed for cross-Space window
                // raising (_SLPSSetFrontProcessWithOptions / SLPSPostEventRecordTo).
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-framework", "SkyLight"])
            ]
        )
    ]
)
