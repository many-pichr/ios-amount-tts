// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KhmerAmountSpeech",
    platforms: [.iOS(.v13), .macOS(.v11)],
    products: [
        .library(name: "KhmerAmountSpeech", targets: ["KhmerAmountSpeech"]),
    ],
    targets: [
        .target(
            name: "KhmerAmountSpeech",
            resources: [.copy("Resources/audio")]
        ),
        .testTarget(
            name: "KhmerAmountSpeechTests",
            dependencies: ["KhmerAmountSpeech"]
        ),
    ]
)
