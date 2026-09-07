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
        .target(
            name: "ZstdDecompressor",
            path: "Vendor/ZstdDecompressor",
            sources: ["zstddeclib.c"],
            publicHeadersPath: "."
        ),
        // TokenStepHelper is bundled by script/build_swiftui_and_run.sh because it
        // intentionally shares internal app sources that SwiftPM cannot own twice.
        .executableTarget(name: "TokenStepSwift", dependencies: ["ZstdDecompressor"]),
        .testTarget(
            name: "TokenStepSwiftTests",
            dependencies: ["TokenStepSwift"]
        )
    ]
)
