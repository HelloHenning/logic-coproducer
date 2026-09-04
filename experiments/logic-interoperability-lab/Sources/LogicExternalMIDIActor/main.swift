import AppKit
import ApplicationServices
import Foundation

private let eventListColumnIDs = ["Lock", "Muted", "Position", "Status", "Ch", "Num", "Val", "Length"]

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
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }
    static func number(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> Double? {
        guard let raw = copy(element, attribute) else { return nil }
        if let number = raw as? NSNumber { return number.doubleValue }
        if let string = raw as? String { return Double(string) }
        return nil
    }
    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let raw = copy(element, attribute) else { return nil }
        if let value = raw as? Bool { return value }
        if let number = raw as? NSNumber { return number.boolValue }
        return nil
    }
    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        copy(element, attribute) as? [AXUIElement] ?? []
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        elements(element, kAXChildrenAttribute).filter { !CFEqual($0, element) }
    }
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copy(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }
    static func display(_ element: AXUIElement) -> String? {
        string(element, kAXDescriptionAttribute)
            ?? simple(element, "AXValueDescription")
            ?? simple(element)
            ?? string(element, kAXTitleAttribute)
            ?? string(element, kAXIdentifierAttribute)
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
    static func setString(_ element: AXUIElement, _ value: String) -> AXError {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
    }
    static func setNumber(_ element: AXUIElement, _ value: Double) -> AXError {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, NSNumber(value: value))
    }
    static func perform(_ element: AXUIElement, _ action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }
}

private struct Snapshot: Decodable {
    let rows: [SnapshotRow]
}

private struct SnapshotRow: Decodable {
    let position: String?
    let status: String?
    let channelRaw: String?
    let channelDescription: String?
    let numberRaw: String?
    let numberDescription: String?
    let valueRaw: String?
    let valueDescription: String?
    let valueMinimum: String?
    let valueMaximum: String?
    let length: String?
}

private struct CanonicalRow: Codable, Hashable, Comparable {
    let position: String
    let status: String
    let channel: String
    let numberRaw: String
    let numberDescription: String
    let valueRaw: String
    let valueDescription: String
    let length: String

    static func < (lhs: CanonicalRow, rhs: CanonicalRow) -> Bool {
        lhs.key < rhs.key
    }
    private var key: String {
        [position, status, channel, numberRaw, numberDescription, valueRaw, valueDescription, length].joined(separator: "\u{1f}")
    }
}

private struct Plan: Codable {
    let schema: String
    let label: String
    let removed: [CanonicalRow]
    let added: [CanonicalRow]
}

private struct LiveRow {
    let row: AXUIElement
    let cells: [AXUIElement]
    let canonical: CanonicalRow
}

private func option(_ name: String, args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

private func normalize(_ value: String?) -> String {
    (value ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func canonical(_ row: SnapshotRow) -> CanonicalRow {
    CanonicalRow(
        position: normalize(row.position),
        status: normalize(row.status),
        channel: normalize(row.channelDescription ?? row.channelRaw),
        numberRaw: normalize(row.numberRaw),
        numberDescription: normalize(row.numberDescription),
        valueRaw: normalize(row.valueRaw),
        valueDescription: normalize(row.valueDescription),
        length: normalize(row.length)
    )
}

private func loadSnapshot(_ path: String) throws -> Snapshot {
    try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

private func writePlan(label: String, removed: [CanonicalRow], added: [CanonicalRow], path: String?) throws {
    let plan = Plan(schema: "logic-coproducer-external-actor-plan/1.0", label: label, removed: removed.sorted(), added: added.sorted())
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(plan)
    if let path {
        try data.write(to: URL(fileURLWithPath: path))
    } else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private func columns(_ table: AXUIElement) -> [String] {
    let direct = AX.elements(table, "AXColumns")
    let source = direct.isEmpty ? AX.children(table).filter { AX.string($0, kAXRoleAttribute) == kAXColumnRole } : direct
    return source.compactMap { AX.string($0, kAXIdentifierAttribute) }
}

private func findEventList(_ root: AXUIElement, maxDepth: Int = 24, maxNodes: Int = 50_000) -> AXUIElement? {
    var stack: [(AXUIElement, Int)] = [(root, 0)]
    var seen: Set<AXIdentity> = []
    var visited = 0
    while let (element, depth) = stack.popLast(), visited < maxNodes {
        let identity = AXIdentity(element: element)
        guard seen.insert(identity).inserted else { continue }
        visited += 1
        if AX.string(element, kAXRoleAttribute) == kAXTableRole,
           Set(eventListColumnIDs).isSubset(of: Set(columns(element))) {
            return element
        }
        guard depth < maxDepth else { continue }
        for child in AX.children(element).reversed() { stack.append((child, depth + 1)) }
    }
    return nil
}

private func primary(_ cell: AXUIElement) -> AXUIElement { AX.children(cell).first ?? cell }

private func liveRow(_ row: AXUIElement) -> LiveRow? {
    let cells = AX.children(row).filter { AX.string($0, kAXRoleAttribute) == kAXCellRole }
    guard cells.count >= 8 else { return nil }
    let position = primary(cells[2])
    let status = primary(cells[3])
    let channel = primary(cells[4])
    let number = primary(cells[5])
    let value = primary(cells[6])
    let length = primary(cells[7])
    return LiveRow(
        row: row,
        cells: cells,
        canonical: CanonicalRow(
            position: normalize(AX.display(position)),
            status: normalize(AX.display(status)),
            channel: normalize(AX.simple(channel, "AXValueDescription") ?? AX.simple(channel)),
            numberRaw: normalize(AX.simple(number)),
            numberDescription: normalize(AX.simple(number, "AXValueDescription")),
            valueRaw: normalize(AX.simple(value)),
            valueDescription: normalize(AX.simple(value, "AXValueDescription") ?? AX.simple(value)),
            length: normalize(AX.display(length))
        )
    )
}

private func scrollBar(for table: AXUIElement) -> AXUIElement? {
    guard let parent = AX.element(table, kAXParentAttribute) else { return nil }
    return AX.children(parent).first { AX.string($0, kAXRoleAttribute) == kAXScrollBarRole && AX.settable($0) }
}

private func setScroll(_ bar: AXUIElement, _ value: Double) {
    _ = AX.setNumber(bar, value)
    usleep(120_000)
}

private func findLiveRow(table: AXUIElement, expected: CanonicalRow, scrollSteps: Int = 16) -> (index: Int, row: LiveRow)? {
    let rows = AX.elements(table, "AXRows")
    guard !rows.isEmpty else { return nil }
    let bar = scrollBar(for: table)
    var originalScroll: Double?
    if let bar { originalScroll = AX.number(bar) }
    defer {
        if let bar, let originalScroll { setScroll(bar, originalScroll) }
    }

    var indexes: Set<Int> = []
    var positions: [Int: Double] = [:]
    let sweep: [Double] = bar == nil ? [0] : (0...max(1, scrollSteps)).map { Double($0) / Double(max(1, scrollSteps)) }
    for scroll in sweep {
        if let bar { setScroll(bar, scroll) }
        for (index, row) in rows.enumerated() {
            if let live = liveRow(row), live.canonical == expected {
                indexes.insert(index)
                positions[index] = scroll
            }
        }
    }
    guard indexes.count == 1, let index = indexes.first else { return nil }
    if let bar, let scroll = positions[index] { setScroll(bar, scroll) }
    let refreshed = AX.elements(table, "AXRows")
    guard refreshed.indices.contains(index), let live = liveRow(refreshed[index]), live.canonical == expected else { return nil }
    return (index, live)
}

private func writableElement(in cell: AXUIElement) -> AXUIElement? {
    let candidates = [primary(cell), cell] + AX.children(cell)
    return candidates.first { AX.settable($0) }
}

private func rereadRow(table: AXUIElement, index: Int) -> LiveRow? {
    let rows = AX.elements(table, "AXRows")
    guard rows.indices.contains(index) else { return nil }
    return liveRow(rows[index])
}

private func keyEvent(keyCode: CGKeyCode, command: Bool = false) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else { return }
    if command {
        down.flags = .maskCommand
        up.flags = .maskCommand
    }
    down.post(tap: .cgAnnotatedSessionEventTap)
    usleep(60_000)
    up.post(tap: .cgAnnotatedSessionEventTap)
}

private func selectRow(table: AXUIElement, row: AXUIElement) -> Bool {
    if AX.settable(table, kAXSelectedRowsAttribute) {
        let array = NSArray(object: row)
        let error = AXUIElementSetAttributeValue(table, kAXSelectedRowsAttribute as CFString, array)
        if error == .success {
            usleep(120_000)
            let selected = AX.elements(table, kAXSelectedRowsAttribute)
            if selected.count == 1, CFEqual(selected[0], row) { return true }
        }
    }
    if AX.settable(row, kAXSelectedAttribute) {
        let error = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        if error == .success {
            usleep(120_000)
            if AX.bool(row, kAXSelectedAttribute) == true { return true }
        }
    }
    return false
}

private func allCanonicalRows(table: AXUIElement, scrollSteps: Int = 16) -> [CanonicalRow] {
    let rows = AX.elements(table, "AXRows")
    guard !rows.isEmpty else { return [] }
    let bar = scrollBar(for: table)
    var originalScroll: Double?
    if let bar { originalScroll = AX.number(bar) }
    defer {
        if let bar, let originalScroll { setScroll(bar, originalScroll) }
    }
    var byIndex: [Int: CanonicalRow] = [:]
    let sweep: [Double] = bar == nil ? [0] : (0...max(1, scrollSteps)).map { Double($0) / Double(max(1, scrollSteps)) }
    for scroll in sweep {
        if let bar { setScroll(bar, scroll) }
        for (index, row) in rows.enumerated() {
            if let live = liveRow(row), !live.canonical.position.isEmpty, !live.canonical.status.isEmpty {
                byIndex[index] = live.canonical
            }
        }
    }
    return byIndex.keys.sorted().compactMap { byIndex[$0] }
}

private func liveEnvironment() -> (NSRunningApplication, AXUIElement, AXUIElement)? {
    guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { return nil }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    guard let table = findEventList(root) else { return nil }
    return (app, root, table)
}

private func setTextField(table: AXUIElement, target: LiveRow, index: Int, field: String, desired: String) -> LiveRow? {
    let cellIndex: Int
    switch field {
    case "position": cellIndex = 2
    case "length": cellIndex = 7
    default: return nil
    }
    guard let element = writableElement(in: target.cells[cellIndex]) else { return nil }
    let original = field == "position" ? target.canonical.position : target.canonical.length
    let error = AX.setString(element, desired)
    guard error == .success else { return nil }
    usleep(450_000)
    guard let changed = rereadRow(table: table, index: index) else {
        _ = AX.setString(element, original)
        return nil
    }
    let observed = field == "position" ? changed.canonical.position : changed.canonical.length
    guard normalize(observed) == normalize(desired) else {
        _ = AX.setString(element, original)
        usleep(300_000)
        return nil
    }
    return changed
}

private func setValueRaw(table: AXUIElement, target: LiveRow, index: Int, desiredRaw: Double, desiredDescription: String?) -> LiveRow? {
    guard let element = writableElement(in: target.cells[6]) else { return nil }
    let error = AX.setNumber(element, desiredRaw)
    guard error == .success else { return nil }
    usleep(450_000)
    guard let changed = rereadRow(table: table, index: index) else { return nil }
    if let desiredDescription, changed.canonical.valueDescription != desiredDescription { return nil }
    return changed
}

private func desiredRawForDisplay(_ desired: Int, valueElement: AXUIElement) -> Double? {
    let minRaw = AX.number(valueElement, kAXMinValueAttribute) ?? 0
    let maxRaw = AX.number(valueElement, kAXMaxValueAttribute) ?? 127
    guard maxRaw > minRaw else { return nil }
    if maxRaw <= 127.000001 { return Double(desired) }
    return minRaw + (Double(desired) / 127.0) * (maxRaw - minRaw)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fputs("Usage: logic-external-midi-actor mutate-field|restore-field|delete-row|undo-delete ...\n", stderr)
    exit(2)
}

guard let env = liveEnvironment() else {
    fputs("Logic/Event List/Accessibility unavailable. Keep the qualified synthetic fixture selected with Event List visible.\n", stderr)
    exit(4)
}
let app = env.0
var table = env.2
let planPath = option("--plan", args: args)
let label = option("--label", args: args) ?? command

func snapshotRow(path: String, index: Int) throws -> (Snapshot, SnapshotRow, CanonicalRow) {
    let snapshot = try loadSnapshot(path)
    guard snapshot.rows.indices.contains(index) else { throw NSError(domain: "LogicExternalMIDIActor", code: 1, userInfo: [NSLocalizedDescriptionKey: "row index out of range"]) }
    let row = snapshot.rows[index]
    return (snapshot, row, canonical(row))
}

do {
    switch command {
    case "mutate-field":
        guard let baselinePath = option("--baseline", args: args),
              let rowIndexText = option("--row-index", args: args), let rowIndex = Int(rowIndexText),
              let field = option("--field", args: args)
        else { throw NSError(domain: "LogicExternalMIDIActor", code: 2, userInfo: [NSLocalizedDescriptionKey: "mutate-field requires --baseline --row-index --field"]) }

        let (_, snapshotRaw, expected) = try snapshotRow(path: baselinePath, index: rowIndex)
        guard let located = findLiveRow(table: table, expected: expected) else {
            fputs("Live row does not exactly match the authoritative baseline target; refusing mutation.\n", stderr)
            exit(6)
        }
        let before = located.row.canonical
        var after: LiveRow?

        if field == "position" || field == "length" {
            guard let desired = option("--to", args: args) else { throw NSError(domain: "LogicExternalMIDIActor", code: 3, userInfo: [NSLocalizedDescriptionKey: "text field mutation requires --to"]) }
            after = setTextField(table: table, target: located.row, index: located.index, field: field, desired: desired)
        } else if field == "value" {
            guard let deltaText = option("--delta", args: args), let delta = Int(deltaText),
                  let currentDisplay = Int(before.valueDescription)
            else { throw NSError(domain: "LogicExternalMIDIActor", code: 4, userInfo: [NSLocalizedDescriptionKey: "value mutation requires integer --delta and numeric displayed value"]) }
            let desiredDisplay = currentDisplay + delta
            guard (0...127).contains(desiredDisplay) else { exit(10) }
            let valueElement = primary(located.row.cells[6])
            let action = delta == 1 ? kAXIncrementAction as String : delta == -1 ? kAXDecrementAction as String : ""
            if !action.isEmpty, AX.actions(valueElement).contains(action), AX.perform(valueElement, action) == .success {
                usleep(450_000)
                if let reread = rereadRow(table: table, index: located.index), reread.canonical.valueDescription == String(desiredDisplay) {
                    after = reread
                }
            }
            if after == nil, let raw = desiredRawForDisplay(desiredDisplay, valueElement: valueElement) {
                after = setValueRaw(table: table, target: located.row, index: located.index, desiredRaw: raw, desiredDescription: String(desiredDisplay))
            }
            if after == nil, let originalRaw = Double(snapshotRaw.valueRaw ?? "") {
                _ = setValueRaw(table: table, target: located.row, index: located.index, desiredRaw: originalRaw, desiredDescription: before.valueDescription)
            }
        } else {
            throw NSError(domain: "LogicExternalMIDIActor", code: 5, userInfo: [NSLocalizedDescriptionKey: "unsupported field \(field)"])
        }

        guard let after else {
            print("RESULT=SKIP label=\(label) reason=field-not-safely-writable")
            exit(10)
        }
        try writePlan(label: label, removed: [before], added: [after.canonical], path: planPath)
        print("RESULT=WRITE_OK label=\(label) field=\(field)")

    case "restore-field":
        guard let currentPath = option("--baseline-current", args: args),
              let sourcePath = option("--restore-source", args: args),
              let rowIndexText = option("--row-index", args: args), let rowIndex = Int(rowIndexText),
              let field = option("--field", args: args)
        else { throw NSError(domain: "LogicExternalMIDIActor", code: 6, userInfo: [NSLocalizedDescriptionKey: "restore-field requires --baseline-current --restore-source --row-index --field"]) }

        let (_, _, expectedCurrent) = try snapshotRow(path: currentPath, index: rowIndex)
        let (_, restoreRaw, restoreCanonical) = try snapshotRow(path: sourcePath, index: rowIndex)
        guard let located = findLiveRow(table: table, expected: expectedCurrent) else {
            fputs("Current live row no longer matches restoration baseline.\n", stderr)
            exit(30)
        }
        let before = located.row.canonical
        var after: LiveRow?
        if field == "position" {
            after = setTextField(table: table, target: located.row, index: located.index, field: field, desired: restoreCanonical.position)
        } else if field == "length" {
            after = setTextField(table: table, target: located.row, index: located.index, field: field, desired: restoreCanonical.length)
        } else if field == "value", let raw = Double(restoreRaw.valueRaw ?? "") {
            after = setValueRaw(table: table, target: located.row, index: located.index, desiredRaw: raw, desiredDescription: restoreCanonical.valueDescription)
        }
        guard let after, after.canonical == restoreCanonical else {
            fputs("RESTORE_FAIL: live row could not be restored exactly.\n", stderr)
            exit(30)
        }
        try writePlan(label: label, removed: [before], added: [after.canonical], path: planPath)
        print("RESULT=RESTORE_OK label=\(label) field=\(field)")

    case "delete-row":
        guard let baselinePath = option("--baseline", args: args),
              let rowIndexText = option("--row-index", args: args), let rowIndex = Int(rowIndexText)
        else { throw NSError(domain: "LogicExternalMIDIActor", code: 7, userInfo: [NSLocalizedDescriptionKey: "delete-row requires --baseline --row-index"]) }
        let (snapshot, _, expected) = try snapshotRow(path: baselinePath, index: rowIndex)
        guard let located = findLiveRow(table: table, expected: expected) else { exit(6) }
        guard selectRow(table: table, row: located.row.row) else {
            print("RESULT=SKIP label=\(label) reason=row-selection-not-verifiable")
            exit(10)
        }
        if AX.settable(table, kAXFocusedAttribute) {
            _ = AXUIElementSetAttributeValue(table, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        _ = app.activate(options: [.activateIgnoringOtherApps])
        usleep(220_000)
        keyEvent(keyCode: 51)
        usleep(600_000)
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let refreshed = findEventList(root) else { exit(20) }
        table = refreshed
        let rowsNow = AX.elements(table, "AXRows")
        let stillThere = findLiveRow(table: table, expected: expected) != nil
        guard rowsNow.count == snapshot.rows.count - 1, !stillThere else {
            // Only undo if we have evidence that deletion actually occurred.
            if rowsNow.count == snapshot.rows.count - 1 || !stillThere {
                keyEvent(keyCode: 6, command: true)
                usleep(500_000)
            }
            print("RESULT=FAIL label=\(label) reason=delete-not-exact")
            exit(20)
        }
        try writePlan(label: label, removed: [expected], added: [], path: planPath)
        print("RESULT=WRITE_OK label=\(label) operation=delete")

    case "undo-delete":
        guard let deletedPath = option("--deleted-state", args: args),
              let originalPath = option("--original-state", args: args),
              let rowIndexText = option("--row-index", args: args), let rowIndex = Int(rowIndexText)
        else { throw NSError(domain: "LogicExternalMIDIActor", code: 8, userInfo: [NSLocalizedDescriptionKey: "undo-delete requires --deleted-state --original-state --row-index"]) }
        let deleted = try loadSnapshot(deletedPath)
        let original = try loadSnapshot(originalPath)
        guard original.rows.indices.contains(rowIndex) else { exit(2) }
        let target = canonical(original.rows[rowIndex])
        let rowsNow = AX.elements(table, "AXRows")
        guard rowsNow.count == deleted.rows.count, deleted.rows.count == original.rows.count - 1, findLiveRow(table: table, expected: target) == nil else {
            fputs("Current state does not match the verified deleted-state precondition; refusing Undo.\n", stderr)
            exit(30)
        }
        _ = app.activate(options: [.activateIgnoringOtherApps])
        usleep(220_000)
        keyEvent(keyCode: 6, command: true)
        usleep(700_000)
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let refreshed = findEventList(root) else { exit(30) }
        table = refreshed
        let afterRows = AX.elements(table, "AXRows")
        guard afterRows.count == original.rows.count, findLiveRow(table: table, expected: target) != nil else {
            fputs("RESTORE_FAIL: Undo did not re-add the exact deleted event.\n", stderr)
            exit(30)
        }
        try writePlan(label: label, removed: [], added: [target], path: planPath)
        print("RESULT=RESTORE_OK label=\(label) operation=undo-add")

    default:
        fputs("Unknown command: \(command)\n", stderr)
        exit(2)
    }
} catch {
    fputs("External MIDI actor failed: \(error)\n", stderr)
    exit(5)
}
