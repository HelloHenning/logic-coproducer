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
    static func description(_ element: AXUIElement) -> String? { simple(element, "AXValueDescription") }
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
    static func settable(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> Bool {
        var value = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &value) == .success && value.boolValue
    }
}

private func option(_ name: String, args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

private func normalized(_ text: String?) -> String {
    (text ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
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

        if AX.string(element, kAXRoleAttribute) == kAXTableRole {
            if Set(eventListColumnIDs).isSubset(of: Set(columns(element))) {
                print("event_list_found visited=\(visited)")
                return element
            }
        }
        guard depth < maxDepth else { continue }
        for child in AX.children(element).reversed() {
            stack.append((child, depth + 1))
        }
    }
    print("event_list_not_found visited=\(visited)")
    return nil
}

private func primary(_ cell: AXUIElement) -> AXUIElement { AX.children(cell).first ?? cell }

struct RowView {
    let row: AXUIElement
    let cells: [AXUIElement]
    let position: String
    let status: String
    let channel: String
    let numberRaw: String
    let numberDescription: String
    let valueDescription: String
}

private func rowView(_ row: AXUIElement) -> RowView? {
    let cells = AX.children(row).filter { AX.string($0, kAXRoleAttribute) == kAXCellRole }
    guard cells.count >= 8 else { return nil }
    let position = normalized(AX.description(primary(cells[2])) ?? AX.simple(primary(cells[2])))
    let status = normalized(AX.string(primary(cells[3]), kAXDescriptionAttribute) ?? AX.description(primary(cells[3])) ?? AX.simple(primary(cells[3])))
    let channelElement = primary(cells[4])
    let numberElement = primary(cells[5])
    let valueElement = primary(cells[6])
    return RowView(
        row: row,
        cells: cells,
        position: position,
        status: status,
        channel: AX.description(channelElement) ?? AX.simple(channelElement) ?? "",
        numberRaw: AX.simple(numberElement) ?? "",
        numberDescription: AX.description(numberElement) ?? "",
        valueDescription: AX.description(valueElement) ?? AX.simple(valueElement) ?? ""
    )
}

private func scrollBar(for table: AXUIElement) -> AXUIElement? {
    guard let parent = AX.element(table, kAXParentAttribute) else { return nil }
    return AX.children(parent).first {
        AX.string($0, kAXRoleAttribute) == kAXScrollBarRole && AX.settable($0)
    }
}

private func setNumber(_ element: AXUIElement, _ value: Int) -> AXError {
    AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, NSNumber(value: value))
}

let args = Array(CommandLine.arguments.dropFirst())
let from = Int(option("--from", args: args) ?? "61") ?? 61
let to = Int(option("--to", args: args) ?? "62") ?? 62
let position = normalized(option("--position", args: args) ?? "1 1 1 1")
let velocity = option("--velocity", args: args) ?? "20"

print("Logic A2 controlled mutation probe")
print("target position=\(position) channel=1 velocity=\(velocity) pitch=\(from)->\(to)")

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is unavailable.\n", stderr)
    exit(3)
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else {
    fputs("Logic Pro is not running.\n", stderr)
    exit(4)
}

let root = AXUIElementCreateApplication(app.processIdentifier)
guard let table = findEventList(root) else {
    fputs("Event List table not found. Keep the corrected fixture selected and Event List visible.\n", stderr)
    exit(5)
}

var originalScroll: Double?
if let bar = scrollBar(for: table) {
    if let raw = AX.copy(bar, kAXValueAttribute), let number = raw as? NSNumber {
        originalScroll = number.doubleValue
    }
    _ = AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: 0.0))
    usleep(250_000)
}

defer {
    if let bar = scrollBar(for: table), let originalScroll {
        _ = AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: originalScroll))
        usleep(100_000)
    }
}

func matchingRows(pitch: Int) -> [RowView] {
    AX.elements(table, "AXRows").compactMap(rowView).filter {
        $0.position == position &&
        $0.status == "Note" &&
        $0.channel == "1" &&
        $0.numberRaw == String(pitch) &&
        $0.valueDescription == velocity
    }
}

let before = matchingRows(pitch: from)
guard before.count == 1, let target = before.first else {
    fputs("Expected exactly one target row before mutation; found \(before.count).\n", stderr)
    exit(6)
}

let numberElement = primary(target.cells[5])
print("before number_raw=\(target.numberRaw) number_desc=\(target.numberDescription) settable=\(AX.settable(numberElement) ? "yes" : "no")")
guard AX.settable(numberElement) else {
    fputs("Target note-number AXValue is not settable.\n", stderr)
    exit(7)
}

let error = setNumber(numberElement, to)
print("write_error=\(error.rawValue)")
guard error == .success else { exit(8) }
usleep(500_000)

let after = matchingRows(pitch: to)
guard after.count == 1, let changed = after.first else {
    fputs("Write returned success, but exactly one changed target could not be read back; found \(after.count).\n", stderr)
    exit(9)
}

print("after number_raw=\(changed.numberRaw) number_desc=\(changed.numberDescription)")
print("RESULT=WRITE_OK")
