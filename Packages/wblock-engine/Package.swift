// swift-tools-version:5.9
// The Rust engine (crates/wbe) as a Swift package. build/WBE.xcframework comes
// from scripts/build-xcframework.sh and must exist before Xcode resolves this.
import PackageDescription

let package = Package(
    name: "WBEngine",
    platforms: [.macOS("12.3"), .iOS("15.4")],
    products: [.library(name: "WBEngine", targets: ["WBEngine"])],
    targets: [
        .binaryTarget(name: "WBE", path: "build/WBE.xcframework"),
        .target(name: "WBEngine", dependencies: ["WBE"]),
    ]
)
