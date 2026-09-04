import AppKit
import ApplicationServices
import CoreMIDI
import Foundation

private struct AXIdentity: Hashable {
    let element: AXUIElement
    static func == (lhs: AXIdentity, rhs: AXIdentity) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

private enum AX {
    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw
    }
    static func string(_ element: AXUIElement, _ attribute: String) -> String? { copy(element, attribute) as? String }
    static func simple(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> String? {
        guard let raw = copy(element, attribute) else { return nil }
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }
    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let raw = copy(element, attribute) else { return nil }
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        return nil
    }
    static func number(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> Double? {
        guard let raw = copy(element, attribute) else { return nil }
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s) }
        return nil
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let raw = copy(element, kAXChildrenAttribute) else { return [] }
        return (raw as? [AXUIElement] ?? []).filter { !CFEqual($0, element) }
    }
    static func actions(_ element: AXUIElement) -> [String] {
        var raw: CFArray?
        guard AXUIElementCopyActionNames(element, &raw) == .success else { return [] }
        return raw as? [String] ?? []
    }
    static func settable(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> Bool {
        var flag = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &flag) == .success && flag.boolValue
    }
    static func perform(_ element: AXUIElement, _ action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }
}

private struct Candidate: Codable {
    let path: String
    let role: String?
    let title: String?
    let identifier: String?
    let elementDescription: String?
    let value: String?
    let valueDescription: String?
    let selected: Bool?
    let focused: Bool?
    let valueSettable: Bool
    let actions: [String]
}

private struct Ref {
    let candidate: Candidate
    let element: AXUIElement
}

private final class Walker {
    let maxDepth: Int
    let maxNodes: Int
    private(set) var visited = 0
    private var seen: Set<AXIdentity> = []

    init(maxDepth: Int, maxNodes: Int) {
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
    }

    func all(from root: AXUIElement) -> [Ref] {
        var stack: [(AXUIElement, Int, String)] = [(root, 0, "app")]
        var output: [Ref] = []
        while let (element, depth, path) = stack.popLast(), visited < maxNodes {
            let id = AXIdentity(element: element)
            guard seen.insert(id).inserted else { continue }
            visited += 1
            let role = AX.string(element, kAXRoleAttribute)
            let candidate = Candidate(
                path: path,
                role: role,
                title: AX.string(element, kAXTitleAttribute),
                identifier: AX.string(element, kAXIdentifierAttribute),
                elementDescription: AX.string(element, kAXDescriptionAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                selected: AX.bool(element, kAXSelectedAttribute),
                focused: AX.bool(element, kAXFocusedAttribute),
                valueSettable: AX.settable(element),
                actions: AX.actions(element)
            )
            output.append(Ref(candidate: candidate, element: element))
            guard depth < maxDepth else { continue }
            if role == kAXMenuBarRole || role == kAXMenuRole { continue }
            let children = AX.children(element)
            for (index, child) in children.enumerated().reversed() {
                let childRole = AX.string(child, kAXRoleAttribute) ?? "AXElement"
                stack.append((child, depth + 1, "\(path)/\(childRole)[\(index)]"))
            }
        }
        return output
    }
}

private struct DeepInventory: Codable {
    let schema: String
    let generatedAt: String
    let visitedNodes: Int
    let trackStrips: [Candidate]
    let interestingControls: [Candidate]
    let selectedElements: [Candidate]
}

private struct MenuInventory: Codable {
    let schema: String
    let generatedAt: String
    let kind: String
    let result: String
    let reason: String?
    let target: Candidate?
    let menuItems: [Candidate]
}

private struct AutomationToggleResult: Codable {
    let schema: String
    let generatedAt: String
    let result: String
    let before: String?
    let toggled: String?
    let restored: String?
    let automationCandidatesWhileOpen: [Candidate]
}

private struct MIDIEndpoint: Codable {
    let direction: String
    let index: Int
    let name: String?
    let manufacturer: String?
    let model: String?
    let uniqueID: Int32?
}

private struct MIDIInventory: Codable {
    let schema: String
    let generatedAt: String
    let sources: [MIDIEndpoint]
    let destinations: [MIDIEndpoint]
}

private func option(_ name: String, args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

private func nowISO() -> String { ISO8601DateFormatter().string(from: Date()) }
private func norm(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

private func writeJSON<T: Encodable>(_ value: T, path: String?) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    if let path { try data.write(to: URL(fileURLWithPath: path)) }
    else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private func logicRoot() -> AXUIElement? {
    guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

private func scan(maxDepth: Int, maxNodes: Int) -> (refs: [Ref], visited: Int)? {
    guard let root = logicRoot() else { return nil }
    let walker = Walker(maxDepth: maxDepth, maxNodes: maxNodes)
    return (walker.all(from: root), walker.visited)
}

private func isTrackStrip(_ c: Candidate) -> Bool {
    c.role == kAXLayoutItemRole && (c.elementDescription ?? "").hasPrefix("Track ") && (c.elementDescription ?? "").contains("“")
}

private func interesting(_ c: Candidate) -> Bool {
    let text = [c.title, c.identifier, c.elementDescription, c.valueDescription].compactMap { $0 }.joined(separator: " ").lowercased()
    let needles = [
        "plug-in", "plugin", "instrument", "audio fx", "midi fx", "preset", "bypass", "parameter",
        "send", "bus", "input", "output", "sidechain", "side chain", "automation", "read", "touch", "latch", "write",
        "volume", "pan", "mute", "solo", "stereo out"
    ]
    return needles.contains { text.contains($0) }
}

private func selectedInspectorPrefix(_ refs: [Ref]) -> String? {
    // The selected-track Inspector channel strip is the AXLayoutItem whose
    // subtree contains both a volume fader and a Stereo Output button. Resolve
    // it structurally rather than by a fixed window/group index.
    let layoutItems = refs.filter { $0.candidate.role == kAXLayoutItemRole }
    for item in layoutItems {
        let prefix = item.candidate.path + "/"
        let descendants = refs.filter { $0.candidate.path.hasPrefix(prefix) }
        let hasVolume = descendants.contains { norm($0.candidate.elementDescription).contains("volume fader") }
        let hasOutput = descendants.contains { norm($0.candidate.elementDescription) == "stereo output" }
        if hasVolume && hasOutput { return item.candidate.path }
    }
    return nil
}

private func pressEscape() {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) else { return }
    down.post(tap: .cgAnnotatedSessionEventTap)
    usleep(50_000)
    up.post(tap: .cgAnnotatedSessionEventTap)
}

private func propertyString(_ object: MIDIObjectRef, _ property: CFString) -> String? {
    var value: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(object, property, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

private func propertyInt(_ object: MIDIObjectRef, _ property: CFString) -> Int32? {
    var value: Int32 = 0
    guard MIDIObjectGetIntegerProperty(object, property, &value) == noErr else { return nil }
    return value
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fputs("Usage: logic-surface-explorer deep-inventory|menu-inventory|automation-toggle|midi-endpoints [options]\n", stderr)
    exit(2)
}
let out = option("--out", args: args)
let maxDepth = Int(option("--depth", args: args) ?? "24") ?? 24
let maxNodes = Int(option("--max-nodes", args: args) ?? "60000") ?? 60_000

if command == "midi-endpoints" {
    var sources: [MIDIEndpoint] = []
    var destinations: [MIDIEndpoint] = []
    for i in 0..<MIDIGetNumberOfSources() {
        let object = MIDIGetSource(i)
        guard object != 0 else { continue }
        sources.append(MIDIEndpoint(
            direction: "source", index: i,
            name: propertyString(object, kMIDIPropertyName),
            manufacturer: propertyString(object, kMIDIPropertyManufacturer),
            model: propertyString(object, kMIDIPropertyModel),
            uniqueID: propertyInt(object, kMIDIPropertyUniqueID)
        ))
    }
    for i in 0..<MIDIGetNumberOfDestinations() {
        let object = MIDIGetDestination(i)
        guard object != 0 else { continue }
        destinations.append(MIDIEndpoint(
            direction: "destination", index: i,
            name: propertyString(object, kMIDIPropertyName),
            manufacturer: propertyString(object, kMIDIPropertyManufacturer),
            model: propertyString(object, kMIDIPropertyModel),
            uniqueID: propertyInt(object, kMIDIPropertyUniqueID)
        ))
    }
    let result = MIDIInventory(schema: "logic-coproducer-midi-endpoints/1.0", generatedAt: nowISO(), sources: sources, destinations: destinations)
    do { try writeJSON(result, path: out) } catch { fputs("Could not write MIDI inventory: \(error)\n", stderr); exit(5) }
    print("RESULT=PASS sources=\(sources.count) destinations=\(destinations.count)")
    exit(0)
}

guard AXIsProcessTrusted(), NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first != nil else {
    fputs("Logic or Accessibility permission unavailable.\n", stderr)
    exit(4)
}

guard let first = scan(maxDepth: maxDepth, maxNodes: maxNodes) else { exit(5) }

if command == "deep-inventory" {
    let tracks = first.refs.map(\.candidate).filter(isTrackStrip)
    let interestingControls = first.refs.map(\.candidate).filter(interesting)
    let selected = first.refs.map(\.candidate).filter { $0.selected == true || $0.focused == true }
    let result = DeepInventory(
        schema: "logic-coproducer-surface-deep-inventory/1.0",
        generatedAt: nowISO(), visitedNodes: first.visited,
        trackStrips: tracks,
        interestingControls: interestingControls,
        selectedElements: selected
    )
    do { try writeJSON(result, path: out) } catch { fputs("Could not write deep inventory: \(error)\n", stderr); exit(5) }
    print("RESULT=PASS tracks=\(tracks.count) interesting=\(interestingControls.count) visited=\(first.visited)")
    exit(0)
}

if command == "menu-inventory" {
    guard let kind = option("--kind", args: args) else { fputs("menu-inventory requires --kind plugin|send|output.\n", stderr); exit(2) }
    guard let prefix = selectedInspectorPrefix(first.refs) else {
        let result = MenuInventory(schema: "logic-coproducer-safe-menu-inventory/1.0", generatedAt: nowISO(), kind: kind, result: "SKIP", reason: "selected Inspector channel strip not resolved", target: nil, menuItems: [])
        try? writeJSON(result, path: out)
        print("RESULT=SKIP reason=inspector-not-resolved")
        exit(10)
    }
    let wanted: String
    switch kind {
    case "plugin": wanted = "audio plug-in"
    case "send": wanted = "send button"
    case "output": wanted = "stereo output"
    default: fputs("Unknown menu kind.\n", stderr); exit(2)
    }
    let candidates = first.refs.filter {
        $0.candidate.path.hasPrefix(prefix + "/") &&
        $0.candidate.role == kAXButtonRole &&
        norm($0.candidate.elementDescription) == wanted &&
        $0.candidate.actions.contains(kAXPressAction as String)
    }
    guard candidates.count == 1, let target = candidates.first else {
        let result = MenuInventory(schema: "logic-coproducer-safe-menu-inventory/1.0", generatedAt: nowISO(), kind: kind, result: "SKIP", reason: "safe target count=\(candidates.count)", target: nil, menuItems: [])
        try? writeJSON(result, path: out)
        print("RESULT=SKIP target_count=\(candidates.count)")
        exit(10)
    }
    let error = AX.perform(target.element, kAXPressAction as String)
    guard error == .success else {
        let result = MenuInventory(schema: "logic-coproducer-safe-menu-inventory/1.0", generatedAt: nowISO(), kind: kind, result: "FAIL", reason: "AXPress failed \(error.rawValue)", target: target.candidate, menuItems: [])
        try? writeJSON(result, path: out)
        print("RESULT=FAIL press_error=\(error.rawValue)")
        exit(20)
    }
    usleep(300_000)
    let second = scan(maxDepth: maxDepth, maxNodes: maxNodes)
    let menuItems = second?.refs.map(\.candidate).filter { $0.role == kAXMenuItemRole } ?? []
    pressEscape()
    usleep(180_000)
    let result = MenuInventory(schema: "logic-coproducer-safe-menu-inventory/1.0", generatedAt: nowISO(), kind: kind, result: "PASS", reason: nil, target: target.candidate, menuItems: menuItems)
    do { try writeJSON(result, path: out) } catch { fputs("Could not write menu inventory: \(error)\n", stderr); exit(5) }
    print("RESULT=PASS kind=\(kind) menu_items=\(menuItems.count)")
    exit(0)
}

if command == "automation-toggle" {
    let candidates = first.refs.filter {
        $0.candidate.role == kAXCheckBoxRole &&
        norm($0.candidate.elementDescription) == "show/hide automation" &&
        $0.candidate.actions.contains(kAXPressAction as String)
    }
    guard candidates.count == 1, let target = candidates.first else {
        let result = AutomationToggleResult(schema: "logic-coproducer-automation-view-toggle/1.0", generatedAt: nowISO(), result: "SKIP", before: nil, toggled: nil, restored: nil, automationCandidatesWhileOpen: [])
        try? writeJSON(result, path: out)
        print("RESULT=SKIP target_count=\(candidates.count)")
        exit(10)
    }
    let before = target.candidate.value
    guard AX.perform(target.element, kAXPressAction as String) == .success else { exit(20) }
    usleep(450_000)
    guard let openScan = scan(maxDepth: maxDepth, maxNodes: maxNodes) else { exit(20) }
    let reopenedTarget = openScan.refs.first { $0.candidate.path == target.candidate.path }
    let toggled = reopenedTarget?.candidate.value
    let automation = openScan.refs.map(\.candidate).filter { c in
        let text = [c.title, c.elementDescription, c.valueDescription].compactMap { $0 }.joined(separator: " ").lowercased()
        return text.contains("automation") || text.contains("volume") || text.contains("pan") || text.contains("read") || text.contains("touch") || text.contains("latch") || text.contains("write")
    }
    guard let current = reopenedTarget, AX.perform(current.element, kAXPressAction as String) == .success else { exit(30) }
    usleep(450_000)
    let restoredScan = scan(maxDepth: maxDepth, maxNodes: maxNodes)
    let restored = restoredScan?.refs.first { $0.candidate.path == target.candidate.path }?.candidate.value
    let ok = before == restored && before != toggled
    let result = AutomationToggleResult(schema: "logic-coproducer-automation-view-toggle/1.0", generatedAt: nowISO(), result: ok ? "PASS" : "RESTORE_FAIL", before: before, toggled: toggled, restored: restored, automationCandidatesWhileOpen: automation)
    try? writeJSON(result, path: out)
    if ok {
        print("RESULT=PASS before=\(before ?? "nil") toggled=\(toggled ?? "nil") restored=\(restored ?? "nil") candidates=\(automation.count)")
    } else {
        print("RESULT=RESTORE_FAIL before=\(before ?? "nil") toggled=\(toggled ?? "nil") restored=\(restored ?? "nil")")
        exit(30)
    }
    exit(0)
}

fputs("Unknown command: \(command)\n", stderr)
exit(2)
