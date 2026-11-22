// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clipdeck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clipdeck", targets: ["Clipdeck"]),
    ],
    targets: [
        .target(name: "ClipdeckCore"),
        .executableTarget(name: "Clipdeck", dependencies: ["ClipdeckCore"]),
        .testTarget(name: "ClipdeckCoreTests", dependencies: ["ClipdeckCore"]),
        .testTarget(name: "ClipdeckTests", dependencies: ["Clipdeck", "ClipdeckCore"]),
    ]
)
