import AppKit
import ApplicationServices
import Foundation

// Technique validated in the MIT-licensed MongLong0214/logic-pro-mcp project.
// This probe is intentionally read-only with respect to the Logic project: it
// opens one empty Audio FX slot menu, observes its AX surface, then dismisses it.
private let legacyPluginMenuAction = "Name:Open plug-in menu with legacy plug-ins\nTarget:0x0\nSelector:(null)"

private struct AXID: Hashable {
    let element: AXUIElement
    static func == (lhs: AXID, rhs: AXID) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

private enum AX {
    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success ? raw : nil
    }
    static func string(_ element: AXUIElement, _ attribute: String) -> String? { copy(element, attribute) as? String }
    static func simple(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> String? {
        guard let raw = copy(element, attribute) else { return nil }
        if let value = raw as? String { return value }
        if let value = raw as? NSNumber { return value.stringValue }
        return nil
    }
    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let raw = copy(element, attribute) else { return nil }
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
        return nil
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (copy(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { !CFEqual($0, element) }
    }
    static func actions(_ element: AXUIElement) -> [String] {
        var raw: CFArray?
        guard AXUIElementCopyActionNames(element, &raw) == .success else { return [] }
        return raw as? [String] ?? []
    }
    static func perform(_ element: AXUIElement, _ action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }
}

private struct Candidate {
    let path: String
    let role: String?
    let title: String?
    let identifier: String?
    let description: String?
    let value: String?
    let valueDescription: String?
    let enabled: Bool?
    let actions: [String]
}

private struct Ref {
    let candidate: Candidate
    let element: AXUIElement
}

private final class Walker {
    private var seen: Set<AXID> = []

    func all(from root: AXUIElement) -> [Ref] {
        var stack: [(AXUIElement, Int, String)] = [(root, 0, "app")]
        var output: [Ref] = []
        var visited = 0

        while let (element, depth, path) = stack.popLast(), visited < 100_000 {
            let id = AXID(element: element)
            guard seen.insert(id).inserted else { continue }
            visited += 1

            let role = AX.string(element, kAXRoleAttribute)
            output.append(Ref(candidate: Candidate(
                path: path,
                role: role,
                title: AX.string(element, kAXTitleAttribute),
                identifier: AX.string(element, kAXIdentifierAttribute),
                description: AX.string(element, kAXDescriptionAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                enabled: AX.bool(element, kAXEnabledAttribute),
                actions: AX.actions(element)
            ), element: element))

            guard depth < 30 else { continue }
            let children = AX.children(element)
            for (index, child) in children.enumerated().reversed() {
                let childRole = AX.string(child, kAXRoleAttribute) ?? "AXElement"
                stack.append((child, depth + 1, "\(path)/\(childRole)[\(index)]"))
            }
        }
        return output
    }
}

private func option(_ name: String, args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

private func norm(_ value: String?) -> String {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func fields(_ candidate: Candidate) -> [String] {
    [candidate.title, candidate.identifier, candidate.description, candidate.value, candidate.valueDescription].compactMap { $0 }
}

private func text(_ candidate: Candidate) -> String {
    fields(candidate).joined(separator: " ").lowercased()
}

private func exact(_ candidate: Candidate, _ wanted: String) -> Bool {
    fields(candidate).contains { norm($0) == norm(wanted) }
}

private func subtree(_ refs: [Ref], prefix: String) -> [Ref] {
    refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") }
}

private func logic() -> (NSRunningApplication, AXUIElement)? {
    guard AXIsProcessTrusted(),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { return nil }
    return (app, AXUIElementCreateApplication(app.processIdentifier))
}

private func activate() -> Bool {
    guard let (app, _) = logic() else { return false }
    return app.activate(options: [.activateIgnoringOtherApps])
}

private func scan() -> [Ref]? {
    guard let (_, root) = logic() else { return nil }
    return Walker().all(from: root)
}

private func postEscape() {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) else { return }
    down.post(tap: .cgAnnotatedSessionEventTap)
    usleep(45_000)
    up.post(tap: .cgAnnotatedSessionEventTap)
}

private func writeJSON(_ object: Any, path: String) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func isMainMixerStripPath(_ path: String) -> Bool {
    path.contains("/AXSplitGroup[") &&
        path.contains("/AXScrollArea[") &&
        path.contains("/AXLayoutItem[")
}

private func mixerStrips(_ label: String, refs: [Ref]) -> [Ref] {
    refs.filter { ref in
        guard ref.candidate.role == kAXLayoutItemRole,
              isMainMixerStripPath(ref.candidate.path) else { return false }
        let descendants = subtree(refs, prefix: ref.candidate.path)
        let hasLabel = descendants.contains { exact($0.candidate, label) }
        let hasVolume = descendants.contains {
            $0.candidate.role == kAXSliderRole && norm($0.candidate.description) == "volume"
        }
        let hasPan = descendants.contains {
            $0.candidate.role == kAXSliderRole &&
                (norm($0.candidate.description).contains("pan") || norm($0.candidate.valueDescription).contains("pan"))
        }
        return hasLabel && hasVolume && hasPan
    }.sorted { $0.candidate.path < $1.candidate.path }
}

private func occupiedPluginName(_ child: AXUIElement) -> String? {
    guard AX.string(child, kAXRoleAttribute) == kAXGroupRole else { return nil }
    let children = AX.children(child)
    let hasCheckbox = children.contains { AX.string($0, kAXRoleAttribute) == kAXCheckBoxRole }
    let buttonCount = children.filter { AX.string($0, kAXRoleAttribute) == kAXButtonRole }.count
    guard hasCheckbox && buttonCount >= 2 else { return nil }
    return AX.string(child, kAXDescriptionAttribute) ?? AX.string(child, kAXTitleAttribute) ?? "<occupied-unreadable>"
}

private func emptyCustomSlots(_ strip: Ref) -> [AXUIElement] {
    AX.children(strip.element).filter { child in
        AX.string(child, kAXRoleAttribute) == kAXButtonRole &&
            AX.actions(child).contains(legacyPluginMenuAction)
    }
}

private func occupiedNames(_ strip: Ref) -> [String] {
    AX.children(strip.element).compactMap(occupiedPluginName)
}

private func buttonActionEvidence(_ strip: Ref) -> [[String: Any]] {
    AX.children(strip.element).compactMap { child in
        guard AX.string(child, kAXRoleAttribute) == kAXButtonRole else { return nil }
        let actions = AX.actions(child)
        guard !actions.isEmpty else { return nil }
        return [
            "description": AX.string(child, kAXDescriptionAttribute) ?? "",
            "title": AX.string(child, kAXTitleAttribute) ?? "",
            "value": AX.simple(child) ?? "",
            "actions": actions
        ]
    }
}

private struct SurfaceCensus {
    let menuPaths: Set<String>
    let compressorCount: Int
    let dynamicsCount: Int
    let textFieldPaths: Set<String>
}

private func surfaceCensus(_ refs: [Ref]) -> SurfaceCensus {
    let menuPaths = Set(refs.filter { $0.candidate.role == kAXMenuRole }.map { $0.candidate.path })
    let compressorCount = refs.filter { $0.candidate.role == kAXMenuItemRole && exact($0.candidate, "Compressor") }.count
    let dynamicsCount = refs.filter { $0.candidate.role == kAXMenuItemRole && exact($0.candidate, "Dynamics") }.count
    let textFieldPaths = Set(refs.filter { $0.candidate.role == kAXTextFieldRole }.map { $0.candidate.path })
    return SurfaceCensus(menuPaths: menuPaths, compressorCount: compressorCount, dynamicsCount: dynamicsCount, textFieldPaths: textFieldPaths)
}

private func popupDeltaExists(baseline: SurfaceCensus, current: SurfaceCensus) -> Bool {
    !current.menuPaths.subtracting(baseline.menuPaths).isEmpty ||
        current.compressorCount > baseline.compressorCount ||
        current.dynamicsCount > baseline.dynamicsCount ||
        !current.textFieldPaths.subtracting(baseline.textFieldPaths).isEmpty
}

private func run(track: String, out: String) -> Int32 {
    guard activate() else {
        writeJSON(["result": "FAIL", "reason": "logic-or-accessibility-unavailable"], path: out)
        print("RESULT=FAIL reason=logic-or-accessibility-unavailable")
        return 20
    }
    usleep(180_000)

    guard let baselineRefs = scan() else {
        writeJSON(["result": "FAIL", "reason": "ax-scan-unavailable"], path: out)
        print("RESULT=FAIL reason=ax-scan-unavailable")
        return 20
    }

    let strips = mixerStrips(track, refs: baselineRefs)
    guard strips.count == 1 else {
        writeJSON([
            "schema": "logic-coproducer-plugin-slot-surface/2.0",
            "result": "FAIL",
            "reason": "main-mixer-strip-not-unique",
            "stripCount": strips.count,
            "stripPaths": strips.map { $0.candidate.path }
        ], path: out)
        print("RESULT=FAIL reason=main-mixer-strip-not-unique count=\(strips.count)")
        return 20
    }

    let strip = strips[0]
    let occupiedBefore = occupiedNames(strip)
    let emptySlots = emptyCustomSlots(strip)
    let baselineSurface = surfaceCensus(baselineRefs)

    guard occupiedBefore.isEmpty else {
        writeJSON([
            "schema": "logic-coproducer-plugin-slot-surface/2.0",
            "result": "SKIP",
            "reason": "audio-1-chain-not-empty",
            "stripPath": strip.candidate.path,
            "occupied": occupiedBefore
        ], path: out)
        print("RESULT=SKIP reason=audio-1-chain-not-empty occupied=\(occupiedBefore.count)")
        return 10
    }

    guard let targetSlot = emptySlots.first else {
        writeJSON([
            "schema": "logic-coproducer-plugin-slot-surface/2.0",
            "result": "SKIP",
            "reason": "custom-slot-action-not-observed",
            "stripPath": strip.candidate.path,
            "buttonActions": buttonActionEvidence(strip)
        ], path: out)
        print("RESULT=SKIP reason=custom-slot-action-not-observed")
        return 10
    }

    let actionRC = AX.perform(targetSlot, legacyPluginMenuAction)
    usleep(500_000)
    let openedRefs = scan() ?? []
    let openedSurface = surfaceCensus(openedRefs)

    let newMenus = openedSurface.menuPaths.subtracting(baselineSurface.menuPaths).sorted()
    let newTextFields = openedSurface.textFieldPaths.subtracting(baselineSurface.textFieldPaths).sorted()
    let compressorDelta = openedSurface.compressorCount - baselineSurface.compressorCount
    let dynamicsDelta = openedSurface.dynamicsCount - baselineSurface.dynamicsCount
    let popupObserved = popupDeltaExists(baseline: baselineSurface, current: openedSurface)
    let pluginNavigationObserved = compressorDelta > 0 || dynamicsDelta > 0 || !newTextFields.isEmpty

    postEscape()
    usleep(300_000)
    var finalRefs = scan() ?? []
    var finalSurface = surfaceCensus(finalRefs)
    if popupDeltaExists(baseline: baselineSurface, current: finalSurface) {
        postEscape()
        usleep(300_000)
        finalRefs = scan() ?? []
        finalSurface = surfaceCensus(finalRefs)
    }

    let finalStrips = mixerStrips(track, refs: finalRefs)
    guard finalStrips.count == 1 else {
        writeJSON([
            "schema": "logic-coproducer-plugin-slot-surface/2.0",
            "result": "SAFETY_FAIL",
            "reason": "could-not-reverify-main-mixer-strip-after-dismissal",
            "stripCount": finalStrips.count
        ], path: out)
        print("RESULT=SAFETY_FAIL reason=could-not-reverify-main-mixer-strip-after-dismissal")
        return 30
    }

    let occupiedAfter = occupiedNames(finalStrips[0])
    let popupLeftOpen = popupDeltaExists(baseline: baselineSurface, current: finalSurface)
    if !occupiedAfter.isEmpty || popupLeftOpen {
        writeJSON([
            "schema": "logic-coproducer-plugin-slot-surface/2.0",
            "result": "SAFETY_FAIL",
            "reason": !occupiedAfter.isEmpty ? "unexpected-plugin-chain-change" : "popup-not-dismissed",
            "occupiedAfter": occupiedAfter,
            "popupLeftOpen": popupLeftOpen
        ], path: out)
        print("RESULT=SAFETY_FAIL reason=\(!occupiedAfter.isEmpty ? "unexpected-plugin-chain-change" : "popup-not-dismissed")")
        return 30
    }

    let pass = popupObserved && pluginNavigationObserved
    writeJSON([
        "schema": "logic-coproducer-plugin-slot-surface/2.0",
        "result": pass ? "PASS" : "NEEDS_ANALYSIS",
        "track": track,
        "stripPath": strip.candidate.path,
        "legacyActionReturnCode": actionRC.rawValue,
        "emptyCustomSlotCount": emptySlots.count,
        "newMenuPaths": newMenus,
        "newTextFieldPaths": newTextFields,
        "compressorMenuItemDelta": compressorDelta,
        "dynamicsMenuItemDelta": dynamicsDelta,
        "popupObserved": popupObserved,
        "pluginNavigationObserved": pluginNavigationObserved,
        "projectChainVerifiedUnchanged": true
    ], path: out)

    print("RESULT=\(pass ? "PASS" : "NEEDS_ANALYSIS") popup=\(popupObserved ? "yes" : "no") navigation=\(pluginNavigationObserved ? "yes" : "no") chain_unchanged=yes")
    return pass ? 0 : 10
}

let args = Array(CommandLine.arguments.dropFirst())
let track = option("--track", args: args) ?? "Audio 1"
let out = option("--out", args: args) ?? FileManager.default.currentDirectoryPath + "/plugin-slot-surface-v2.json"
exit(run(track: track, out: out))
