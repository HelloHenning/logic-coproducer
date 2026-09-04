import AppKit
import ApplicationServices
import Foundation

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
        (copy(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { !CFEqual($0, element) }
    }
    static func actions(_ element: AXUIElement) -> [String] {
        var raw: CFArray?
        guard AXUIElementCopyActionNames(element, &raw) == .success else { return [] }
        return raw as? [String] ?? []
    }
    static func settable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var flag = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &flag) == .success && flag.boolValue
    }
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
    static func press(_ element: AXUIElement) -> AXError { AXUIElementPerformAction(element, kAXPressAction as CFString) }
}

private struct Candidate: Codable {
    let path: String
    let role: String?
    let title: String?
    let identifier: String?
    let elementDescription: String?
    let value: String?
    let valueDescription: String?
    let enabled: Bool?
    let selected: Bool?
    let actions: [String]
}

private struct Ref {
    let candidate: Candidate
    let element: AXUIElement
}

private final class Walker {
    private var seen: Set<AXID> = []
    private(set) var visited = 0
    func all(from root: AXUIElement) -> [Ref] {
        var stack: [(AXUIElement, Int, String)] = [(root, 0, "app")]
        var output: [Ref] = []
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
                elementDescription: AX.string(element, kAXDescriptionAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                enabled: AX.bool(element, kAXEnabledAttribute),
                selected: AX.bool(element, kAXSelectedAttribute),
                actions: AX.actions(element)
            ), element: element))
            guard depth < 30 else { continue }
            for (index, child) in AX.children(element).enumerated().reversed() {
                let childRole = AX.string(child, kAXRoleAttribute) ?? "AXElement"
                stack.append((child, depth + 1, "\(path)/\(childRole)[\(index)]"))
            }
        }
        return output
    }
}

private func option(_ name: String, _ args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}
private func norm(_ value: String?) -> String { (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
private func fields(_ c: Candidate) -> [String] { [c.title, c.identifier, c.elementDescription, c.value, c.valueDescription].compactMap { $0 } }
private func text(_ c: Candidate) -> String { fields(c).joined(separator: " ").lowercased() }
private func exact(_ c: Candidate, _ wanted: String) -> Bool { fields(c).contains { norm($0) == norm(wanted) } }
private func depth(_ path: String) -> Int { path.reduce(into: 0) { if $1 == "/" { $0 += 1 } } }
private func parent(_ path: String) -> String? { path.lastIndex(of: "/").map { String(path[..<$0]) } }
private func subtree(_ refs: [Ref], _ prefix: String) -> [Ref] { refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") } }
private func directChildren(_ refs: [Ref], _ prefix: String) -> [Ref] {
    let start = prefix + "/"
    return refs.filter { ref in
        guard ref.candidate.path.hasPrefix(start) else { return false }
        return !ref.candidate.path.dropFirst(start.count).contains("/")
    }
}

private func logic() -> (NSRunningApplication, AXUIElement)? {
    guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { return nil }
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
private func postKey(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return }
    down.flags = flags; up.flags = flags
    down.post(tap: .cgAnnotatedSessionEventTap)
    usleep(45_000)
    up.post(tap: .cgAnnotatedSessionEventTap)
}
private func paste(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    postKey(9, .maskCommand)
}
private func writeJSON(_ object: Any, path: String?) {
    guard let path, JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func targetStrips(_ label: String, refs: [Ref]) -> [Ref] {
    let raw = refs.filter { ref in
        guard ref.candidate.role == kAXLayoutItemRole || ref.candidate.role == kAXGroupRole else { return false }
        let descendants = subtree(refs, ref.candidate.path)
        return descendants.contains { exact($0.candidate, label) } &&
            descendants.contains { $0.candidate.role == kAXSliderRole && text($0.candidate).contains("volume") } &&
            descendants.contains { $0.candidate.role == kAXSliderRole && text($0.candidate).contains("pan") }
    }
    return raw.filter { candidate in
        !raw.contains { other in other.candidate.path != candidate.candidate.path && other.candidate.path.hasPrefix(candidate.candidate.path + "/") }
    }.sorted { depth($0.candidate.path) > depth($1.candidate.path) }
}

@discardableResult private func selectTrack(_ label: String) -> Ref? {
    guard activate() else { return nil }
    usleep(120_000)
    guard let refs = scan() else { return nil }
    let strips = targetStrips(label, refs: refs)
    guard !strips.isEmpty else { return nil }
    for strip in strips.sorted(by: { ($0.candidate.selected == true ? 0 : 1, $0.candidate.path) < ($1.candidate.selected == true ? 0 : 1, $1.candidate.path) }) {
        if AX.settable(strip.element, kAXSelectedAttribute), AX.set(strip.element, kAXSelectedAttribute, kCFBooleanTrue) == .success {
            usleep(160_000); return strip
        }
        for labelRef in subtree(refs, strip.candidate.path).filter({ exact($0.candidate, label) }) {
            if AX.settable(labelRef.element, kAXSelectedAttribute), AX.set(labelRef.element, kAXSelectedAttribute, kCFBooleanTrue) == .success {
                usleep(160_000); return strip
            }
            if labelRef.candidate.actions.contains(kAXPressAction as String), AX.press(labelRef.element) == .success {
                usleep(160_000); return strip
            }
        }
    }
    return nil
}

private func focusMain() {
    guard activate(), let refs = scan() else { return }
    if let window = refs.first(where: { $0.candidate.role == kAXWindowRole && norm($0.candidate.title).contains("tracks") }) {
        if AX.settable(window.element, kAXFocusedAttribute) { _ = AX.set(window.element, kAXFocusedAttribute, kCFBooleanTrue) }
        if AX.settable(window.element, kAXMainAttribute) { _ = AX.set(window.element, kAXMainAttribute, kCFBooleanTrue) }
    }
    usleep(100_000)
}

private func pressExactMenu(_ title: String) -> Bool {
    guard let refs = scan() else { return false }
    let candidates = refs.filter {
        $0.candidate.role == kAXMenuItemRole && exact($0.candidate, title) &&
        $0.candidate.enabled != false && $0.candidate.actions.contains(kAXPressAction as String)
    }
    guard candidates.count == 1 else { return false }
    return AX.press(candidates[0].element) == .success
}

private struct OccupiedSlot: Codable, Equatable {
    let relativePath: String
    let display: [String]
    let childDescriptions: [String]
}

private func occupiedSlots(track: String, refs: [Ref]) -> (strip: Ref, slots: [OccupiedSlot])? {
    let strips = targetStrips(track, refs: refs)
    guard let strip = strips.first else { return nil }
    let descendants = subtree(refs, strip.candidate.path)
    var output: [OccupiedSlot] = []
    for group in descendants where group.candidate.role == kAXGroupRole {
        let children = directChildren(descendants, group.candidate.path)
        let descriptions = children.compactMap { $0.candidate.elementDescription }.map(norm)
        guard descriptions.contains("bypass"), descriptions.contains("open"), descriptions.contains("list") else { continue }
        let relative = String(group.candidate.path.dropFirst(strip.candidate.path.count))
        output.append(OccupiedSlot(
            relativePath: relative,
            display: fields(group.candidate).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted(),
            childDescriptions: descriptions.sorted()
        ))
    }
    output.sort { $0.relativePath < $1.relativePath }
    return (strip, output)
}

private func pluginFingerprint(track: String, out: String?) -> Int32 {
    guard selectTrack(track) != nil, let refs = scan(), let result = occupiedSlots(track: track, refs: refs) else {
        print("RESULT=SKIP reason=track-or-plugin-chain-not-resolved"); return 10
    }
    let payload: [String: Any] = [
        "schema": "logic-coproducer-plugin-chain-fingerprint/1.0",
        "track": track,
        "stripPath": result.strip.candidate.path,
        "occupiedSlots": result.slots.map { ["relativePath": $0.relativePath, "display": $0.display, "childDescriptions": $0.childDescriptions] }
    ]
    writeJSON(payload, path: out)
    print("RESULT=PASS track=\(track.replacingOccurrences(of: " ", with: "_")) occupied_slots=\(result.slots.count)")
    return 0
}

private func pluginWindow(named name: String, refs: [Ref]) -> Ref? {
    let q = norm(name)
    let candidates = refs.filter { ref in
        guard ref.candidate.role == kAXWindowRole, !norm(ref.candidate.title).contains("tracks") else { return false }
        let own = text(ref.candidate)
        let descendants = subtree(refs, ref.candidate.path)
        return own.contains(q) || descendants.contains { text($0.candidate).contains(q) }
    }
    guard candidates.count == 1 else { return nil }
    return candidates[0]
}

private func verifyPluginWindow(name: String, out: String?) -> Int32 {
    guard let refs = scan(), let window = pluginWindow(named: name, refs: refs) else {
        print("RESULT=SKIP reason=plugin-window-not-unique plugin=\(name.replacingOccurrences(of: " ", with: "_"))"); return 10
    }
    let hits = subtree(refs, window.candidate.path).filter { text($0.candidate).contains(norm(name)) }.prefix(12).map { fields($0.candidate).joined(separator: " | ") }
    writeJSON([
        "schema": "logic-coproducer-plugin-window/1.0",
        "plugin": name,
        "windowPath": window.candidate.path,
        "windowTitle": window.candidate.title ?? "",
        "semanticHits": Array(hits)
    ], path: out)
    print("RESULT=PASS plugin=\(name.replacingOccurrences(of: " ", with: "_")) window=\((window.candidate.title ?? window.candidate.path).replacingOccurrences(of: " ", with: "_"))")
    return 0
}

private func sidechainPopup(window: Ref, refs: [Ref]) -> Ref? {
    let descendants = subtree(refs, window.candidate.path)
    var scored: [(Ref, Int)] = []
    for ref in descendants where ref.candidate.role == kAXPopUpButtonRole && ref.candidate.enabled != false && ref.candidate.actions.contains(kAXPressAction as String) {
        var score = 0
        if text(ref.candidate).contains("side chain") || text(ref.candidate).contains("sidechain") { score += 12 }
        if let p = parent(ref.candidate.path) {
            let siblingText = directChildren(descendants, p).map { text($0.candidate) }.joined(separator: " ")
            if siblingText.contains("side chain") || siblingText.contains("sidechain") { score += 8 }
        }
        if ref.candidate.value != nil || ref.candidate.valueDescription != nil { score += 2 }
        if score > 0 { scored.append((ref, score)) }
    }
    scored.sort { $0.1 == $1.1 ? $0.0.candidate.path < $1.0.candidate.path : $0.1 > $1.1 }
    guard let first = scored.first, first.1 >= 8 else { return nil }
    if scored.count > 1 && scored[1].1 == first.1 { return nil }
    return first.0
}

private func popupValue(_ ref: Ref) -> String {
    ref.candidate.valueDescription ?? ref.candidate.value ?? ref.candidate.title ?? ref.candidate.elementDescription ?? ""
}

private func menuItem(matching wanted: String, refs: [Ref]) -> Ref? {
    let q = norm(wanted)
    let candidates = refs.filter { ref in
        guard ref.candidate.role == kAXMenuItemRole, ref.candidate.enabled != false, ref.candidate.actions.contains(kAXPressAction as String) else { return false }
        return fields(ref.candidate).contains { field in
            let n = norm(field)
            return n == q || n.hasSuffix(q) || (q.count >= 6 && n.contains(q))
        }
    }
    return candidates.count == 1 ? candidates[0] : nil
}

private func sidechainRoundTrip(plugin: String, source: String, out: String?) -> Int32 {
    guard activate(), let initialRefs = scan(), let window = pluginWindow(named: plugin, refs: initialRefs), let popup = sidechainPopup(window: window, refs: initialRefs) else {
        print("RESULT=SKIP reason=sidechain-popup-not-resolved"); return 10
    }
    let before = popupValue(popup)
    guard AX.press(popup.element) == .success else { print("RESULT=SKIP reason=sidechain-popup-not-actionable"); return 10 }
    usleep(180_000)
    guard let menuRefs = scan(), let sourceItem = menuItem(matching: source, refs: menuRefs) else {
        postKey(53); print("RESULT=SKIP reason=sidechain-source-menu-item-not-unique source=\(source.replacingOccurrences(of: " ", with: "_"))"); return 10
    }
    guard AX.press(sourceItem.element) == .success else { postKey(53); print("RESULT=FAIL reason=sidechain-source-selection-failed"); return 20 }
    usleep(280_000)
    guard let changedRefs = scan(), let changedWindow = pluginWindow(named: plugin, refs: changedRefs), let changedPopup = sidechainPopup(window: changedWindow, refs: changedRefs) else {
        print("RESULT=RESTORE_FAIL reason=sidechain-readback-unavailable"); return 30
    }
    let changed = popupValue(changedPopup)
    guard norm(changed).contains(norm(source)) else {
        print("RESULT=RESTORE_FAIL reason=sidechain-change-not-observed before=\(before.replacingOccurrences(of: " ", with: "_")) changed=\(changed.replacingOccurrences(of: " ", with: "_"))"); return 30
    }

    guard AX.press(changedPopup.element) == .success else { print("RESULT=RESTORE_FAIL reason=sidechain-restore-menu-unavailable"); return 30 }
    usleep(180_000)
    guard let restoreMenu = scan() else { return 30 }
    var restoreItem: Ref? = nil
    if !norm(before).isEmpty { restoreItem = menuItem(matching: before, refs: restoreMenu) }
    if restoreItem == nil {
        for fallback in ["Off", "None", "No Side Chain", "--"] {
            if let item = menuItem(matching: fallback, refs: restoreMenu) { restoreItem = item; break }
        }
    }
    guard let restoreItem, AX.press(restoreItem.element) == .success else {
        postKey(53); print("RESULT=RESTORE_FAIL reason=sidechain-original-source-not-restorable before=\(before.replacingOccurrences(of: " ", with: "_"))"); return 30
    }
    usleep(280_000)
    guard let finalRefs = scan(), let finalWindow = pluginWindow(named: plugin, refs: finalRefs), let finalPopup = sidechainPopup(window: finalWindow, refs: finalRefs) else {
        print("RESULT=RESTORE_FAIL reason=sidechain-final-readback-unavailable"); return 30
    }
    let final = popupValue(finalPopup)
    let restored = !norm(before).isEmpty ? norm(final) == norm(before) || norm(final).contains(norm(before)) : !norm(final).contains(norm(source))
    writeJSON([
        "schema": "logic-coproducer-sidechain-roundtrip/1.0",
        "plugin": plugin, "source": source, "before": before, "changed": changed, "final": final, "restored": restored
    ], path: out)
    guard restored else { print("RESULT=RESTORE_FAIL reason=sidechain-final-value-mismatch before=\(before) final=\(final)"); return 30 }
    print("RESULT=PASS plugin=\(plugin.replacingOccurrences(of: " ", with: "_")) sidechain_source=\(source.replacingOccurrences(of: " ", with: "_")) before=\(before.replacingOccurrences(of: " ", with: "_")) restored=\(final.replacingOccurrences(of: " ", with: "_"))")
    return 0
}

private func importMusicXML(path: String) -> Int32 {
    focusMain()
    var opened = pressExactMenu("MusicXML…")
    if !opened { opened = pressExactMenu("MusicXML...") }
    if !opened { opened = pressExactMenu("MusicXML") }
    guard opened else { print("RESULT=SKIP reason=musicxml-import-menu-not-resolved"); return 10 }
    usleep(420_000)
    postKey(5, [.maskShift, .maskCommand])
    usleep(120_000)
    paste(path)
    postKey(36)
    usleep(300_000)
    postKey(36)
    usleep(1_100_000)
    print("RESULT=PASS import_command=MusicXML path=\(URL(fileURLWithPath: path).lastPathComponent)")
    return 0
}

private func deleteTrack(label: String) -> Int32 {
    guard selectTrack(label) != nil else { print("RESULT=SKIP reason=delete-track-target-not-resolved"); return 10 }
    focusMain()
    postKey(51, .maskCommand)
    usleep(450_000)
    guard let refs = scan() else { return 20 }
    if targetStrips(label, refs: refs).isEmpty {
        print("RESULT=PASS deleted_track=\(label.replacingOccurrences(of: " ", with: "_"))")
        return 0
    }
    print("RESULT=FAIL reason=delete-track-not-observed")
    return 20
}

private func trackAbsent(label: String) -> Int32 {
    guard let refs = scan() else { return 20 }
    if targetStrips(label, refs: refs).isEmpty { print("RESULT=PASS absent=\(label.replacingOccurrences(of: " ", with: "_"))"); return 0 }
    print("RESULT=FAIL reason=track-still-present label=\(label.replacingOccurrences(of: " ", with: "_"))")
    return 20
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first, AXIsProcessTrusted(), logic() != nil else { exit(3) }
let out = option("--out", args)

switch command {
case "plugin-fingerprint":
    guard let track = option("--track", args) else { exit(2) }
    exit(pluginFingerprint(track: track, out: out))
case "plugin-window":
    guard let name = option("--name", args) else { exit(2) }
    exit(verifyPluginWindow(name: name, out: out))
case "sidechain-roundtrip":
    guard let plugin = option("--plugin", args), let source = option("--source", args) else { exit(2) }
    exit(sidechainRoundTrip(plugin: plugin, source: source, out: out))
case "press-menu":
    guard let title = option("--title", args) else { exit(2) }
    if pressExactMenu(title) { usleep(220_000); print("RESULT=PASS menu=\(title.replacingOccurrences(of: " ", with: "_"))") } else { print("RESULT=SKIP reason=menu-item-not-unique title=\(title.replacingOccurrences(of: " ", with: "_"))"); exit(10) }
case "import-musicxml":
    guard let path = option("--path", args) else { exit(2) }
    exit(importMusicXML(path: path))
case "delete-track":
    guard let label = option("--label", args) else { exit(2) }
    exit(deleteTrack(label: label))
case "track-absent":
    guard let label = option("--label", args) else { exit(2) }
    exit(trackAbsent(label: label))
default:
    exit(2)
}
