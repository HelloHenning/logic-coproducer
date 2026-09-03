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

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let raw = copy(element, kAXChildrenAttribute) else { return [] }
        return (raw as? [AXUIElement] ?? []).filter { !CFEqual($0, element) }
    }

    static func actions(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    static func settable(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> Bool {
        var value = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &value) == .success && value.boolValue
    }

    static func setNumber(_ element: AXUIElement, _ value: Double) -> AXError {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, NSNumber(value: value))
    }
}

private struct Candidate: Codable {
    let path: String
    let role: String?
    let subrole: String?
    let title: String?
    let identifier: String?
    let elementDescription: String?
    let value: String?
    let valueDescription: String?
    let minimum: Double?
    let maximum: Double?
    let enabled: Bool?
    let valueSettable: Bool
    let actions: [String]
}

private struct CandidateRef {
    let candidate: Candidate
    let element: AXUIElement
}

private struct InventoryResult: Codable {
    let schema: String
    let generatedAt: String
    let visitedNodes: Int
    let queries: [String]
    let matches: [String: [Candidate]]
}

private struct RoundTripResult: Codable {
    let schema: String
    let generatedAt: String
    let operation: String
    let query: String
    let result: String
    let reason: String?
    let target: Candidate?
    let before: String?
    let changed: String?
    let restored: String?
    let writeError: Int?
    let restoreError: Int?
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

    func all(from root: AXUIElement) -> [CandidateRef] {
        var stack: [(AXUIElement, Int, String)] = [(root, 0, "app")]
        var output: [CandidateRef] = []

        while let (element, depth, path) = stack.popLast(), visited < maxNodes {
            let identity = AXIdentity(element: element)
            guard seen.insert(identity).inserted else { continue }
            visited += 1

            let role = AX.string(element, kAXRoleAttribute)
            let candidate = Candidate(
                path: path,
                role: role,
                subrole: AX.string(element, kAXSubroleAttribute),
                title: AX.string(element, kAXTitleAttribute),
                identifier: AX.string(element, kAXIdentifierAttribute),
                elementDescription: AX.string(element, kAXDescriptionAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                minimum: AX.number(element, kAXMinValueAttribute),
                maximum: AX.number(element, kAXMaxValueAttribute),
                enabled: AX.bool(element, kAXEnabledAttribute),
                valueSettable: AX.settable(element),
                actions: AX.actions(element)
            )
            output.append(CandidateRef(candidate: candidate, element: element))

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

private func option(_ name: String, args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

private func nowISO() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func normalized(_ value: String?) -> String {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func fields(_ candidate: Candidate) -> [String] {
    [candidate.title, candidate.identifier, candidate.elementDescription, candidate.valueDescription]
        .compactMap { $0 }
}

private func matches(_ candidate: Candidate, query: String) -> Bool {
    let q = normalized(query)
    guard !q.isEmpty else { return false }
    return fields(candidate).contains { normalized($0).contains(q) }
}

private func exactMatches(_ candidate: Candidate, query: String) -> Bool {
    let q = normalized(query)
    return fields(candidate).contains { normalized($0) == q }
}

private func writeJSON<T: Encodable>(_ value: T, path: String?) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    if let path {
        try data.write(to: URL(fileURLWithPath: path))
    } else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private func logicRoot() -> AXUIElement? {
    guard AXIsProcessTrusted(),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first
    else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

private func scan(maxDepth: Int, maxNodes: Int) -> (refs: [CandidateRef], visited: Int)? {
    guard let root = logicRoot() else { return nil }
    let walker = Walker(maxDepth: maxDepth, maxNodes: maxNodes)
    let refs = walker.all(from: root)
    return (refs, walker.visited)
}

private func chooseSafe(_ refs: [CandidateRef], query: String, numeric: Bool = false, press: Bool = false) -> (CandidateRef?, String?) {
    var candidates = refs.filter { matches($0.candidate, query: query) }
        .filter { $0.candidate.enabled != false }
    if numeric {
        candidates = candidates.filter { $0.candidate.valueSettable && AX.number($0.element) != nil }
    }
    if press {
        candidates = candidates.filter { $0.candidate.actions.contains(kAXPressAction as String) && $0.candidate.value != nil }
    }

    let exact = candidates.filter { exactMatches($0.candidate, query: query) }
    if exact.count == 1 { return (exact[0], nil) }
    if exact.count > 1 { return (nil, "ambiguous exact matches=\(exact.count)") }
    if candidates.count == 1 { return (candidates[0], nil) }
    if candidates.isEmpty { return (nil, "no safe writable/verifiable candidate") }
    return (nil, "ambiguous matches=\(candidates.count)")
}

private func resolvePath(_ path: String, maxDepth: Int, maxNodes: Int) -> CandidateRef? {
    guard let scanned = scan(maxDepth: maxDepth, maxNodes: maxNodes) else { return nil }
    return scanned.refs.first { $0.candidate.path == path }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fputs("Usage: logic-control-probe inventory|numeric-roundtrip|press-roundtrip [options]\n", stderr)
    exit(2)
}

let maxDepth = Int(option("--depth", args: args) ?? "22") ?? 22
let maxNodes = Int(option("--max-nodes", args: args) ?? "50000") ?? 50_000
let out = option("--out", args: args)

guard AXIsProcessTrusted() else {
    fputs("Accessibility permission is unavailable.\n", stderr)
    exit(3)
}
guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first != nil else {
    fputs("Logic Pro is not running.\n", stderr)
    exit(4)
}

if command == "inventory" {
    let queryList = option("--queries", args: args) ?? "Volume,Pan,Mute,Solo,Instrument,Audio FX,MIDI FX,Plug-in,Send,Bus,Input,Output,Automation,Read,Touch,Latch,Write,Stereo Out"
    let queries = queryList.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard let scanned = scan(maxDepth: maxDepth, maxNodes: maxNodes) else { exit(5) }
    var found: [String: [Candidate]] = [:]
    for query in queries {
        found[query] = scanned.refs.filter { matches($0.candidate, query: query) }.map(\.candidate)
    }
    let result = InventoryResult(schema: "logic-coproducer-control-inventory/1.0", generatedAt: nowISO(), visitedNodes: scanned.visited, queries: queries, matches: found)
    do { try writeJSON(result, path: out) } catch { fputs("Could not write inventory: \(error)\n", stderr); exit(6) }
    for query in queries { print("\(query)=\(found[query]?.count ?? 0)") }
    print("RESULT=PASS")
    exit(0)
}

guard let query = option("--query", args: args), !query.isEmpty else {
    fputs("Round-trip commands require --query.\n", stderr)
    exit(2)
}

guard let initialScan = scan(maxDepth: maxDepth, maxNodes: maxNodes) else { exit(5) }

if command == "numeric-roundtrip" {
    let (selected, reason) = chooseSafe(initialScan.refs, query: query, numeric: true)
    guard let selected else {
        let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "SKIP", reason: reason, target: nil, before: nil, changed: nil, restored: nil, writeError: nil, restoreError: nil)
        try? writeJSON(result, path: out)
        print("RESULT=SKIP reason=\(reason ?? "unknown")")
        exit(10)
    }
    guard let before = AX.number(selected.element) else { exit(10) }
    let minValue = selected.candidate.minimum
    let maxValue = selected.candidate.maximum
    var step: Double
    if let minValue, let maxValue, maxValue > minValue { step = max((maxValue - minValue) * 0.05, 0.001) }
    else { step = abs(before) <= 1.0 ? 0.05 : 1.0 }
    var requested = before + step
    if let maxValue, requested > maxValue { requested = before - step }
    if let minValue { requested = max(requested, minValue) }
    if let maxValue { requested = min(requested, maxValue) }
    guard abs(requested - before) > 1e-9 else {
        let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "SKIP", reason: "could not derive reversible in-range test value", target: selected.candidate, before: String(before), changed: nil, restored: nil, writeError: nil, restoreError: nil)
        try? writeJSON(result, path: out)
        print("RESULT=SKIP reason=no reversible test value")
        exit(10)
    }

    let writeError = AX.setNumber(selected.element, requested)
    guard writeError == .success else {
        let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "FAIL", reason: "AXValue write failed", target: selected.candidate, before: String(before), changed: nil, restored: nil, writeError: Int(writeError.rawValue), restoreError: nil)
        try? writeJSON(result, path: out)
        print("RESULT=FAIL write_error=\(writeError.rawValue)")
        exit(20)
    }
    usleep(300_000)
    guard let changedRef = resolvePath(selected.candidate.path, maxDepth: maxDepth, maxNodes: maxNodes), let changed = AX.number(changedRef.element), abs(changed - before) > 1e-9 else {
        _ = AX.setNumber(selected.element, before)
        let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "FAIL", reason: "write returned success but independent rescan did not observe a changed value", target: selected.candidate, before: String(before), changed: nil, restored: nil, writeError: Int(writeError.rawValue), restoreError: nil)
        try? writeJSON(result, path: out)
        print("RESULT=FAIL readback")
        exit(21)
    }

    guard let currentRef = resolvePath(selected.candidate.path, maxDepth: maxDepth, maxNodes: maxNodes) else { exit(30) }
    let restoreError = AX.setNumber(currentRef.element, before)
    usleep(300_000)
    guard restoreError == .success,
          let restoredRef = resolvePath(selected.candidate.path, maxDepth: maxDepth, maxNodes: maxNodes),
          let restored = AX.number(restoredRef.element),
          abs(restored - before) <= 1e-6
    else {
        let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "RESTORE_FAIL", reason: "control could not be verified back at its original value", target: selected.candidate, before: String(before), changed: String(changed), restored: nil, writeError: Int(writeError.rawValue), restoreError: Int(restoreError.rawValue))
        try? writeJSON(result, path: out)
        print("RESULT=RESTORE_FAIL")
        exit(30)
    }

    let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "PASS", reason: nil, target: selected.candidate, before: String(before), changed: String(changed), restored: String(restored), writeError: Int(writeError.rawValue), restoreError: Int(restoreError.rawValue))
    try? writeJSON(result, path: out)
    print("RESULT=PASS path=\(selected.candidate.path) before=\(before) changed=\(changed) restored=\(restored)")
    exit(0)
}

if command == "press-roundtrip" {
    let (selected, reason) = chooseSafe(initialScan.refs, query: query, press: true)
    guard let selected else {
        let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "SKIP", reason: reason, target: nil, before: nil, changed: nil, restored: nil, writeError: nil, restoreError: nil)
        try? writeJSON(result, path: out)
        print("RESULT=SKIP reason=\(reason ?? "unknown")")
        exit(10)
    }
    guard let before = AX.simple(selected.element) else { exit(10) }
    let writeError = AXUIElementPerformAction(selected.element, kAXPressAction as CFString)
    guard writeError == .success else {
        let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "FAIL", reason: "AXPress failed", target: selected.candidate, before: before, changed: nil, restored: nil, writeError: Int(writeError.rawValue), restoreError: nil)
        try? writeJSON(result, path: out)
        print("RESULT=FAIL press_error=\(writeError.rawValue)")
        exit(20)
    }
    usleep(300_000)
    guard let changedRef = resolvePath(selected.candidate.path, maxDepth: maxDepth, maxNodes: maxNodes), let changed = AX.simple(changedRef.element), changed != before else {
        _ = AXUIElementPerformAction(selected.element, kAXPressAction as CFString)
        let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "FAIL", reason: "press returned success but independent rescan did not observe a state change", target: selected.candidate, before: before, changed: nil, restored: nil, writeError: Int(writeError.rawValue), restoreError: nil)
        try? writeJSON(result, path: out)
        print("RESULT=FAIL readback")
        exit(21)
    }
    guard let currentRef = resolvePath(selected.candidate.path, maxDepth: maxDepth, maxNodes: maxNodes) else { exit(30) }
    let restoreError = AXUIElementPerformAction(currentRef.element, kAXPressAction as CFString)
    usleep(300_000)
    guard restoreError == .success,
          let restoredRef = resolvePath(selected.candidate.path, maxDepth: maxDepth, maxNodes: maxNodes),
          let restored = AX.simple(restoredRef.element),
          restored == before
    else {
        let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "RESTORE_FAIL", reason: "toggle could not be verified back at its original state", target: selected.candidate, before: before, changed: changed, restored: nil, writeError: Int(writeError.rawValue), restoreError: Int(restoreError.rawValue))
        try? writeJSON(result, path: out)
        print("RESULT=RESTORE_FAIL")
        exit(30)
    }
    let result = RoundTripResult(schema: "logic-coproducer-control-roundtrip/1.0", generatedAt: nowISO(), operation: command, query: query, result: "PASS", reason: nil, target: selected.candidate, before: before, changed: changed, restored: restored, writeError: Int(writeError.rawValue), restoreError: Int(restoreError.rawValue))
    try? writeJSON(result, path: out)
    print("RESULT=PASS path=\(selected.candidate.path) before=\(before) changed=\(changed) restored=\(restored)")
    exit(0)
}

fputs("Unknown command: \(command)\n", stderr)
exit(2)
