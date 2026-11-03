// swift-tools-version:5.9
// AdGuard-side per-page lookup benchmark. Builds against the local SafariConverterLib checkout
// (SCL_PATH overrides the default, which is the checkout ConverterTool was built from).
import Foundation
import PackageDescription

let sclPath = ProcessInfo.processInfo.environment["SCL_PATH"] ?? "/tmp/research/bench/scl"

let package = Package(
    name: "ag-lookup",
    platforms: [.macOS(.v12)],
    dependencies: [.package(path: sclPath)],
    targets: [
        .executableTarget(
            name: "ag-lookup",
            dependencies: [.product(name: "ContentBlockerConverter", package: "scl")]
        ),
    ]
)
