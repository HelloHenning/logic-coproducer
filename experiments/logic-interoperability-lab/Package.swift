// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogicInteroperabilityLab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "logic-lab", targets: ["LogicInteroperabilityLab"]),
        .executable(name: "logic-fixture", targets: ["LogicFixture"])
    ],
    targets: [
        .executableTarget(
            name: "LogicInteroperabilityLab",
            path: "Sources/LogicInteroperabilityLab"
        ),
        .executableTarget(
            name: "LogicFixture",
            path: "Sources/LogicFixture"
        )
    ]
)
