import AppKit
import ApplicationServices
import Foundation

struct AXIdentity: Hashable {
    let element: AXUIElement
    static func == (lhs: AXIdentity, rhs: AXIdentity) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

enum AX {
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
    static func number(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> Double? {
        guard let raw = copy(element, attribute) else { return nil }
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s) }
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
    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copy(element, attribute) as? [AXUIElement]) ?? []
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

struct Candidate: Codable {
    let path: String
    let role: String?
    let subrole: String?
    let title: String?
    let identifier: String?
    let elementDescription: String?
    let value: String?
    let valueDescription: String?
    let enabled: Bool?
    let selected: Bool?
    let actions: [String]
}

struct Ref {
    let candidate: Candidate
    let element: AXUIElement
}

final class Walker {
    let maxDepth: Int
    let maxNodes: Int
    private(set) var visited = 0
    private var seen: Set<AXIdentity> = []
    init(maxDepth: Int = 30, maxNodes: Int = 100_000) { self.maxDepth = maxDepth; self.maxNodes = maxNodes }
    func all(from root: AXUIElement) -> [Ref] {
        var stack: [(AXUIElement, Int, String)] = [(root, 0, "app")]
        var out: [Ref] = []
        while let (element, depth, path) = stack.popLast(), visited < maxNodes {
            let identity = AXIdentity(element: element)
            guard seen.insert(identity).inserted else { continue }
            visited += 1
            let role = AX.string(element, kAXRoleAttribute)
            out.append(Ref(candidate: Candidate(
                path: path,
                role: role,
                subrole: AX.string(element, kAXSubroleAttribute),
                title: AX.string(element, kAXTitleAttribute),
                identifier: AX.string(element, kAXIdentifierAttribute),
                elementDescription: AX.string(element, kAXDescriptionAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                enabled: AX.bool(element, kAXEnabledAttribute),
                selected: AX.bool(element, kAXSelectedAttribute),
                actions: AX.actions(element)
            ), element: element))
            guard depth < maxDepth else { continue }
            for (i, child) in AX.children(element).enumerated().reversed() {
                let childRole = AX.string(child, kAXRoleAttribute) ?? "AXElement"
                stack.append((child, depth + 1, "\(path)/\(childRole)[\(i)]"))
            }
        }
        return out
    }
}

func option(_ name: String, _ args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func norm(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
func fields(_ c: Candidate) -> [String] { [c.title, c.identifier, c.elementDescription, c.value, c.valueDescription].compactMap { $0 } }
func text(_ c: Candidate) -> String { fields(c).joined(separator: " ").lowercased() }
func exactField(_ c: Candidate, _ wanted: String) -> Bool { fields(c).contains { norm($0) == norm(wanted) } }
func subtree(_ refs: [Ref], _ prefix: String) -> [Ref] { refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") } }
func depth(_ path: String) -> Int { path.filter { $0 == "/" }.count }
func parentPath(_ path: String) -> String? { path.lastIndex(of: "/").map { String(path[..<$0]) } }

func logicApp() -> (NSRunningApplication, AXUIElement)? {
    guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { return nil }
    return (app, AXUIElementCreateApplication(app.processIdentifier))
}
func scan() -> (refs: [Ref], visited: Int)? {
    guard let (_, root) = logicApp() else { return nil }
    let walker = Walker()
    return (walker.all(from: root), walker.visited)
}
func activateLogic() -> Bool {
    guard let (app, _) = logicApp() else { return false }
    return app.activate(options: [.activateIgnoringOtherApps])
}

func targetStrips(label: String, refs: [Ref]) -> [Ref] {
    let raw = refs.filter { ref in
        guard ref.candidate.role == kAXLayoutItemRole || ref.candidate.role == kAXGroupRole else { return false }
        let d = subtree(refs, ref.candidate.path)
        let hasTrack = d.contains { exactField($0.candidate, label) }
        let hasVolume = d.contains { $0.candidate.role == kAXSliderRole && text($0.candidate).contains("volume") }
        let hasPan = d.contains { $0.candidate.role == kAXSliderRole && text($0.candidate).contains("pan") }
        return hasTrack && hasVolume && hasPan
    }
    return raw.filter { candidate in
        !raw.contains { other in other.candidate.path != candidate.candidate.path && other.candidate.path.hasPrefix(candidate.candidate.path + "/") }
    }.sorted { depth($0.candidate.path) > depth($1.candidate.path) }
}

@discardableResult
func selectTrack(_ label: String) -> Ref? {
    guard activateLogic() else { return nil }
    usleep(150_000)
    guard let s = scan() else { return nil }
    let strips = targetStrips(label: label, refs: s.refs)
    guard !strips.isEmpty else { return nil }
    let ordered = strips.sorted { ($0.candidate.selected == true ? 0 : 1, $0.candidate.path) < ($1.candidate.selected == true ? 0 : 1, $1.candidate.path) }
    for strip in ordered {
        if AX.settable(strip.element, kAXSelectedAttribute), AX.set(strip.element, kAXSelectedAttribute, kCFBooleanTrue) == .success {
            usleep(200_000); return strip
        }
        for labelRef in subtree(s.refs, strip.candidate.path).filter({ exactField($0.candidate, label) }) {
            if AX.settable(labelRef.element, kAXSelectedAttribute), AX.set(labelRef.element, kAXSelectedAttribute, kCFBooleanTrue) == .success {
                usleep(200_000); return strip
            }
            if labelRef.candidate.actions.contains(kAXPressAction as String), AX.press(labelRef.element) == .success {
                usleep(200_000); return strip
            }
        }
    }
    return nil
}

func focusMainWindow() -> Bool {
    guard activateLogic(), let scanned = scan() else { return false }
    let windows = scanned.refs.filter { $0.candidate.role == kAXWindowRole && norm($0.candidate.title).contains("tracks") }
    guard let w = windows.first else { return true }
    if AX.settable(w.element, kAXFocusedAttribute) { _ = AX.set(w.element, kAXFocusedAttribute, kCFBooleanTrue) }
    if AX.settable(w.element, kAXMainAttribute) { _ = AX.set(w.element, kAXMainAttribute, kCFBooleanTrue) }
    usleep(120_000)
    return true
}

func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
    down.flags = flags; up.flags = flags
    down.post(tap: .cgAnnotatedSessionEventTap); usleep(50_000); up.post(tap: .cgAnnotatedSessionEventTap)
}
func pasteText(_ value: String) {
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    postKey(9, flags: .maskCommand) // V
}
func pressEscape() { postKey(53) }

func nearestActionable(for ref: Ref, within root: Ref, refs: [Ref]) -> Ref? {
    var p: String? = ref.candidate.path
    while let path = p, path.hasPrefix(root.candidate.path) {
        if let candidate = refs.first(where: { $0.candidate.path == path }), candidate.candidate.actions.contains(kAXPressAction as String) { return candidate }
        p = parentPath(path)
    }
    return nil
}

func routingFingerprint(_ refs: [Ref]) -> [String] {
    let tokens = ["st out", "stereo out", "no output", "output", "send", "bus", "input"]
    return refs.compactMap { r -> String? in
        let t = text(r.candidate)
        guard tokens.contains(where: { t.contains($0) }) else { return nil }
        return "\(r.candidate.path)|\(r.candidate.role ?? "")|\(fields(r.candidate).joined(separator: "~"))"
    }.sorted()
}

struct OutputEvidence: Codable {
    let schema: String; let result: String; let reason: String?; let track: String
    let beforeFingerprint: [String]; let changedFingerprint: [String]; let finalFingerprint: [String]
}
func writeJSON<T: Encodable>(_ value: T, path: String?) {
    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let d = try? e.encode(value) else { return }
    if let path { try? d.write(to: URL(fileURLWithPath: path)) } else { FileHandle.standardOutput.write(d); FileHandle.standardOutput.write(Data("\n".utf8)) }
}

func chooseMenuItem(_ title: String) -> Bool {
    guard let s = scan() else { return false }
    let all = s.refs.filter { $0.candidate.role == kAXMenuItemRole && exactField($0.candidate, title) && $0.candidate.actions.contains(kAXPressAction as String) && $0.candidate.enabled != false }
    guard all.count == 1 else { return false }
    return AX.press(all[0].element) == .success
}

func outputRoundtrip(track: String, out: String?) -> Int32 {
    guard let strip0 = selectTrack(track), let s0 = scan() else { print("RESULT=SKIP reason=track-not-resolved"); return 10 }
    let strip = targetStrips(label: track, refs: s0.refs).first(where: { $0.candidate.path == strip0.candidate.path }) ?? targetStrips(label: track, refs: s0.refs).first!
    let d0 = subtree(s0.refs, strip.candidate.path)
    let before = routingFingerprint(d0)
    let st = d0.filter { exactField($0.candidate, "St Out") || exactField($0.candidate, "Stereo Out") }
    let actionable = Array(Set(st.compactMap { nearestActionable(for: $0, within: strip, refs: s0.refs)?.candidate.path })).compactMap { p in s0.refs.first { $0.candidate.path == p } }
    guard actionable.count == 1 else { print("RESULT=SKIP reason=output-slot-not-unique candidates=\(actionable.count)"); return 10 }
    guard AX.press(actionable[0].element) == .success else { print("RESULT=SKIP reason=output-menu-not-opened"); return 10 }
    usleep(200_000)
    guard let menuScan = scan(), menuScan.refs.contains(where: { $0.candidate.role == kAXMenuItemRole && exactField($0.candidate, "No Output") }), menuScan.refs.contains(where: { $0.candidate.role == kAXMenuItemRole && exactField($0.candidate, "Stereo Out") }) else {
        pressEscape(); print("RESULT=SKIP reason=output-menu-contract-not-proven"); return 10
    }
    guard chooseMenuItem("No Output") else { pressEscape(); print("RESULT=SKIP reason=no-output-not-actionable"); return 10 }
    usleep(350_000)
    guard let sc = scan(), let changedStrip = targetStrips(label: track, refs: sc.refs).first else {
        print("RESULT=RESTORE_FAIL reason=track-lost-after-output-change"); return 30
    }
    let changedRefs = subtree(sc.refs, changedStrip.candidate.path)
    let changed = routingFingerprint(changedRefs)
    guard changedRefs.contains(where: { exactField($0.candidate, "No Output") || text($0.candidate).contains("no output") }) else {
        print("RESULT=RESTORE_FAIL reason=no-output-change-not-readable"); return 30
    }
    let noOutRefs = changedRefs.filter { exactField($0.candidate, "No Output") || text($0.candidate).contains("no output") }
    let restoreActions = Array(Set(noOutRefs.compactMap { nearestActionable(for: $0, within: changedStrip, refs: sc.refs)?.candidate.path })).compactMap { p in sc.refs.first { $0.candidate.path == p } }
    guard restoreActions.count == 1, AX.press(restoreActions[0].element) == .success else { print("RESULT=RESTORE_FAIL reason=restore-output-menu-unavailable"); return 30 }
    usleep(180_000)
    guard chooseMenuItem("Stereo Out") else { pressEscape(); print("RESULT=RESTORE_FAIL reason=stereo-out-restore-selection-failed"); return 30 }
    usleep(350_000)
    guard let sf = scan(), let finalStrip = targetStrips(label: track, refs: sf.refs).first else { print("RESULT=RESTORE_FAIL reason=final-track-unavailable"); return 30 }
    let final = routingFingerprint(subtree(sf.refs, finalStrip.candidate.path))
    let ok = final == before
    writeJSON(OutputEvidence(schema: "logic-coproducer-a7-output-roundtrip/1.0", result: ok ? "PASS" : "RESTORE_FAIL", reason: ok ? nil : "routing-fingerprint-mismatch", track: track, beforeFingerprint: before, changedFingerprint: changed, finalFingerprint: final), path: out)
    if ok { print("RESULT=PASS route=Studio_Grand_to_Stereo_Out changed=No_Output restored=Stereo_Out"); return 0 }
    print("RESULT=RESTORE_FAIL reason=routing-fingerprint-mismatch"); return 30
}

func columnIdentifiers(_ table: AXUIElement) -> [String] {
    let direct = AX.elements(table, "AXColumns")
    let cols = direct.isEmpty ? AX.children(table).filter { AX.string($0, kAXRoleAttribute) == kAXColumnRole } : direct
    return cols.map { AX.string($0, kAXIdentifierAttribute) ?? AX.string($0, kAXTitleAttribute) ?? "" }
}
func findAutomationTable(_ refs: [Ref]) -> Ref? {
    let tables = refs.filter { $0.candidate.role == kAXTableRole }
    var scored: [(Ref, Int)] = []
    for t in tables {
        let cols = columnIdentifiers(t.element).map(norm)
        let windowPath = refs.filter { $0.candidate.role == kAXWindowRole && t.candidate.path.hasPrefix($0.candidate.path + "/") }.max { depth($0.candidate.path) < depth($1.candidate.path) }
        let windowText = windowPath.map { text($0.candidate) } ?? ""
        var score = 0
        if windowText.contains("automation") { score += 10 }
        if cols.contains(where: { $0.contains("position") }) { score += 3 }
        if cols.contains(where: { $0 == "value" || $0 == "val" || $0.contains("value") }) { score += 3 }
        if score >= 6 { scored.append((t, score)) }
    }
    scored.sort { $0.1 > $1.1 }
    guard let first = scored.first else { return nil }
    if scored.count > 1 && scored[1].1 == first.1 { return nil }
    return first.0
}
func tableRows(_ table: AXUIElement) -> [AXUIElement] {
    let r = AX.elements(table, "AXRows")
    return r.isEmpty ? AX.children(table).filter { AX.string($0, kAXRoleAttribute) == kAXRowRole } : r
}
func rowCells(_ row: AXUIElement) -> [AXUIElement] { AX.children(row).filter { AX.string($0, kAXRoleAttribute) == kAXCellRole } }
func primary(_ cell: AXUIElement) -> AXUIElement { AX.children(cell).first ?? cell }
func display(_ cell: AXUIElement) -> String {
    let p = primary(cell)
    return AX.string(p, kAXDescriptionAttribute) ?? AX.simple(p, "AXValueDescription") ?? AX.simple(p) ?? AX.string(p, kAXTitleAttribute) ?? ""
}
struct AutomationEvidence: Codable { let schema: String; let result: String; let reason: String?; let columns: [String]; let rows: [[String]]; let before: Double?; let changed: Double?; let restored: Double? }
func automationSnapshot(_ table: AXUIElement) -> (columns: [String], rows: [[String]]) {
    (columnIdentifiers(table), tableRows(table).map { rowCells($0).map(display) })
}

func automationInventory(out: String?) -> Int32 {
    guard let s = scan(), let t = findAutomationTable(s.refs) else { print("RESULT=SKIP reason=automation-event-list-not-resolved"); return 10 }
    let snap = automationSnapshot(t.element)
    writeJSON(AutomationEvidence(schema: "logic-coproducer-a6-automation-inventory/1.0", result: "PASS", reason: nil, columns: snap.columns, rows: snap.rows, before: nil, changed: nil, restored: nil), path: out)
    print("RESULT=PASS rows=\(snap.rows.count) columns=\(snap.columns.joined(separator: ","))")
    return 0
}

func automationRoundtrip(out: String?) -> Int32 {
    guard let s0 = scan(), let t0 = findAutomationTable(s0.refs) else { print("RESULT=SKIP reason=automation-event-list-not-resolved"); return 10 }
    let snap0 = automationSnapshot(t0.element)
    guard !snap0.rows.isEmpty else { print("RESULT=SKIP reason=no-automation-points"); return 10 }
    let ids = snap0.columns.map(norm)
    guard let vi = ids.firstIndex(where: { $0 == "value" || $0 == "val" || $0.contains("value") }) else { print("RESULT=SKIP reason=value-column-not-resolved"); return 10 }
    let rows0 = tableRows(t0.element)
    var chosen: (Int, AXUIElement, Double)?
    for (ri, row) in rows0.enumerated() {
        let cells = rowCells(row); guard vi < cells.count else { continue }
        let p = primary(cells[vi])
        if AX.settable(p, kAXValueAttribute), let n = AX.number(p) { chosen = (ri, p, n); break }
    }
    guard let chosen else { print("RESULT=SKIP reason=no-settable-numeric-automation-value"); return 10 }
    let before = chosen.2
    let min = AX.number(chosen.1, kAXMinValueAttribute), max = AX.number(chosen.1, kAXMaxValueAttribute)
    var step = (min != nil && max != nil && max! > min!) ? max((max! - min!) * 0.01, 0.001) : (abs(before) <= 1 ? 0.01 : 1)
    var requested = before + step
    if let max, requested > max { requested = before - step }
    if let min { requested = Swift.max(requested, min) }; if let max { requested = Swift.min(requested, max) }
    guard abs(requested - before) > 1e-9 else { print("RESULT=SKIP reason=no-reversible-value"); return 10 }
    guard AX.set(chosen.1, kAXValueAttribute, NSNumber(value: requested)) == .success else { print("RESULT=FAIL reason=automation-write-failed"); return 20 }
    usleep(300_000)
    guard let sc = scan(), let tc = findAutomationTable(sc.refs) else { print("RESULT=RESTORE_FAIL reason=automation-readback-unavailable"); return 30 }
    let rowsc = tableRows(tc.element); guard chosen.0 < rowsc.count else { print("RESULT=RESTORE_FAIL reason=automation-row-lost"); return 30 }
    let cellsc = rowCells(rowsc[chosen.0]); guard vi < cellsc.count else { print("RESULT=RESTORE_FAIL reason=automation-value-cell-lost"); return 30 }
    let pc = primary(cellsc[vi]); guard let changed = AX.number(pc), abs(changed - before) > 1e-9 else {
        _ = AX.set(pc, kAXValueAttribute, NSNumber(value: before)); usleep(250_000)
        if let sf = scan(), let tf = findAutomationTable(sf.refs), automationSnapshot(tf.element).rows == snap0.rows { print("RESULT=FAIL reason=write-not-observed restoration=verified"); return 20 }
        print("RESULT=RESTORE_FAIL reason=write-not-observed-and-baseline-unproven"); return 30
    }
    guard AX.set(pc, kAXValueAttribute, NSNumber(value: before)) == .success else { print("RESULT=RESTORE_FAIL reason=automation-restore-write-failed"); return 30 }
    usleep(300_000)
    guard let sf = scan(), let tf = findAutomationTable(sf.refs) else { print("RESULT=RESTORE_FAIL reason=final-automation-inventory-unavailable"); return 30 }
    let snapf = automationSnapshot(tf.element)
    guard snapf.rows == snap0.rows else { print("RESULT=RESTORE_FAIL reason=automation-final-snapshot-mismatch"); return 30 }
    writeJSON(AutomationEvidence(schema: "logic-coproducer-a6-automation-roundtrip/1.0", result: "PASS", reason: nil, columns: snap0.columns, rows: snap0.rows, before: before, changed: changed, restored: before), path: out)
    print("RESULT=PASS row=\(chosen.0) before=\(before) changed=\(changed) restored=\(before)")
    return 0
}

func deleteAllAutomationPoints() -> Int32 {
    guard let s0 = scan(), let t0 = findAutomationTable(s0.refs) else { print("RESULT=SKIP reason=automation-event-list-not-resolved"); return 10 }
    let rows = tableRows(t0.element)
    if rows.isEmpty { print("RESULT=PASS rows=0 already-empty=true"); return 0 }
    if AX.settable(t0.element, "AXSelectedRows") { _ = AX.set(t0.element, "AXSelectedRows", rows as CFArray) }
    let windows = s0.refs.filter { $0.candidate.role == kAXWindowRole && t0.candidate.path.hasPrefix($0.candidate.path + "/") }
    if let w = windows.max(by: { depth($0.candidate.path) < depth($1.candidate.path) }), AX.settable(w.element, kAXFocusedAttribute) { _ = AX.set(w.element, kAXFocusedAttribute, kCFBooleanTrue) }
    postKey(51); usleep(350_000)
    if let s1 = scan(), let t1 = findAutomationTable(s1.refs), tableRows(t1.element).isEmpty { print("RESULT=PASS rows=0 deleted-via-list=true"); return 0 }
    // Baseline-zero callers may use Logic's documented Delete Visible Automation command as a recovery cleanup.
    _ = focusMainWindow(); postKey(51, flags: [.maskControl, .maskCommand]); usleep(350_000)
    if let s2 = scan(), let t2 = findAutomationTable(s2.refs), tableRows(t2.element).isEmpty { print("RESULT=PASS rows=0 deleted-via-visible-automation-command=true"); return 0 }
    print("RESULT=RESTORE_FAIL reason=temporary-automation-not-removed"); return 30
}

func renameTrack(from: String, to: String) -> Int32 {
    guard selectTrack(from) != nil else { print("RESULT=SKIP reason=source-track-not-resolved"); return 10 }
    _ = focusMainWindow(); postKey(36, flags: .maskShift); usleep(150_000)
    postKey(0, flags: .maskCommand); pasteText(to); postKey(36); usleep(350_000)
    guard let s = scan(), !targetStrips(label: to, refs: s.refs).isEmpty else { print("RESULT=FAIL reason=renamed-track-not-observed"); return 20 }
    print("RESULT=PASS from=\(from.replacingOccurrences(of: " ", with: "_")) to=\(to.replacingOccurrences(of: " ", with: "_"))")
    return 0
}

func pressExactMenu(_ title: String) -> Bool {
    guard let s = scan() else { return false }
    let c = s.refs.filter { $0.candidate.role == kAXMenuItemRole && exactField($0.candidate, title) && $0.candidate.actions.contains(kAXPressAction as String) && $0.candidate.enabled != false }
    guard c.count == 1 else { return false }
    return AX.press(c[0].element) == .success
}

func saveCopy(path: String) -> Int32 {
    _ = focusMainWindow()
    var opened = pressExactMenu("Save a Copy As…")
    if !opened { opened = pressExactMenu("Save a Copy As...") }
    guard opened else { print("RESULT=SKIP reason=save-a-copy-menu-not-resolved"); return 10 }
    usleep(500_000)
    let url = URL(fileURLWithPath: path); let dir = url.deletingLastPathComponent().path; let name = url.deletingPathExtension().lastPathComponent
    postKey(5, flags: [.maskCommand, .maskShift]); usleep(150_000) // G
    pasteText(dir); postKey(36); usleep(350_000)
    guard let s = scan() else { print("RESULT=FAIL reason=save-dialog-unavailable"); return 20 }
    let fields = s.refs.filter { $0.candidate.role == kAXTextFieldRole && AX.settable($0.element, kAXValueAttribute) }
    let saveFields = fields.filter { text($0.candidate).contains("save") || norm($0.candidate.value).contains("untitled") || norm($0.candidate.value).contains("copy") }
    let target = saveFields.count == 1 ? saveFields[0] : (fields.count == 1 ? fields[0] : nil)
    guard let target else { pressEscape(); print("RESULT=FAIL reason=save-name-field-ambiguous count=\(fields.count)"); return 20 }
    guard AX.set(target.element, kAXValueAttribute, name as CFString) == .success else { print("RESULT=FAIL reason=save-name-write-failed"); return 20 }
    usleep(100_000)
    guard let s2 = scan() else { return 20 }
    let buttons = s2.refs.filter { $0.candidate.role == kAXButtonRole && exactField($0.candidate, "Save") && $0.candidate.actions.contains(kAXPressAction as String) && $0.candidate.enabled != false }
    guard buttons.count == 1, AX.press(buttons[0].element) == .success else { print("RESULT=FAIL reason=save-button-not-unique count=\(buttons.count)"); return 20 }
    usleep(800_000)
    let fm = FileManager.default
    let candidates = [path, path.hasSuffix(".logicx") ? path : path + ".logicx", url.deletingPathExtension().appendingPathExtension("logicx").path]
    if let actual = candidates.first(where: { fm.fileExists(atPath: $0) }) { print("RESULT=PASS path=\(actual)"); return 0 }
    print("RESULT=FAIL reason=saved-copy-not-found"); return 20
}

func importAudio(track: String, path: String) -> Int32 {
    guard selectTrack(track) != nil else { print("RESULT=SKIP reason=audio-track-not-resolved"); return 10 }
    _ = focusMainWindow(); postKey(34, flags: [.maskShift, .maskCommand]); usleep(450_000) // I
    postKey(5, flags: [.maskShift, .maskCommand]); usleep(120_000) // G
    pasteText(path); postKey(36); usleep(300_000); postKey(36); usleep(800_000)
    let filename = URL(fileURLWithPath: path).lastPathComponent
    guard let s = scan() else { print("RESULT=FAIL reason=post-import-scan-unavailable"); return 20 }
    let hits = s.refs.filter { fields($0.candidate).contains(where: { $0.contains(filename) }) }
    guard !hits.isEmpty else { print("RESULT=FAIL reason=imported-source-marker-not-observed"); return 20 }
    print("RESULT=PASS source=\(filename) hits=\(hits.count)"); return 0
}

func sourceContext(filename: String, out: String?) -> Int32 {
    guard let s = scan() else { return 20 }
    let windows = s.refs.filter { $0.candidate.role == kAXWindowRole }
    let matches = windows.filter { w in subtree(s.refs, w.candidate.path).contains { fields($0.candidate).contains(where: { $0.contains(filename) }) } }
    let editorLike = matches.filter { w in
        let t = text(w.candidate); let d = subtree(s.refs, w.candidate.path)
        return !t.contains("tracks") && (t.contains(filename.lowercased()) || d.contains { text($0.candidate).contains("audio file") || fields($0.candidate).contains(where: { $0.contains(filename) }) })
    }
    let payload = ["schema": "logic-coproducer-a9-source-context/1.0", "filename": filename, "matchingWindows": matches.map { $0.candidate.title ?? $0.candidate.path }, "editorLikeWindows": editorLike.map { $0.candidate.title ?? $0.candidate.path }]
    if let out, let d = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: URL(fileURLWithPath: out)) }
    if editorLike.count == 1 { print("RESULT=PASS mapping_level=associated_source_file_only filename=\(filename)"); return 0 }
    print("RESULT=SKIP reason=source-editor-context-not-unique matching=\(matches.count) editor_like=\(editorLike.count)"); return 10
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fputs("Usage: logic-phase-a-probe track-context|focus-main|key|output-roundtrip|automation-inventory|automation-roundtrip|automation-delete-all|rename-track|save-copy|import-audio|source-context ...\n", stderr); exit(2)
}
guard AXIsProcessTrusted() else { fputs("Accessibility unavailable\n", stderr); exit(3) }
guard logicApp() != nil else { fputs("Logic Pro not running\n", stderr); exit(4) }
let out = option("--out", args)

switch command {
case "track-context":
    guard let label = option("--label", args) else { exit(2) }
    guard let r = selectTrack(label) else { print("RESULT=SKIP reason=track-not-resolved"); exit(10) }
    print("RESULT=PASS track=\(label.replacingOccurrences(of: " ", with: "_")) strip=\(r.candidate.path)")
case "focus-main":
    if focusMainWindow() { print("RESULT=PASS"); exit(0) } else { print("RESULT=FAIL"); exit(20) }
case "key":
    guard let name = option("--name", args) else { exit(2) }
    _ = focusMainWindow()
    switch name {
    case "right": postKey(124)
    case "automation-toggle": postKey(0) // A
    case "automation-create2": postKey(19, flags: [.maskControl, .maskShift, .maskCommand])
    case "automation-list": postKey(14, flags: [.maskControl, .maskCommand])
    case "close-window": postKey(13, flags: .maskCommand) // W
    case "audio-editor": postKey(22, flags: .maskCommand) // 6
    case "undo": postKey(6, flags: .maskCommand) // Z
    default: print("RESULT=FAIL reason=unknown-key"); exit(20)
    }
    usleep(250_000); print("RESULT=PASS key=\(name)")
case "output-roundtrip":
    guard let track = option("--track", args) else { exit(2) }; exit(outputRoundtrip(track: track, out: out))
case "automation-inventory": exit(automationInventory(out: out))
case "automation-roundtrip": exit(automationRoundtrip(out: out))
case "automation-delete-all": exit(deleteAllAutomationPoints())
case "rename-track":
    guard let from = option("--from", args), let to = option("--to", args) else { exit(2) }; exit(renameTrack(from: from, to: to))
case "save-copy":
    guard let path = option("--path", args) else { exit(2) }; exit(saveCopy(path: path))
case "import-audio":
    guard let track = option("--track", args), let path = option("--path", args) else { exit(2) }; exit(importAudio(track: track, path: path))
case "source-context":
    guard let filename = option("--filename", args) else { exit(2) }; exit(sourceContext(filename: filename, out: out))
default: fputs("Unknown command\n", stderr); exit(2)
}
