import AppKit
import ApplicationServices
import Foundation

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

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

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

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(raw, to: AXValue.self)
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(raw, to: AXValue.self)
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }
}

private struct Candidate {
    let path: String
    let role: String?
    let subrole: String?
    let title: String?
    let identifier: String?
    let description: String?
    let help: String?
    let value: String?
    let valueDescription: String?
    let enabled: Bool?
    let actions: [String]
    let childCount: Int
    let position: CGPoint?
    let size: CGSize?
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

            let children = AX.children(element)
            output.append(Ref(candidate: Candidate(
                path: path,
                role: AX.string(element, kAXRoleAttribute),
                subrole: AX.string(element, kAXSubroleAttribute),
                title: AX.string(element, kAXTitleAttribute),
                identifier: AX.string(element, kAXIdentifierAttribute),
                description: AX.string(element, kAXDescriptionAttribute),
                help: AX.string(element, kAXHelpAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                enabled: AX.bool(element, kAXEnabledAttribute),
                actions: AX.actions(element),
                childCount: children.count,
                position: AX.point(element, kAXPositionAttribute),
                size: AX.size(element, kAXSizeAttribute)
            ), element: element))

            guard depth < 30 else { continue }
            for (index, child) in children.enumerated().reversed() {
                let role = AX.string(child, kAXRoleAttribute) ?? "AXElement"
                stack.append((child, depth + 1, "\(path)/\(role)[\(index)]"))
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

private func fields(_ c: Candidate) -> [String] {
    [c.title, c.identifier, c.description, c.help, c.value, c.valueDescription].compactMap { $0 }
}

private func text(_ c: Candidate) -> String {
    fields(c).joined(separator: " ").lowercased()
}

private func exact(_ c: Candidate, _ wanted: String) -> Bool {
    fields(c).contains { norm($0) == norm(wanted) }
}

private func subtree(_ refs: [Ref], prefix: String) -> [Ref] {
    refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") }
}

private func depth(_ path: String) -> Int {
    path.reduce(into: 0) { if $1 == "/" { $0 += 1 } }
}

private func parentPath(_ path: String) -> String? {
    guard let slash = path.lastIndex(of: "/") else { return nil }
    return String(path[..<slash])
}

private func isMainMixerStripPath(_ path: String) -> Bool {
    path.contains("/AXSplitGroup[") && path.contains("/AXScrollArea[") && path.contains("/AXLayoutItem[")
}

private func mixerStrips(_ label: String, refs: [Ref]) -> [Ref] {
    refs.filter { ref in
        guard ref.candidate.role == kAXLayoutItemRole, isMainMixerStripPath(ref.candidate.path) else { return false }
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

private func isKnownNonInsertText(_ value: String) -> Bool {
    let needles = [
        "send", "input", "output", "stereo out", "volume", "pan", "mute", "solo",
        "record", "freeze", "automation", "read", "touch", "latch", "write", "group",
        "channel mode", "instrument", "midi fx", "eq", "setting", "gain reduction"
    ]
    return needles.contains { value.contains($0) }
}

private func plausibleSlotFrame(_ c: Candidate) -> Bool {
    guard let size = c.size else { return false }
    return size.width >= 44 && size.height >= 12 && size.height <= 24
}

private func semanticEmptyCandidate(_ ref: Ref) -> Bool {
    let c = ref.candidate
    guard c.role == kAXButtonRole, c.enabled != false else { return false }
    let t = text(c)
    let semantic = t.contains("audio plug-in") || t.contains("audio plugin") || t.contains("audio fx")
    return semantic && !isKnownNonInsertText(t)
}

private func geometryEmptyCandidate(_ ref: Ref) -> Bool {
    let c = ref.candidate
    guard c.role == kAXButtonRole,
          c.enabled != false,
          c.childCount == 0,
          c.subrole != kAXSwitchSubrole as String,
          plausibleSlotFrame(c) else { return false }
    return !isKnownNonInsertText(text(c))
}

private func payload(_ ref: Ref, stripPath: String) -> [String: Any] {
    let c = ref.candidate
    var object: [String: Any] = [
        "path": c.path,
        "relativePath": String(c.path.dropFirst(stripPath.count)),
        "relativeDepth": max(0, depth(c.path) - depth(stripPath)),
        "role": c.role ?? NSNull(),
        "subrole": c.subrole ?? NSNull(),
        "title": c.title ?? NSNull(),
        "identifier": c.identifier ?? NSNull(),
        "description": c.description ?? NSNull(),
        "help": c.help ?? NSNull(),
        "value": c.value ?? NSNull(),
        "valueDescription": c.valueDescription ?? NSNull(),
        "enabled": c.enabled ?? NSNull(),
        "actions": c.actions,
        "childCount": c.childCount,
        "semanticEmptyCandidate": semanticEmptyCandidate(ref),
        "geometryEmptyCandidate": geometryEmptyCandidate(ref),
        "hasLegacyPluginMenuAction": c.actions.contains(legacyPluginMenuAction)
    ]
    if let p = c.position {
        object["position"] = ["x": p.x, "y": p.y]
    } else {
        object["position"] = NSNull()
    }
    if let s = c.size {
        object["size"] = ["width": s.width, "height": s.height]
    } else {
        object["size"] = NSNull()
    }
    return object
}

private func writeJSON(_ object: Any, path: String) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func run(track: String, out: String) -> Int32 {
    guard AXIsProcessTrusted(),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else {
        writeJSON(["result": "FAIL", "reason": "logic-or-accessibility-unavailable"], path: out)
        print("RESULT=FAIL reason=logic-or-accessibility-unavailable")
        return 20
    }

    _ = app.activate(options: [.activateIgnoringOtherApps])
    usleep(180_000)
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let refs = Walker().all(from: root)
    let strips = mixerStrips(track, refs: refs)

    guard strips.count == 1 else {
        writeJSON([
            "schema": "logic-coproducer-plugin-slot-census/3.0",
            "result": "FAIL",
            "reason": "main-mixer-strip-not-unique",
            "stripCount": strips.count,
            "stripPaths": strips.map { $0.candidate.path }
        ], path: out)
        print("RESULT=FAIL reason=main-mixer-strip-not-unique count=\(strips.count)")
        return 20
    }

    let strip = strips[0]
    let descendants = subtree(refs, prefix: strip.candidate.path)
        .filter { depth($0.candidate.path) <= depth(strip.candidate.path) + 5 }
        .sorted { $0.candidate.path < $1.candidate.path }
    let direct = descendants.filter { parentPath($0.candidate.path) == strip.candidate.path }
    let buttons = descendants.filter { $0.candidate.role == kAXButtonRole }
    let actionButtons = buttons.filter { !$0.candidate.actions.isEmpty }
    let legacy = buttons.filter { $0.candidate.actions.contains(legacyPluginMenuAction) }
    let semantic = buttons.filter(semanticEmptyCandidate)
    let geometry = buttons.filter(geometryEmptyCandidate)

    writeJSON([
        "schema": "logic-coproducer-plugin-slot-census/3.0",
        "result": "PASS",
        "track": track,
        "stripPath": strip.candidate.path,
        "directChildCount": direct.count,
        "descendantCountDepth5": descendants.count,
        "buttonCountDepth5": buttons.count,
        "actionButtonCountDepth5": actionButtons.count,
        "legacyActionCountDepth5": legacy.count,
        "semanticEmptyCandidateCount": semantic.count,
        "geometryEmptyCandidateCount": geometry.count,
        "directChildren": direct.map { payload($0, stripPath: strip.candidate.path) },
        "buttonsDepth5": buttons.map { payload($0, stripPath: strip.candidate.path) },
        "legacyActionMatches": legacy.map { payload($0, stripPath: strip.candidate.path) },
        "semanticEmptyCandidates": semantic.map { payload($0, stripPath: strip.candidate.path) },
        "geometryEmptyCandidates": geometry.map { payload($0, stripPath: strip.candidate.path) }
    ], path: out)

    print("RESULT=PASS census_only=yes direct_children=\(direct.count) buttons=\(buttons.count) action_buttons=\(actionButtons.count) legacy_actions=\(legacy.count) semantic_candidates=\(semantic.count) geometry_candidates=\(geometry.count)")
    return 0
}

let args = Array(CommandLine.arguments.dropFirst())
let track = option("--track", args: args) ?? "Audio 1"
guard let out = option("--out", args: args) else {
    fputs("Usage: logic-plugin-slot-census --track 'Audio 1' --out PATH\n", stderr)
    exit(2)
}
exit(run(track: track, out: out))
