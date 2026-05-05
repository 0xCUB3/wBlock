// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WBlockFilterCompiler",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "WBlockFilterCompiler",
            targets: ["WBlockFilterCompiler"]
        ),
        .executable(
            name: "wblock-filter-compiler",
            targets: ["wblock-filter-compiler"]
        ),
    ],
    targets: [
        .target(
            name: "WBlockFilterCompiler"
        ),
        .executableTarget(
            name: "wblock-filter-compiler",
            dependencies: ["WBlockFilterCompiler"]
        ),
        .testTarget(
            name: "WBlockFilterCompilerTests",
            dependencies: ["WBlockFilterCompiler"]
        ),
    ]
)
