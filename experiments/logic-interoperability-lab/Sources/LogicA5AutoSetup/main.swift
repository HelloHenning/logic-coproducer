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

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

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

private struct Candidate: Codable {
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

private struct Ref {
    let candidate: Candidate
    let element: AXUIElement
}

private final class Walker {
    private let maxDepth: Int
    private let maxNodes: Int
    private(set) var visited = 0
    private var seen: Set<AXIdentity> = []

    init(maxDepth: Int = 30, maxNodes: Int = 100_000) {
        self.maxDepth = maxDepth
        self.maxNodes = maxNodes
    }

    func all(from root: AXUIElement) -> [Ref] {
        var stack: [(AXUIElement, Int, String)] = [(root, 0, "app")]
        var output: [Ref] = []
        while let (element, depth, path) = stack.popLast(), visited < maxNodes {
            let identity = AXIdentity(element: element)
            guard seen.insert(identity).inserted else { continue }
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

private struct SlotMatch {
    let strip: Ref
    let slot: Ref
    let openControl: Ref?
    let score: Int
    let evidence: [String]
}

private struct SetupEvidence: Codable {
    let schema: String
    let generatedAt: String
    let result: String
    let reason: String?
    let channelStripPaths: [String]
    let selectedChannelStripPath: String?
    let instrumentSlotPath: String?
    let instrumentSlotDisplayName: String?
    let instrumentSlotEvidence: [String]
    let pluginWindowPath: String?
    let pluginWindowTitle: String?
    let semanticParameterHits: [String]
    let numericParameterHits: [String]
    let actionsPerformed: [String]
    let visitedNodes: Int
}

private let targetTrack = "Studio Grand"
private let slotDisplayHint = "Piano" // Fixture display/short-name hint only; never canonical plug-in identity.
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

private func exactDescription(_ candidate: Candidate, _ wanted: String) -> Bool {
    norm(candidate.elementDescription) == norm(wanted)
}

private func subtree(_ refs: [Ref], _ prefix: String) -> [Ref] {
    refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") }
}

private func directChildren(_ refs: [Ref], _ parent: String) -> [Ref] {
    let prefix = parent + "/"
    return refs.filter { ref in
        guard ref.candidate.path.hasPrefix(prefix) else { return false }
        let remainder = ref.candidate.path.dropFirst(prefix.count)
        return !remainder.contains("/")
    }
}

private func depth(_ path: String) -> Int {
    path.reduce(into: 0) { count, ch in if ch == "/" { count += 1 } }
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

private func targetStrips(in refs: [Ref]) -> [Ref] {
    let raw = refs.filter { ref in
        guard ref.candidate.role == kAXLayoutItemRole || ref.candidate.role == kAXGroupRole else { return false }
        let descendants = subtree(refs, ref.candidate.path)
        let hasExactTrack = descendants.contains { exactField($0.candidate, targetTrack) }
        let hasVolume = descendants.contains {
            $0.candidate.role == kAXSliderRole && text($0.candidate).contains("volume")
        }
        let hasPan = descendants.contains {
            $0.candidate.role == kAXSliderRole && text($0.candidate).contains("pan")
        }
        return hasExactTrack && hasVolume && hasPan
    }

    // Keep the smallest/deepest matching containers. This permits both Mixer and Inspector
    // representations without treating a common ancestor as a second channel strip.
    let minimal = raw.filter { candidate in
        !raw.contains(where: { other in
            other.candidate.path != candidate.candidate.path &&
            other.candidate.path.hasPrefix(candidate.candidate.path + "/")
        })
    }
    return minimal.sorted {
        if depth($0.candidate.path) != depth($1.candidate.path) {
            return depth($0.candidate.path) > depth($1.candidate.path)
        }
        return $0.candidate.path < $1.candidate.path
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

private func pressControlBarToggleIfOff(_ refs: [Ref], title: String) -> Bool {
    let candidates = refs.filter {
        $0.candidate.role == kAXCheckBoxRole &&
        exactField($0.candidate, title) &&
        norm($0.candidate.value) == "0" &&
        $0.candidate.enabled != false &&
        $0.candidate.actions.contains(kAXPressAction as String)
    }
    guard candidates.count == 1 else { return false }
    return AX.press(candidates[0].element) == .success
}

private func ensureTargetStrips(actions: inout [String]) -> (strips: [Ref], refs: [Ref], visited: Int)? {
    guard var current = scan() else { return nil }
    var strips = targetStrips(in: current.refs)
    if !strips.isEmpty { return (strips, current.refs, current.visited) }

    // Prefer semantic UI controls/menu commands over customizable key assignments.
    if pressControlBarToggleIfOff(current.refs, title: "Inspector") || pressExactMenuItem(current.refs, title: "Show Inspector") {
        actions.append("opened-inspector-semantically")
        usleep(500_000)
        if let rescanned = scan() {
            current = rescanned
            strips = targetStrips(in: rescanned.refs)
            if !strips.isEmpty { return (strips, rescanned.refs, rescanned.visited) }
        }
    }

    if pressControlBarToggleIfOff(current.refs, title: "Mixer") || pressExactMenuItem(current.refs, title: "Show Mixer") {
        actions.append("opened-mixer-semantically")
        usleep(600_000)
        if let rescanned = scan() {
            current = rescanned
            strips = targetStrips(in: rescanned.refs)
            if !strips.isEmpty { return (strips, rescanned.refs, rescanned.visited) }
        }
    }

    return nil
}

private func clickCenter(_ ref: Ref) -> Bool {
    // Do not use AXEnabled as identity or geometry eligibility. Stored Logic AX evidence
    // shows valid occupied plug-in slot groups reported disabled when another area has focus.
    guard ref.candidate.visible != false,
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

private func postEscape() {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) else { return }
    down.post(tap: .cgAnnotatedSessionEventTap)
    usleep(40_000)
    up.post(tap: .cgAnnotatedSessionEventTap)
}

private func slotMatches(strips: [Ref], refs: [Ref]) -> [SlotMatch] {
    var matches: [SlotMatch] = []
    for strip in strips {
        let descendants = subtree(refs, strip.candidate.path)
        let groups = descendants.filter { $0.candidate.role == kAXGroupRole }
        for group in groups {
            let children = directChildren(descendants, group.candidate.path)
            let bypass = children.first { exactDescription($0.candidate, "bypass") }
            let open = children.first { exactDescription($0.candidate, "open") }
            let list = children.first { exactDescription($0.candidate, "list") }
            guard bypass != nil, open != nil, list != nil else { continue }

            var score = 0
            var evidence = ["occupied-slot-signature:bypass+open+list"]

            let parentPath: String
            if let slash = group.candidate.path.lastIndex(of: "/") {
                parentPath = String(group.candidate.path[..<slash])
            } else {
                parentPath = ""
            }
            let siblings = directChildren(descendants, parentPath)
            if let slotIndex = siblings.firstIndex(where: { $0.candidate.path == group.candidate.path }),
               let audioIndex = siblings.firstIndex(where: { exactDescription($0.candidate, "audio plug-in") }),
               let midiIndex = siblings.firstIndex(where: { exactDescription($0.candidate, "MIDI plug-in") }),
               min(audioIndex, midiIndex) < slotIndex,
               slotIndex < max(audioIndex, midiIndex) {
                score += 100
                evidence.append("between-audio-plug-in-and-MIDI-plug-in-markers")
            }

            if exactField(group.candidate, slotDisplayHint) {
                score += 25
                evidence.append("fixture-display-hint:Piano")
            }

            let stripHasAudioMarker = descendants.contains { exactDescription($0.candidate, "audio plug-in") }
            let stripHasMIDIMarker = descendants.contains { exactDescription($0.candidate, "MIDI plug-in") }
            if stripHasAudioMarker && stripHasMIDIMarker {
                score += 10
                evidence.append("instrument-strip-component-markers-present")
            }

            // Structural identity is mandatory. The fixture short name is only a hint.
            if score >= 35 {
                if open?.candidate.enabled != false { score += 5 }
                matches.append(SlotMatch(strip: strip, slot: group, openControl: open, score: score, evidence: evidence))
            }
        }
    }

    return matches.sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        return $0.slot.candidate.path < $1.slot.candidate.path
    }
}

private func bestSlot(strips: [Ref], refs: [Ref]) -> SlotMatch? {
    slotMatches(strips: strips, refs: refs).first
}

private func focusStripIfPossible(_ strip: Ref, refs: [Ref], actions: inout [String]) {
    if AX.isSettable(strip.element, kAXSelectedAttribute), AX.select(strip.element) == .success {
        actions.append("focused-Studio-Grand-channel-strip-via-AXSelected")
        usleep(250_000)
        return
    }

    let labels = subtree(refs, strip.candidate.path).filter { exactField($0.candidate, targetTrack) }
    for label in labels {
        if AX.isSettable(label.element, kAXSelectedAttribute), AX.select(label.element) == .success {
            actions.append("focused-Studio-Grand-label-via-AXSelected")
            usleep(250_000)
            return
        }
        if label.candidate.actions.contains(kAXPressAction as String), AX.press(label.element) == .success {
            actions.append("focused-Studio-Grand-label-via-AXPress")
            usleep(250_000)
            return
        }
    }
}

private func openInstrumentSlot(_ initial: SlotMatch, actions: inout [String]) -> Bool {
    if let open = initial.openControl,
       open.candidate.actions.contains(kAXPressAction as String),
       AX.press(open.element) == .success {
        actions.append("opened-instrument-slot-via-semantic-open-control")
        usleep(900_000)
        return true
    }

    // The current UI may expose the right slot structurally while reporting its controls
    // disabled. Focus the known target strip, rescan, and retry before any coordinate action.
    if let rescanned = scan() {
        let strips = targetStrips(in: rescanned.refs)
        if let matchingStrip = strips.first(where: { $0.candidate.path == initial.strip.candidate.path }) ?? strips.first {
            focusStripIfPossible(matchingStrip, refs: rescanned.refs, actions: &actions)
        }
    }

    if let rescanned = scan(),
       let refreshed = bestSlot(strips: targetStrips(in: rescanned.refs), refs: rescanned.refs) {
        if let open = refreshed.openControl,
           open.candidate.actions.contains(kAXPressAction as String),
           AX.press(open.element) == .success {
            actions.append("opened-instrument-slot-via-semantic-open-control-after-focus")
            usleep(900_000)
            return true
        }
        if clickCenter(refreshed.slot) {
            actions.append("opened-instrument-slot-via-documented-center-click")
            usleep(900_000)
            return true
        }
    }

    if clickCenter(initial.slot) {
        actions.append("opened-instrument-slot-via-documented-center-click-original-ref")
        usleep(900_000)
        return true
    }
    return false
}

private func pluginWindow(in refs: [Ref]) -> Ref? {
    let windows = refs.filter { $0.candidate.role == kAXWindowRole }
    let scored: [(Ref, Int)] = windows.compactMap { window in
        let descendants = subtree(refs, window.candidate.path)
        let semanticCount = semanticHits(in: descendants).count
        let canonical = descendants.contains { text($0.candidate).contains("studio piano") } ||
            text(window.candidate).contains("studio piano")
        guard canonical || semanticCount >= 3 else { return nil }
        var score = semanticCount * 2
        if canonical { score += 12 }
        if exactField(window.candidate, targetTrack) { score += 2 }
        return (window, score)
    }.sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        return $0.0.candidate.path < $1.0.candidate.path
    }
    guard let first = scored.first else { return nil }
    if scored.count > 1 && scored[1].1 == first.1 { return nil }
    return first.0
}

private func isPercentLike(_ value: String?) -> Bool {
    let s = norm(value)
    guard s.hasSuffix("%") else { return false }
    return Double(s.dropLast()) != nil
}

private func switchPluginToControls(window: Ref, refs: [Ref], actions: inout [String]) -> Bool {
    let descendants = subtree(refs, window.candidate.path)
    let candidates = descendants.compactMap { ref -> (Ref, Int)? in
        guard (ref.candidate.role == kAXPopUpButtonRole || ref.candidate.role == kAXButtonRole),
              ref.candidate.enabled != false,
              ref.candidate.visible != false,
              ref.candidate.actions.contains(kAXPressAction as String)
        else { return nil }
        let t = text(ref.candidate)
        var score = 0
        if t.contains("view") { score += 6 }
        if fields(ref.candidate).contains(where: { isPercentLike($0) }) { score += 4 }
        guard score > 0 else { return nil }
        if ref.candidate.role == kAXPopUpButtonRole { score += 2 }
        return (ref, score)
    }.sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        return $0.0.candidate.path < $1.0.candidate.path
    }

    for (control, _) in candidates.prefix(4) {
        guard AX.press(control.element) == .success else { continue }
        usleep(250_000)
        if let menuScan = scan() {
            let controlsItems = menuScan.refs.filter {
                $0.candidate.role == kAXMenuItemRole &&
                exactField($0.candidate, "Controls") &&
                $0.candidate.visible != false &&
                $0.candidate.enabled != false &&
                $0.candidate.actions.contains(kAXPressAction as String)
            }
            if controlsItems.count == 1, AX.press(controlsItems[0].element) == .success {
                actions.append("switched-Studio-Piano-to-Controls-via-verified-View-menu")
                usleep(700_000)
                return true
            }
        }
        postEscape()
        usleep(120_000)
    }
    return false
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
var stripPaths: [String] = []
var selectedStripPath: String?
var slotPath: String?
var slotDisplayName: String?
var slotEvidence: [String] = []
var windowPath: String?
var windowTitle: String?
var semantic: [String] = []
var numeric: [String] = []

@MainActor
func finish(_ result: String, _ reason: String?, code: Int32) -> Never {
    let evidence = SetupEvidence(
        schema: "logic-coproducer-a5-auto-setup/1.2",
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        result: result,
        reason: reason,
        channelStripPaths: stripPaths,
        selectedChannelStripPath: selectedStripPath,
        instrumentSlotPath: slotPath,
        instrumentSlotDisplayName: slotDisplayName,
        instrumentSlotEvidence: slotEvidence,
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

guard let prepared = ensureTargetStrips(actions: &actions) else {
    finish("FAIL", "studio-grand-channel-strip-not-resolved", code: 20)
}
var currentRefs = prepared.refs
visited = prepared.visited
stripPaths = prepared.strips.map { $0.candidate.path }

guard var slot = bestSlot(strips: prepared.strips, refs: currentRefs) else {
    actions.append("structural-instrument-slot-candidates=0")
    finish("FAIL", "studio-piano-instrument-slot-not-resolved-structurally", code: 21)
}
selectedStripPath = slot.strip.candidate.path
slotPath = slot.slot.candidate.path
slotDisplayName = slot.slot.candidate.elementDescription
slotEvidence = slot.evidence

actions.append("resolved-instrument-slot-structurally-score=\(slot.score)")

var current = scan()
if let found = current.flatMap({ pluginWindow(in: $0.refs) }) {
    windowPath = found.candidate.path
    windowTitle = found.candidate.title
    actions.append("Studio-Piano-window-already-open")
} else {
    guard openInstrumentSlot(slot, actions: &actions) else {
        finish("FAIL", "studio-piano-instrument-slot-open-failed", code: 22)
    }
    current = scan()
    if let rescanned = current {
        visited = rescanned.visited
        currentRefs = rescanned.refs
        let refreshedStrips = targetStrips(in: rescanned.refs)
        stripPaths = refreshedStrips.map { $0.candidate.path }
        if let refreshedSlot = bestSlot(strips: refreshedStrips, refs: rescanned.refs) {
            slot = refreshedSlot
            selectedStripPath = refreshedSlot.strip.candidate.path
            slotPath = refreshedSlot.slot.candidate.path
            slotDisplayName = refreshedSlot.slot.candidate.elementDescription
            slotEvidence = refreshedSlot.evidence
        }
    }
    guard let found = current.flatMap({ pluginWindow(in: $0.refs) }) else {
        finish("FAIL", "studio-piano-window-not-detected-after-open", code: 23)
    }
    windowPath = found.candidate.path
    windowTitle = found.candidate.title
}

guard var scanNow = current ?? scan(), var plugin = pluginWindow(in: scanNow.refs) else {
    finish("FAIL", "studio-piano-window-not-resolved", code: 24)
}
visited = scanNow.visited
var pluginRefs = subtree(scanNow.refs, plugin.candidate.path)
semantic = semanticHits(in: pluginRefs)
numeric = numericHits(in: pluginRefs)

if numeric.isEmpty {
    guard switchPluginToControls(window: plugin, refs: scanNow.refs, actions: &actions) else {
        finish("FAIL", "controls-view-not-automatable", code: 25)
    }
    guard let rescanned = scan(), let rescannedPlugin = pluginWindow(in: rescanned.refs) else {
        finish("FAIL", "plugin-window-lost-after-controls-switch", code: 26)
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

guard semantic.count >= 3 else { finish("FAIL", "studio-piano-semantic-identity-too-weak", code: 27) }
guard !numeric.isEmpty else { finish("FAIL", "no-settable-semantic-parameter", code: 28) }
finish("PASS", nil, code: 0)
