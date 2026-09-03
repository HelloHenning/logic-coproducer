// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogicInteroperabilityLab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "logic-lab", targets: ["LogicInteroperabilityLab"]),
        .executable(name: "logic-fixture", targets: ["LogicFixture"]),
        .executable(name: "logic-a1-compare", targets: ["LogicA1Compare"])
    ],
    targets: [
        .executableTarget(
            name: "LogicInteroperabilityLab",
            path: "Sources/LogicInteroperabilityLab"
        ),
        .executableTarget(
            name: "LogicFixture",
            path: "Sources/LogicFixture"
        ),
        .executableTarget(
            name: "LogicA1Compare",
            path: "Sources/LogicA1Compare"
        )
    ]
)
