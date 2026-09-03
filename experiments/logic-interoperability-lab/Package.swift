// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogicInteroperabilityLab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "logic-lab", targets: ["LogicInteroperabilityLab"])
    ],
    targets: [
        .executableTarget(
            name: "LogicInteroperabilityLab",
            path: "Sources/LogicInteroperabilityLab"
        )
    ]
)
