// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Workaround: with Command Line Tools only, incremental test builds sometimes fail with
// "plugin for module 'TestingMacros' not found" because the Swift Testing macro plugin lives in a
// `testing/` subfolder that the explicit-module build doesn't always pass along. Point at it directly.
let testingPluginDir = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSwiftSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPluginDir)
    ? [.unsafeFlags(["-plugin-path", testingPluginDir])]
    : []

let package = Package(
    name: "VoyagerView",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VoyagerView", targets: ["VoyagerView"]),
    ],
    targets: [
        // Pure logic: protocol codec, layout models, labels, geometry, settings. No AppKit, no I/O.
        .target(
            name: "VoyagerCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The app: menu bar, overlay panel, HID, networking, persistence.
        .executableTarget(
            name: "VoyagerView",
            dependencies: ["VoyagerCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]
        ),
        .testTarget(
            name: "VoyagerCoreTests",
            dependencies: ["VoyagerCore"],
            path: "Tests/VoyagerCoreTests",
            swiftSettings: testSwiftSettings
        ),
    ]
)
