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
        .executable(name: "logic-a1-compare", targets: ["LogicA1Compare"]),
        .executable(name: "logic-a2-mutate", targets: ["LogicA2Mutate"]),
        .executable(name: "logic-a2-compare", targets: ["LogicA2Compare"]),
        .executable(name: "logic-control-probe", targets: ["LogicControlProbe"]),
        .executable(name: "logic-mixer-matrix", targets: ["LogicMixerMatrix"]),
        .executable(name: "logic-blind-diff", targets: ["LogicBlindDiff"]),
        .executable(name: "logic-external-midi-actor", targets: ["LogicExternalMIDIActor"]),
        .executable(name: "logic-surface-explorer", targets: ["LogicSurfaceExplorer"]),
        .executable(name: "logic-mcu-bridge", targets: ["LogicMCUBridge"]),
        .executable(name: "logic-midi-smoke-client", targets: ["LogicMIDISmokeClient"]),
        .executable(name: "logic-a5-auto-setup", targets: ["LogicA5AutoSetup"]),
        .executable(name: "logic-a5-controls-setup", targets: ["LogicA5ControlsSetup"]),
        .executable(name: "logic-a5-plugin-probe", targets: ["LogicA5PluginProbe"]),
        .executable(name: "logic-a5-safe-roundtrip", targets: ["LogicA5SafeRoundTrip"]),
        .executable(name: "logic-phase-a-probe", targets: ["LogicPhaseAProbe"]),
        .executable(name: "logic-foundation-probe", targets: ["LogicFoundationProbe"]),
        .executable(name: "logic-foundation-repair-probe", targets: ["LogicFoundationRepairProbe2"])
    ],
    targets: [
        .executableTarget(name: "LogicInteroperabilityLab", path: "Sources/LogicInteroperabilityLab"),
        .executableTarget(name: "LogicFixture", path: "Sources/LogicFixture"),
        .executableTarget(name: "LogicA1Compare", path: "Sources/LogicA1Compare"),
        .executableTarget(name: "LogicA2Mutate", path: "Sources/LogicA2Mutate"),
        .executableTarget(name: "LogicA2Compare", path: "Sources/LogicA2Compare"),
        .executableTarget(name: "LogicControlProbe", path: "Sources/LogicControlProbe"),
        .executableTarget(name: "LogicMixerMatrix", path: "Sources/LogicMixerMatrixFixed"),
        .executableTarget(name: "LogicBlindDiff", path: "Sources/LogicBlindDiff"),
        .executableTarget(name: "LogicExternalMIDIActor", path: "Sources/LogicExternalMIDIActor"),
        .executableTarget(name: "LogicSurfaceExplorer", path: "Sources/LogicSurfaceExplorer"),
        .executableTarget(name: "LogicMCUBridge", path: "Sources/LogicMCUBridge"),
        .executableTarget(name: "LogicMIDISmokeClient", path: "Sources/LogicMIDISmokeClient"),
        .executableTarget(name: "LogicA5AutoSetup", path: "Sources/LogicA5AutoSetup"),
        .executableTarget(name: "LogicA5ControlsSetup", path: "Sources/LogicA5ControlsSetup"),
        .executableTarget(name: "LogicA5PluginProbe", path: "Sources/LogicA5PluginProbe"),
        .executableTarget(name: "LogicA5SafeRoundTrip", path: "Sources/LogicA5SafeRoundTrip"),
        .executableTarget(name: "LogicPhaseAProbe", path: "Sources/LogicPhaseAProbe"),
        .executableTarget(name: "LogicFoundationProbe", path: "Sources/LogicFoundationProbe"),
        .executableTarget(name: "LogicFoundationRepairProbe2", path: "Sources/LogicFoundationRepairProbe2")
    ]
)
