import AppKit
import ApplicationServices
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

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let raw = copy(element, kAXChildrenAttribute) else { return [] }
        return (raw as? [AXUIElement] ?? []).filter { !CFEqual($0, element) }
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var raw: CFArray?
        guard AXUIElementCopyActionNames(element, &raw) == .success else { return [] }
        return raw as? [String] ?? []
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var flag = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &flag) == .success && flag.boolValue
    }

    static func press(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    static func select(_ element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(element, kAXSelectedAttribute as CFString, kCFBooleanTrue)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement) -> CGSize? {
        guard let raw = copy(element, kAXSizeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(raw as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}

struct Candidate: Codable {
    let path: String
    let role: String?
    let title: String?
    let elementDescription: String?
    let value: String?
    let valueDescription: String?
    let enabled: Bool?
    let visible: Bool?
    let selected: Bool?
    let actions: [String]
}

struct Ref {
    let candidate: Candidate
    let element: AXUIElement
}

private final class Walker {
    private let maxDepth: Int
    private let maxNodes: Int
    private(set) var visited = 0
    private var seen: Set<AXIdentity> = []

    init(maxDepth: Int = 28, maxNodes: Int = 80_000) {
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
            output.append(Ref(candidate: Candidate(
                path: path,
                role: role,
                title: AX.string(element, kAXTitleAttribute),
                elementDescription: AX.string(element, kAXDescriptionAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                enabled: AX.bool(element, kAXEnabledAttribute),
                visible: AX.bool(element, "AXVisible"),
                selected: AX.bool(element, kAXSelectedAttribute),
                actions: AX.actions(element)
            ), element: element))
            guard depth < maxDepth else { continue }
            for (index, child) in AX.children(element).enumerated().reversed() {
                let childRole = AX.string(child, kAXRoleAttribute) ?? "AXElement"
                stack.append((child, depth + 1, "\(path)/\(childRole)[\(index)]"))
            }
        }
        return output
    }
}

private struct SetupEvidence: Codable {
    let schema: String
    let generatedAt: String
    let result: String
    let reason: String?
    let trackStripPath: String?
    let pluginWindowPath: String?
    let pluginWindowTitle: String?
    let semanticParameterHits: [String]
    let numericParameterHits: [String]
    let actionsPerformed: [String]
    let visitedNodes: Int
}

private let targetTrack = "Studio Grand"
private let parameterPatterns: [(String, [String])] = [
    ("Stereo Mic A", ["stereo mic a"]),
    ("Stereo Mic B", ["stereo mic b"]),
    ("Mono Mic", ["mono mic"]),
    ("Main Volume", ["main volume"]),
    ("Pedal Noise", ["pedal noise"]),
    ("Key Noise", ["key noise"]),
    ("Release Samples", ["release samples"]),
    ("Sympathetic Resonance", ["sympathetic resonance", "sympathetic res"])
]

private func norm(_ value: String?) -> String {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func fields(_ candidate: Candidate) -> [String] {
    [candidate.title, candidate.elementDescription, candidate.value, candidate.valueDescription].compactMap { $0 }
}

private func text(_ candidate: Candidate) -> String {
    fields(candidate).joined(separator: " ").lowercased()
}

private func exactField(_ candidate: Candidate, _ wanted: String) -> Bool {
    let q = norm(wanted)
    return fields(candidate).contains { norm($0) == q }
}

private func subtree(_ refs: [Ref], _ prefix: String) -> [Ref] {
    refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") }
}

private func scan() -> (refs: [Ref], visited: Int)? {
    guard AXIsProcessTrusted(),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first
    else { return nil }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    let walker = Walker()
    return (walker.all(from: root), walker.visited)
}

private func activateLogic() -> Bool {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { return false }
    return app.activate(options: [.activateIgnoringOtherApps])
}

private func targetStrip(in refs: [Ref]) -> Ref? {
    let layouts = refs.filter { $0.candidate.role == kAXLayoutItemRole }
    let matches = layouts.filter { item in
        let descendants = subtree(refs, item.candidate.path)
        let hasLabel = descendants.contains { text($0.candidate).contains(targetTrack.lowercased()) }
        let hasVolume = descendants.contains {
            $0.candidate.role == kAXSliderRole && norm($0.candidate.elementDescription) == "volume"
        }
        let hasPan = descendants.contains {
            $0.candidate.role == kAXSliderRole && text($0.candidate).contains("pan")
        }
        return hasLabel && hasVolume && hasPan
    }
    return matches.count == 1 ? matches[0] : nil
}

private func pluginWindow(in refs: [Ref]) -> Ref? {
    let windows = refs.filter { $0.candidate.role == kAXWindowRole }
    let scored: [(Ref, Int)] = windows.compactMap { window in
        let descendants = subtree(refs, window.candidate.path)
        var score = 0
        if norm(window.candidate.title) == targetTrack.lowercased() { score += 6 }
        if descendants.contains(where: { text($0.candidate).contains("studio piano") }) { score += 5 }
        let hits = semanticHits(in: descendants).count
        score += min(hits, 4)
        return score >= 7 ? (window, score) : nil
    }.sorted { $0.1 > $1.1 }
    guard let first = scored.first else { return nil }
    if scored.count > 1 && scored[1].1 == first.1 { return nil }
    return first.0
}

private func semanticHits(in refs: [Ref]) -> [String] {
    parameterPatterns.compactMap { name, patterns in
        refs.contains { ref in patterns.contains { text(ref.candidate).contains($0) } } ? name : nil
    }
}

private func numericHits(in refs: [Ref]) -> [String] {
    parameterPatterns.compactMap { name, patterns in
        let found = refs.contains { ref in
            guard ref.candidate.role == kAXSliderRole,
                  AX.isSettable(ref.element, kAXValueAttribute),
                  ref.candidate.enabled != false
            else { return false }
            return patterns.contains { text(ref.candidate).contains($0) }
        }
        return found ? name : nil
    }
}

private func pressExactMenuItem(_ refs: [Ref], title: String) -> Bool {
    let all = refs.filter {
        $0.candidate.role == kAXMenuItemRole &&
        exactField($0.candidate, title) &&
        $0.candidate.enabled != false &&
        $0.candidate.actions.contains(kAXPressAction as String)
    }
    let visible = all.filter { $0.candidate.visible != false }
    let candidates = visible.isEmpty ? all : visible
    guard candidates.count == 1 else { return false }
    return AX.press(candidates[0].element) == .success
}

private func postX() {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: false) else { return }
    down.post(tap: .cgAnnotatedSessionEventTap)
    usleep(50_000)
    up.post(tap: .cgAnnotatedSessionEventTap)
}

private func clickCenter(_ ref: Ref) -> Bool {
    guard ref.candidate.enabled != false,
          ref.candidate.visible != false,
          let origin = AX.point(ref.element, kAXPositionAttribute),
          let size = AX.size(ref.element),
          size.width > 2, size.height > 2
    else { return false }
    let point = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    else { return false }
    down.post(tap: .cgAnnotatedSessionEventTap)
    usleep(70_000)
    up.post(tap: .cgAnnotatedSessionEventTap)
    return true
}

private func nearestPressableAncestor(of ref: Ref, within prefix: String, refs: [Ref]) -> Ref? {
    var path = ref.candidate.path
    let byPath = Dictionary(uniqueKeysWithValues: refs.map { ($0.candidate.path, $0) })
    while path.hasPrefix(prefix) {
        if let candidate = byPath[path],
           candidate.candidate.enabled != false,
           candidate.candidate.actions.contains(kAXPressAction as String) {
            return candidate
        }
        guard let slash = path.lastIndex(of: "/") else { break }
        path = String(path[..<slash])
    }
    return nil
}

private func activateRef(_ ref: Ref, within prefix: String, refs: [Ref], actions: inout [String], label: String) -> Bool {
    if ref.candidate.actions.contains(kAXPressAction as String), AX.press(ref.element) == .success {
        actions.append(label + "-via-AXPress")
        return true
    }
    if let ancestor = nearestPressableAncestor(of: ref, within: prefix, refs: refs), AX.press(ancestor.element) == .success {
        actions.append(label + "-via-pressable-ancestor")
        return true
    }
    if clickCenter(ref) {
        actions.append(label + "-via-center-click")
        return true
    }
    return false
}

private func ensureTargetStrip(actions: inout [String]) -> (Ref, [Ref], Int)? {
    guard var current = scan() else { return nil }
    if let strip = targetStrip(in: current.refs) { return (strip, current.refs, current.visited) }

    if pressExactMenuItem(current.refs, title: "Show Mixer") {
        actions.append("opened-mixer-via-menu")
        usleep(500_000)
        if let rescanned = scan(), let strip = targetStrip(in: rescanned.refs) {
            return (strip, rescanned.refs, rescanned.visited)
        }
    }

    _ = activateLogic()
    postX()
    actions.append("opened-mixer-via-X-fallback")
    usleep(600_000)
    current = scan() ?? current
    guard let strip = targetStrip(in: current.refs) else { return nil }
    return (strip, current.refs, current.visited)
}

private func selectStripIfPossible(_ strip: Ref, refs: [Ref], actions: inout [String]) {
    let descendants = subtree(refs, strip.candidate.path)
    if strip.candidate.selected == true || descendants.contains(where: { $0.candidate.selected == true }) {
        actions.append("Studio-Grand-already-selected")
        return
    }
    if AX.isSettable(strip.element, kAXSelectedAttribute), AX.select(strip.element) == .success {
        actions.append("selected-Studio-Grand-strip")
        usleep(250_000)
        return
    }
    let labelRefs = descendants.filter { exactField($0.candidate, targetTrack) }
    for ref in labelRefs {
        if AX.isSettable(ref.element, kAXSelectedAttribute), AX.select(ref.element) == .success {
            actions.append("selected-Studio-Grand-label")
            usleep(250_000)
            return
        }
        if activateRef(ref, within: strip.candidate.path, refs: descendants, actions: &actions, label: "selected-Studio-Grand-label") {
            usleep(250_000)
            return
        }
    }
}

private func openInstrumentFromStrip(_ strip: Ref, refs: [Ref], actions: inout [String]) -> Bool {
    let descendants = subtree(refs, strip.candidate.path)

    let studioPiano = descendants.filter {
        $0.candidate.enabled != false && $0.candidate.visible != false && text($0.candidate).contains("studio piano")
    }
    let studioLeaves = studioPiano.filter { candidate in
        !studioPiano.contains(where: { other in
            other.candidate.path != candidate.candidate.path &&
            other.candidate.path.hasPrefix(candidate.candidate.path + "/")
        })
    }
    if studioLeaves.count == 1,
       activateRef(studioLeaves[0], within: strip.candidate.path, refs: descendants, actions: &actions, label: "opened-Studio-Piano-slot") {
        usleep(900_000)
        return true
    }

    let generic = descendants.filter { ref in
        guard ref.candidate.enabled != false, ref.candidate.visible != false else { return false }
        let t = text(ref.candidate)
        return (t.contains("software instrument") || t == "instrument" || t.contains("instrument slot")) &&
            !t.contains("midi fx") && !t.contains("audio fx") && !t.contains("audio instruments") &&
            !t.contains("input") && !t.contains("output")
    }
    let genericLeaves = generic.filter { candidate in
        !generic.contains(where: { other in
            other.candidate.path != candidate.candidate.path &&
            other.candidate.path.hasPrefix(candidate.candidate.path + "/")
        })
    }
    if genericLeaves.count == 1,
       activateRef(genericLeaves[0], within: strip.candidate.path, refs: descendants, actions: &actions, label: "opened-instrument-slot") {
        usleep(900_000)
        return true
    }

    actions.append("instrument-slot-candidates-studio=\(studioLeaves.count)-generic=\(genericLeaves.count)")
    return false
}

private func switchPluginToControls(window: Ref, refs: [Ref], actions: inout [String]) -> Bool {
    let descendants = subtree(refs, window.candidate.path)
    let pressable = descendants.filter {
        ($0.candidate.role == kAXPopUpButtonRole || $0.candidate.role == kAXButtonRole) &&
        $0.candidate.enabled != false &&
        $0.candidate.actions.contains(kAXPressAction as String)
    }
    let scored = pressable.map { ref -> (Ref, Int) in
        let t = text(ref.candidate)
        var score = 0
        if ref.candidate.role == kAXPopUpButtonRole { score += 2 }
        if t.contains("%") { score += 4 }
        if t.contains("view") { score += 3 }
        return (ref, score)
    }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    guard let first = scored.first,
          !(scored.count > 1 && scored[1].1 == first.1),
          AX.press(first.0.element) == .success
    else { return false }

    usleep(300_000)
    guard let menuScan = scan(), pressExactMenuItem(menuScan.refs, title: "Controls") else { return false }
    actions.append("switched-Studio-Piano-to-Controls-view")
    usleep(700_000)
    return true
}

private func option(_ name: String, args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

private func writeEvidence(_ evidence: SetupEvidence, to path: String?) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(evidence) else { return }
    if let path { try? data.write(to: URL(fileURLWithPath: path)) }
}

let args = Array(CommandLine.arguments.dropFirst())
let out = option("--out", args: args)
var actions: [String] = []
var visited = 0
var stripPath: String?
var windowPath: String?
var windowTitle: String?
var semantic: [String] = []
var numeric: [String] = []

@MainActor
func finish(_ result: String, _ reason: String?, code: Int32) -> Never {
    let evidence = SetupEvidence(
        schema: "logic-coproducer-a5-auto-setup/1.1",
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        result: result,
        reason: reason,
        trackStripPath: stripPath,
        pluginWindowPath: windowPath,
        pluginWindowTitle: windowTitle,
        semanticParameterHits: semantic,
        numericParameterHits: numeric,
        actionsPerformed: actions,
        visitedNodes: visited
    )
    writeEvidence(evidence, to: out)
    if result == "PASS" {
        print("RESULT=PASS track=Studio_Grand plugin=Studio_Piano semantic_hits=\(semantic.count) numeric_hits=\(numeric.count) actions=\(actions.joined(separator: ","))")
    } else {
        print("RESULT=FAIL reason=\(reason ?? "unknown") actions=\(actions.joined(separator: ","))")
    }
    exit(code)
}

guard AXIsProcessTrusted() else { finish("FAIL", "accessibility-unavailable", code: 3) }
guard activateLogic() else { finish("FAIL", "logic-not-running", code: 4) }
usleep(250_000)

guard let (strip, initialRefs, initialVisited) = ensureTargetStrip(actions: &actions) else {
    finish("FAIL", "studio-grand-strip-not-resolved", code: 20)
}
stripPath = strip.candidate.path
visited = initialVisited
selectStripIfPossible(strip, refs: initialRefs, actions: &actions)

var current = scan()
if let found = current.flatMap({ pluginWindow(in: $0.refs) }) {
    windowPath = found.candidate.path
    windowTitle = found.candidate.title
} else {
    let freshRefs = current?.refs ?? initialRefs
    let freshStrip = targetStrip(in: freshRefs) ?? strip
    guard openInstrumentFromStrip(freshStrip, refs: freshRefs, actions: &actions) else {
        finish("FAIL", "studio-piano-instrument-slot-not-resolved", code: 21)
    }
    current = scan()
    guard let found = current.flatMap({ pluginWindow(in: $0.refs) }) else {
        finish("FAIL", "studio-piano-window-not-detected-after-open", code: 22)
    }
    windowPath = found.candidate.path
    windowTitle = found.candidate.title
}

guard var scanNow = current ?? scan(), var plugin = pluginWindow(in: scanNow.refs) else {
    finish("FAIL", "studio-piano-window-not-resolved", code: 23)
}
visited = scanNow.visited
var pluginRefs = subtree(scanNow.refs, plugin.candidate.path)
semantic = semanticHits(in: pluginRefs)
numeric = numericHits(in: pluginRefs)

if numeric.isEmpty {
    guard switchPluginToControls(window: plugin, refs: scanNow.refs, actions: &actions) else {
        finish("FAIL", "controls-view-not-automatable", code: 24)
    }
    guard let rescanned = scan(), let rescannedPlugin = pluginWindow(in: rescanned.refs) else {
        finish("FAIL", "plugin-window-lost-after-controls-switch", code: 25)
    }
    scanNow = rescanned
    plugin = rescannedPlugin
    visited = rescanned.visited
    windowPath = plugin.candidate.path
    windowTitle = plugin.candidate.title
    pluginRefs = subtree(rescanned.refs, plugin.candidate.path)
    semantic = semanticHits(in: pluginRefs)
    numeric = numericHits(in: pluginRefs)
}

guard semantic.count >= 3 else { finish("FAIL", "studio-piano-semantic-identity-too-weak", code: 26) }
guard !numeric.isEmpty else { finish("FAIL", "no-settable-semantic-parameter", code: 27) }
finish("PASS", nil, code: 0)
