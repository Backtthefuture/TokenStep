// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenStepSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TokenStepSwift", targets: ["TokenStepSwift"])
    ],
    targets: [
        // TokenStepHelper is bundled by script/build_swiftui_and_run.sh because it
        // intentionally shares internal app sources that SwiftPM cannot own twice.
        .executableTarget(name: "TokenStepSwift"),
        .testTarget(
            name: "TokenStepSwiftTests",
            dependencies: ["TokenStepSwift"]
        )
    ]
)
