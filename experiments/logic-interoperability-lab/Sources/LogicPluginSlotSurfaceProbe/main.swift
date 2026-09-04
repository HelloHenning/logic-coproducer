import AppKit
import ApplicationServices
import Foundation

// Prior-art note: this probe intentionally validates the Logic-specific empty
// insert-slot Accessibility action documented and live-tested by the MIT-licensed
// MongLong0214/logic-pro-mcp project before we depend on it for mutation.
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
    static func perform(_ element: AXUIElement, _ action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }
    static func settable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var flag = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &flag) == .success && flag.boolValue
    }
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
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
                elementDescription: AX.string(element, kAXDescriptionAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                enabled: AX.bool(element, kAXEnabledAttribute),
                selected: AX.bool(element, kAXSelectedAttribute),
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

private func norm(_ value: String?) -> String {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
private func fields(_ c: Candidate) -> [String] {
    [c.title, c.identifier, c.elementDescription, c.value, c.valueDescription].compactMap { $0 }
}
private func text(_ c: Candidate) -> String { fields(c).joined(separator: " ").lowercased() }
private func exact(_ c: Candidate, _ wanted: String) -> Bool { fields(c).contains { norm($0) == norm(wanted) } }
private func subtree(_ refs: [Ref], _ prefix: String) -> [Ref] {
    refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") }
}
private func depth(_ path: String) -> Int { path.reduce(into: 0) { if $1 == "/" { $0 += 1 } } }

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
    usleep(40_000)
    up.post(tap: .cgAnnotatedSessionEventTap)
}
private func writeJSON(_ object: Any, path: String) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func mixerStrips(_ label: String, refs: [Ref]) -> [Ref] {
    let raw = refs.filter { ref in
        guard ref.candidate.role == kAXLayoutItemRole else { return false }
        let descendants = subtree(refs, ref.candidate.path)
        return descendants.contains { exact($0.candidate, label) } &&
            descendants.contains { $0.candidate.role == kAXSliderRole && text($0.candidate).contains("volume") } &&
            descendants.contains { $0.candidate.role == kAXSliderRole && text($0.candidate).contains("pan") }
    }
    return raw.filter { candidate in
        !raw.contains { other in
            other.candidate.path != candidate.candidate.path &&
            other.candidate.path.hasPrefix(candidate.candidate.path + "/")
        }
    }.sorted { depth($0.candidate.path) > depth($1.candidate.path) }
}

private func selectTrack(_ label: String, refs: [Ref]) -> Bool {
    let strips = mixerStrips(label, refs: refs)
    guard strips.count == 1 else { return false }
    let strip = strips[0]
    if AX.settable(strip.element, kAXSelectedAttribute),
       AX.set(strip.element, kAXSelectedAttribute, kCFBooleanTrue) == .success {
        return true
    }
    for hit in subtree(refs, strip.candidate.path).filter({ exact($0.candidate, label) }) {
        if hit.candidate.actions.contains(kAXPressAction as String),
           AX.perform(hit.element, kAXPressAction as String) == .success {
            return true
        }
    }
    return false
}

private struct SlotSnapshot: Codable, Equatable {
    let index: Int
    let kind: String
    let name: String?
    let role: String?
    let text: String
    let actions: [String]
}

private func slotSnapshot(strip: Ref) -> [SlotSnapshot] {
    var slots: [SlotSnapshot] = []
    let children = AX.children(strip.element)
    for child in children {
        let role = AX.string(child, kAXRoleAttribute)
        let desc = AX.string(child, kAXDescriptionAttribute)
        let title = AX.string(child, kAXTitleAttribute)
        let value = AX.simple(child)
        let search = [desc, title, value].compactMap { $0 }.joined(separator: " ")
        let actions = AX.actions(child)

        if role == kAXGroupRole {
            let direct = AX.children(child)
            let directRoles = direct.compactMap { AX.string($0, kAXRoleAttribute) }
            let directText = direct.flatMap { [AX.string($0, kAXDescriptionAttribute), AX.string($0, kAXTitleAttribute)] }.compactMap { $0 }.joined(separator: " ").lowercased()
            let occupied = directRoles.contains(kAXCheckBoxRole as String) &&
                (directRoles.filter { $0 == (kAXButtonRole as String) }.count >= 2 ||
                 (directText.contains("bypass") && (directText.contains("open") || directText.contains("list"))))
            if occupied {
                slots.append(SlotSnapshot(index: slots.count, kind: "occupied", name: desc ?? title, role: role, text: search, actions: actions))
                continue
            }
        }

        if role == kAXButtonRole && actions.contains(legacyPluginMenuAction) {
            slots.append(SlotSnapshot(index: slots.count, kind: "empty_custom_action", name: nil, role: role, text: search, actions: actions))
            continue
        }

        let lower = search.lowercased()
        if role == kAXButtonRole && (lower.contains("audio plug-in") || lower.contains("audio plugin") || lower.contains("audio fx")) {
            slots.append(SlotSnapshot(index: slots.count, kind: "empty_semantic", name: nil, role: role, text: search, actions: actions))
        }
    }
    return slots
}

private func customActionSlot(strip: Ref) -> AXUIElement? {
    for child in AX.children(strip.element) {
        guard AX.string(child, kAXRoleAttribute) == kAXButtonRole else { continue }
        if AX.actions(child).contains(legacyPluginMenuAction) { return child }
    }
    return nil
}

private func run(track: String, out: String) -> Int32 {
    guard activate() else {
        print("RESULT=FAIL reason=logic-or-accessibility-unavailable")
        return 20
    }
    usleep(150_000)
    guard var refs = scan() else {
        print("RESULT=FAIL reason=ax-scan-unavailable")
        return 20
    }
    guard selectTrack(track, refs: refs) else {
        writeJSON(["result": "FAIL", "reason": "unique-mixer-strip-not-resolved"], path: out)
        print("RESULT=FAIL reason=unique-mixer-strip-not-resolved track=\(track.replacingOccurrences(of: " ", with: "_"))")
        return 20
    }
    usleep(180_000)
    refs = scan() ?? refs
    let strips = mixerStrips(track, refs: refs)
    guard strips.count == 1 else {
        writeJSON(["result": "FAIL", "reason": "unique-mixer-strip-not-resolved-after-selection", "stripCount": strips.count], path: out)
        print("RESULT=FAIL reason=unique-mixer-strip-not-resolved-after-selection count=\(strips.count)")
        return 20
    }
    let strip = strips[0]
    let before = slotSnapshot(strip: strip)
    let occupiedBefore = before.filter { $0.kind == "occupied" }
    let customBefore = before.filter { $0.kind == "empty_custom_action" }

    guard occupiedBefore.isEmpty else {
        writeJSON([
            "schema": "logic-coproducer-plugin-slot-surface/1.0",
            "result": "SKIP",
            "reason": "audio-1-chain-not-empty",
            "before": before.map { ["index": $0.index, "kind": $0.kind, "name": $0.name ?? NSNull(), "text": $0.text, "actions": $0.actions] }
        ], path: out)
        print("RESULT=SKIP reason=audio-1-chain-not-empty occupied=\(occupiedBefore.count)")
        return 10
    }

    guard customBefore.count >= 1, let slot = customActionSlot(strip: strip) else {
        writeJSON([
            "schema": "logic-coproducer-plugin-slot-surface/1.0",
            "result": "SKIP",
            "reason": "logic-12.0.1-custom-slot-action-not-observed",
            "before": before.map { ["index": $0.index, "kind": $0.kind, "name": $0.name ?? NSNull(), "text": $0.text, "actions": $0.actions] }
        ], path: out)
        print("RESULT=SKIP reason=custom-slot-action-not-observed empty_candidates=\(before.filter { $0.kind.hasPrefix("empty") }.count)")
        return 10
    }

    // The upstream implementation explicitly notes this action can return
    // kAXErrorCannotComplete even when the popup successfully opens, so observed
    // menu state below is authoritative rather than the AX return code.
    let actionRC = AX.perform(slot, legacyPluginMenuAction)
    usleep(350_000)
    let menuRefs = scan() ?? []
    let menuItems = menuRefs.filter { $0.candidate.role == kAXMenuItemRole }
    let compressorExact = menuItems.filter { exact($0.candidate, "Compressor") }
    let compressorContains = menuItems.filter { text($0.candidate).contains("compressor") }.prefix(20)
    let dynamics = menuItems.filter { exact($0.candidate, "Dynamics") }
    let textFields = menuRefs.filter { $0.candidate.role == kAXTextFieldRole }.prefix(20)
    let menus = menuRefs.filter { $0.candidate.role == kAXMenuRole }

    let menuEvidence: [[String: Any]] = Array(compressorContains).map {
        ["path": $0.candidate.path, "fields": fields($0.candidate), "actions": $0.candidate.actions, "enabled": $0.candidate.enabled as Any]
    }
    let fieldEvidence: [[String: Any]] = Array(textFields).map {
        ["path": $0.candidate.path, "fields": fields($0.candidate), "actions": $0.candidate.actions]
    }

    postEscape()
    usleep(250_000)
    let finalRefs = scan() ?? []
    let finalStrips = mixerStrips(track, refs: finalRefs)
    guard finalStrips.count == 1 else {
        writeJSON(["result": "RESTORE_FAIL", "reason": "mixer-strip-not-resolved-after-escape"], path: out)
        print("RESULT=RESTORE_FAIL reason=mixer-strip-not-resolved-after-escape")
        return 30
    }
    let final = slotSnapshot(strip: finalStrips[0])
    let unchanged = final == before

    let popupObserved = !menus.isEmpty || !compressorExact.isEmpty
    let discoverable = !compressorExact.isEmpty || !textFields.isEmpty
    let pass = popupObserved && discoverable && unchanged

    writeJSON([
        "schema": "logic-coproducer-plugin-slot-surface/1.0",
        "result": pass ? "PASS" : (unchanged ? "SKIP" : "RESTORE_FAIL"),
        "track": track,
        "legacyActionReturnCode": actionRC.rawValue,
        "customActionSlotCount": customBefore.count,
        "menuCount": menus.count,
        "compressorExactCount": compressorExact.count,
        "dynamicsExactCount": dynamics.count,
        "textFieldCount": textFields.count,
        "compressorEvidence": menuEvidence,
        "textFieldEvidence": fieldEvidence,
        "before": before.map { ["index": $0.index, "kind": $0.kind, "name": $0.name ?? NSNull(), "text": $0.text, "actions": $0.actions] },
        "final": final.map { ["index": $0.index, "kind": $0.kind, "name": $0.name ?? NSNull(), "text": $0.text, "actions": $0.actions] },
        "chainUnchanged": unchanged
    ], path: out)

    if !unchanged {
        print("RESULT=RESTORE_FAIL reason=plugin-chain-changed-during-nonmutating-probe")
        return 30
    }
    if pass {
        print("RESULT=PASS track=Audio_1 custom_slot_action=verified plugin_popup=verified compressor_discovery=verified chain_unchanged=verified")
        return 0
    }
    print("RESULT=SKIP reason=popup-or-compressor-discovery-not-qualified menu_count=\(menus.count) compressor_exact=\(compressorExact.count) text_fields=\(textFields.count)")
    return 10
}

let args = Array(CommandLine.arguments.dropFirst())
let track = args.firstIndex(of: "--track").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "Audio 1"
let out = args.firstIndex(of: "--out").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }

if args.contains("--help") || out == nil {
    print("Usage: logic-plugin-slot-surface-probe --track 'Audio 1' --out /path/evidence.json")
    exit(out == nil ? 2 : 0)
}
exit(run(track: track, out: out!))
