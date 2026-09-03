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
        var raw: CFArray?
        guard AXUIElementCopyActionNames(element, &raw) == .success else { return [] }
        return raw as? [String] ?? []
    }
    static func settable(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> Bool {
        var flag = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &flag) == .success && flag.boolValue
    }
    static func setNumber(_ element: AXUIElement, _ value: Double) -> AXError {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, NSNumber(value: value))
    }
    static func press(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
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
    let minimum: Double?
    let maximum: Double?
    let enabled: Bool?
    let selected: Bool?
    let focused: Bool?
    let valueSettable: Bool
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

    init(maxDepth: Int, maxNodes: Int) {
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

enum ControlKind: String, Codable, CaseIterable {
    case volume = "Volume"
    case pan = "Pan"
    case mute = "Mute"
    case solo = "Solo"
    var isNumeric: Bool { self == .volume || self == .pan }
}

struct StripTopology: Codable {
    let stripPath: String
    let selectedDescendantCount: Int
    let focusedDescendantCount: Int
    let labelHints: [String]
    let controls: [String: [Candidate]]
}

struct TopologyResult: Codable {
    let schema: String
    let generatedAt: String
    let visitedNodes: Int
    let strips: [StripTopology]
    let selectedElements: [Candidate]
}

struct CaseResult: Codable {
    let control: String
    let stripPath: String
    let targetPath: String
    let result: String
    let reason: String?
    let before: Double?
    let requested: Double?
    let observed: Double?
    let restored: Double?
    let collateralChangedPaths: [String]
    let writeError: Int?
    let restoreError: Int?
}

struct MatrixResult: Codable {
    let schema: String
    let generatedAt: String
    let control: String
    let candidateCount: Int
    let passCount: Int
    let failCount: Int
    let skipCount: Int
    let restoreFailureCount: Int
    let cases: [CaseResult]
}

func option(_ name: String, args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func nowISO() -> String { ISO8601DateFormatter().string(from: Date()) }
func norm(_ value: String?) -> String { (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

func writeJSON<T: Encodable>(_ value: T, path: String?) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    if let path { try data.write(to: URL(fileURLWithPath: path)) }
    else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

func root() -> AXUIElement? {
    guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

func scan(maxDepth: Int, maxNodes: Int) -> (refs: [Ref], visited: Int)? {
    guard let root = root() else { return nil }
    let walker = Walker(maxDepth: maxDepth, maxNodes: maxNodes)
    let refs = walker.all(from: root)
    return (refs, walker.visited)
}

func isMixerPath(_ path: String) -> Bool {
    path.contains("/AXSplitGroup[") && path.contains("/AXScrollArea[") && path.contains("/AXLayoutItem[")
}

func stripPrefix(_ path: String) -> String? {
    let parts = path.split(separator: "/").map(String.init)
    guard let i = parts.firstIndex(where: { $0.hasPrefix("AXLayoutItem[") }) else { return nil }
    return parts[0...i].joined(separator: "/")
}

func controlRefs(_ refs: [Ref], kind: ControlKind) -> [Ref] {
    refs.filter { ref in
        let c = ref.candidate
        guard isMixerPath(c.path), c.enabled != false else { return false }
        switch kind {
        case .volume:
            return c.role == kAXSliderRole && norm(c.elementDescription) == "volume" && c.valueSettable && AX.number(ref.element) != nil
        case .pan:
            return c.role == kAXSliderRole && norm(c.valueDescription).contains("pan") && c.valueSettable && AX.number(ref.element) != nil
        case .mute:
            return c.role == kAXCheckBoxRole && norm(c.elementDescription) == "mute" && c.actions.contains(kAXPressAction as String) && AX.number(ref.element) != nil
        case .solo:
            return c.role == kAXCheckBoxRole && norm(c.elementDescription) == "solo" && c.actions.contains(kAXPressAction as String) && AX.number(ref.element) != nil
        }
    }.sorted { $0.candidate.path < $1.candidate.path }
}

func values(_ refs: [Ref], kind: ControlKind) -> [String: Double] {
    Dictionary(uniqueKeysWithValues: controlRefs(refs, kind: kind).compactMap { ref in
        AX.number(ref.element).map { (ref.candidate.path, $0) }
    })
}

func resolve(_ refs: [Ref], path: String) -> Ref? { refs.first { $0.candidate.path == path } }

func changedPaths(before: [String: Double], after: [String: Double], excluding target: String) -> [String] {
    let keys = Set(before.keys).union(after.keys)
    return keys.filter { key in
        guard key != target else { return false }
        guard let a = before[key], let b = after[key] else { return true }
        return abs(a - b) > 1e-9
    }.sorted()
}

func allEqual(_ a: [String: Double], _ b: [String: Double]) -> Bool {
    guard Set(a.keys) == Set(b.keys) else { return false }
    return a.allSatisfy { key, value in
        guard let other = b[key] else { return false }
        return abs(value - other) <= 1e-9
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fputs("Usage: logic-mixer-matrix topology|matrix [--control Volume|Pan|Mute|Solo] [--out PATH]\n", stderr)
    exit(2)
}
let maxDepth = Int(option("--depth", args: args) ?? "22") ?? 22
let maxNodes = Int(option("--max-nodes", args: args) ?? "50000") ?? 50_000
let out = option("--out", args: args)

guard AXIsProcessTrusted() else { fputs("Accessibility permission is unavailable.\n", stderr); exit(3) }
guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first != nil else { fputs("Logic Pro is not running.\n", stderr); exit(4) }
guard let firstScan = scan(maxDepth: maxDepth, maxNodes: maxNodes) else { exit(5) }

if command == "topology" {
    var prefixes: Set<String> = []
    for kind in ControlKind.allCases {
        for ref in controlRefs(firstScan.refs, kind: kind) {
            if let prefix = stripPrefix(ref.candidate.path) { prefixes.insert(prefix) }
        }
    }
    let strips: [StripTopology] = prefixes.sorted().map { prefix in
        let descendants = firstScan.refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") }
        var hints: [String] = []
        var seenHints: Set<String> = []
        for ref in descendants {
            let c = ref.candidate
            for raw in [c.title, c.identifier, c.elementDescription, c.valueDescription] {
                guard let raw else { continue }
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, text.count <= 120 else { continue }
                let key = text.lowercased()
                if seenHints.insert(key).inserted { hints.append(text) }
                if hints.count >= 40 { break }
            }
            if hints.count >= 40 { break }
        }
        var controls: [String: [Candidate]] = [:]
        for kind in ControlKind.allCases {
            controls[kind.rawValue] = controlRefs(firstScan.refs, kind: kind)
                .filter { stripPrefix($0.candidate.path) == prefix }
                .map(\.candidate)
        }
        return StripTopology(
            stripPath: prefix,
            selectedDescendantCount: descendants.filter { $0.candidate.selected == true }.count,
            focusedDescendantCount: descendants.filter { $0.candidate.focused == true }.count,
            labelHints: hints,
            controls: controls
        )
    }
    let selected = firstScan.refs.filter { $0.candidate.selected == true }.prefix(80).map(\.candidate)
    let topology = TopologyResult(schema: "logic-coproducer-mixer-topology/1.0", generatedAt: nowISO(), visitedNodes: firstScan.visited, strips: strips, selectedElements: Array(selected))
    do { try writeJSON(topology, path: out) } catch { fputs("Could not write topology: \(error)\n", stderr); exit(6) }
    print("strips=\(strips.count) selected_elements=\(selected.count) visited=\(firstScan.visited)")
    for strip in strips {
        let counts = ControlKind.allCases.map { "\($0.rawValue)=\(strip.controls[$0.rawValue]?.count ?? 0)" }.joined(separator: " ")
        print("strip=\(strip.stripPath) selected_descendants=\(strip.selectedDescendantCount) \(counts)")
    }
    print("RESULT=PASS")
    exit(0)
}

guard command == "matrix" else { fputs("Unknown command: \(command)\n", stderr); exit(2) }
guard let controlText = option("--control", args: args), let kind = ControlKind.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(controlText) == .orderedSame }) else {
    fputs("matrix requires --control Volume|Pan|Mute|Solo\n", stderr)
    exit(2)
}

let initialTargets = controlRefs(firstScan.refs, kind: kind)
if initialTargets.isEmpty {
    let empty = MatrixResult(schema: "logic-coproducer-mixer-matrix/1.0", generatedAt: nowISO(), control: kind.rawValue, candidateCount: 0, passCount: 0, failCount: 0, skipCount: 1, restoreFailureCount: 0, cases: [])
    try? writeJSON(empty, path: out)
    print("RESULT=SKIP candidates=0")
    exit(10)
}

var cases: [CaseResult] = []
var passCount = 0
var failCount = 0
var skipCount = 0
var restoreFailureCount = 0

for (index, original) in initialTargets.enumerated() {
    guard let currentScan = scan(maxDepth: maxDepth, maxNodes: maxNodes) else { break }
    let baseline = values(currentScan.refs, kind: kind)
    let path = original.candidate.path
    guard let target = resolve(currentScan.refs, path: path), let before = AX.number(target.element), let strip = stripPrefix(path) else {
        skipCount += 1
        cases.append(CaseResult(control: kind.rawValue, stripPath: stripPrefix(path) ?? "unknown", targetPath: path, result: "SKIP", reason: "target path was not stable/resolvable at case start", before: nil, requested: nil, observed: nil, restored: nil, collateralChangedPaths: [], writeError: nil, restoreError: nil))
        continue
    }

    var requested: Double? = nil
    let writeError: AXError
    if kind.isNumeric {
        var next = before + 1.0
        if let max = target.candidate.maximum, next > max { next = before - 1.0 }
        if let min = target.candidate.minimum, next < min { next = before + 1.0 }
        if let min = target.candidate.minimum { next = Swift.max(next, min) }
        if let max = target.candidate.maximum { next = Swift.min(next, max) }
        guard abs(next - before) > 1e-9 else {
            skipCount += 1
            cases.append(CaseResult(control: kind.rawValue, stripPath: strip, targetPath: path, result: "SKIP", reason: "no safe adjacent in-range numeric value", before: before, requested: nil, observed: nil, restored: nil, collateralChangedPaths: [], writeError: nil, restoreError: nil))
            continue
        }
        requested = next
        writeError = AX.setNumber(target.element, next)
    } else {
        requested = before == 0 ? 1 : 0
        writeError = AX.press(target.element)
    }

    if writeError != .success {
        failCount += 1
        cases.append(CaseResult(control: kind.rawValue, stripPath: strip, targetPath: path, result: "FAIL", reason: "AX write/action failed before a verified change", before: before, requested: requested, observed: nil, restored: nil, collateralChangedPaths: [], writeError: Int(writeError.rawValue), restoreError: nil))
        continue
    }

    usleep(300_000)
    guard let changedScan = scan(maxDepth: maxDepth, maxNodes: maxNodes) else { exit(30) }
    let after = values(changedScan.refs, kind: kind)
    let observed = after[path]
    let collateral = changedPaths(before: baseline, after: after, excluding: path)
    let changedCorrectly = observed != nil && requested != nil && abs(observed! - requested!) <= 1e-9

    if !changedCorrectly {
        if let currentTarget = resolve(changedScan.refs, path: path) {
            if kind.isNumeric { _ = AX.setNumber(currentTarget.element, before) }
            else if let observed, abs(observed - before) > 1e-9 { _ = AX.press(currentTarget.element) }
        }
        usleep(300_000)
        let restoredScan = scan(maxDepth: maxDepth, maxNodes: maxNodes)
        let restoredValues = restoredScan.map { values($0.refs, kind: kind) } ?? [:]
        let restoredOK = allEqual(baseline, restoredValues)
        if !restoredOK { restoreFailureCount += 1 }
        failCount += 1
        cases.append(CaseResult(control: kind.rawValue, stripPath: strip, targetPath: path, result: restoredOK ? "FAIL" : "RESTORE_FAIL", reason: "write/action returned success but independent rescan did not show the requested target value", before: before, requested: requested, observed: observed, restored: restoredValues[path], collateralChangedPaths: collateral, writeError: Int(writeError.rawValue), restoreError: nil))
        if !restoredOK { break }
        continue
    }

    guard let changedTarget = resolve(changedScan.refs, path: path) else { exit(30) }
    let restoreError: AXError = kind.isNumeric ? AX.setNumber(changedTarget.element, before) : AX.press(changedTarget.element)
    usleep(300_000)
    guard let restoredScan = scan(maxDepth: maxDepth, maxNodes: maxNodes) else { exit(30) }
    let restoredValues = values(restoredScan.refs, kind: kind)
    let restored = restoredValues[path]
    let restoredOK = restoreError == .success && allEqual(baseline, restoredValues)

    if !restoredOK {
        restoreFailureCount += 1
        failCount += 1
        cases.append(CaseResult(control: kind.rawValue, stripPath: strip, targetPath: path, result: "RESTORE_FAIL", reason: "peer set did not return exactly to pre-case state", before: before, requested: requested, observed: observed, restored: restored, collateralChangedPaths: collateral, writeError: Int(writeError.rawValue), restoreError: Int(restoreError.rawValue)))
        break
    }

    if collateral.isEmpty {
        passCount += 1
        cases.append(CaseResult(control: kind.rawValue, stripPath: strip, targetPath: path, result: "PASS", reason: nil, before: before, requested: requested, observed: observed, restored: restored, collateralChangedPaths: [], writeError: Int(writeError.rawValue), restoreError: Int(restoreError.rawValue)))
    } else {
        failCount += 1
        cases.append(CaseResult(control: kind.rawValue, stripPath: strip, targetPath: path, result: "FAIL", reason: "other peer control values changed during target mutation, although restoration succeeded", before: before, requested: requested, observed: observed, restored: restored, collateralChangedPaths: collateral, writeError: Int(writeError.rawValue), restoreError: Int(restoreError.rawValue)))
    }
    print("case=\(index + 1)/\(initialTargets.count) control=\(kind.rawValue) strip=\(strip) result=\(cases.last?.result ?? "unknown")")
}

let matrixResult = MatrixResult(schema: "logic-coproducer-mixer-matrix/1.0", generatedAt: nowISO(), control: kind.rawValue, candidateCount: initialTargets.count, passCount: passCount, failCount: failCount, skipCount: skipCount, restoreFailureCount: restoreFailureCount, cases: cases)
do { try writeJSON(matrixResult, path: out) } catch { fputs("Could not write matrix result: \(error)\n", stderr); exit(6) }
print("control=\(kind.rawValue) candidates=\(initialTargets.count) PASS=\(passCount) FAIL=\(failCount) SKIP=\(skipCount) RESTORE_FAIL=\(restoreFailureCount)")
if restoreFailureCount > 0 { print("RESULT=RESTORE_FAIL"); exit(30) }
if failCount > 0 { print("RESULT=PARTIAL"); exit(0) }
print("RESULT=PASS")
exit(0)
