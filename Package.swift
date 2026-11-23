// swift-tools-version: 6.4
// SwiftPM manifest used for the model/client unit tests. The Xcode project is
// the distributable app and WidgetKit extension.
import PackageDescription

let package = Package(
    name: "CodexUsageWidget",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CodexUsage", targets: ["CodexUsage"])],
    targets: [
        .target(name: "CodexUsage", path: "CodexUsage", exclude: ["CodexUsageApp.swift", "Info.plist", "CodexUsage.entitlements"]),
        .testTarget(name: "CodexUsageWidgetTests", dependencies: ["CodexUsage"], path: "CodexUsageWidgetTests", exclude: ["Info.plist"])
    ]
)
