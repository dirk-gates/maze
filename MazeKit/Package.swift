// swift-tools-version: 6.0
//
// MazeKit -- maze generation and solving engine.
// Pure Swift, no platform UI dependencies. Powers Maze (macOS) and Maze (iOS).

import PackageDescription

let package = Package(
    name     : "MazeKit",
    platforms: [
        .macOS(.v15),       // one back from current macOS 26 (Tahoe)
        .iOS(.v18),         // one back from current iOS 26
    ],
    products: [
        .library   (name: "MazeKit",            targets: ["MazeKit"]),
        .executable(name: "MazeIconGenerator",  targets: ["MazeIconGenerator"]),
    ],
    targets: [
        .target(
            name : "MazeKit",
            path : "Sources/MazeKit"
        ),
        .executableTarget(
            name        : "MazeIconGenerator",
            dependencies: ["MazeKit"],
            path        : "Sources/MazeIconGenerator"
        ),
        .testTarget(
            name        : "MazeKitTests",
            dependencies: ["MazeKit"],
            path        : "Tests/MazeKitTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
