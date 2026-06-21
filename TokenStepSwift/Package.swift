// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenStepSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TokenStepSwift", targets: ["TokenStepSwift"]),
        .executable(name: "TokenStepHelper", targets: ["TokenStepHelper"])
    ],
    targets: [
        .executableTarget(name: "TokenStepSwift"),
        .executableTarget(
            name: "TokenStepHelper",
            path: "Sources",
            sources: [
                "TokenStepSwift/Support/AppPaths.swift",
                "TokenStepSwift/Support/Localization.swift",
                "TokenStepSwift/Support/MemoryPressure.swift",
                "TokenStepSwift/Support/Theme.swift",
                "TokenStepSwift/Models/UsageModels.swift",
                "TokenStepSwift/Services/UsageCollector.swift",
                "TokenStepSwift/Services/DataService.swift",
                "TokenStepHelper/main.swift"
            ]
        ),
        .testTarget(
            name: "TokenStepSwiftTests",
            dependencies: ["TokenStepSwift"]
        )
    ]
)
