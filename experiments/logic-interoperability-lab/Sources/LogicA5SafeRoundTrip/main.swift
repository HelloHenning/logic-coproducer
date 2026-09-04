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
    let title: String?
    let identifier: String?
    let elementDescription: String?
    let valueDescription: String?
    let minimum: Double?
    let maximum: Double?
    let enabled: Bool?
    let valueSettable: Bool
}

private struct CandidateRef {
    let candidate: Candidate
    let element: AXUIElement
}

private struct A5RoundTripResult: Codable {
    let schema: String
    let generatedAt: String
    let query: String
    let result: String
    let reason: String?
    let target: Candidate?
    let before: Double?
    let requested: Double?
    let changed: Double?
    let restored: Double?
    let writeError: Int?
    let restoreErrors: [Int]
    let restoreAttempts: [String]
    let restorationVerified: Bool
}

private final class Walker {
    let maxDepth: Int
    let maxNodes: Int
    private var seen: Set<AXIdentity> = []
    private(set) var visited = 0

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

            let candidate = Candidate(
                path: path,
                role: AX.string(element, kAXRoleAttribute),
                title: AX.string(element, kAXTitleAttribute),
                identifier: AX.string(element, kAXIdentifierAttribute),
                elementDescription: AX.string(element, kAXDescriptionAttribute),
                valueDescription: AX.string(element, "AXValueDescription"),
                minimum: AX.number(element, kAXMinValueAttribute),
                maximum: AX.number(element, kAXMaxValueAttribute),
                enabled: AX.bool(element, kAXEnabledAttribute),
                valueSettable: AX.settable(element)
            )
            output.append(CandidateRef(candidate: candidate, element: element))

            guard depth < maxDepth else { continue }
            let role = candidate.role
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
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

private func normalized(_ value: String?) -> String {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func fields(_ candidate: Candidate) -> [String] {
    [candidate.title, candidate.identifier, candidate.elementDescription, candidate.valueDescription].compactMap { $0 }
}

private func matches(_ candidate: Candidate, query: String) -> Bool {
    let q = normalized(query)
    return !q.isEmpty && fields(candidate).contains { normalized($0).contains(q) }
}

private func exactMatches(_ candidate: Candidate, query: String) -> Bool {
    let q = normalized(query)
    return fields(candidate).contains { normalized($0) == q }
}

private func logicRoot() -> AXUIElement? {
    guard AXIsProcessTrusted(),
          let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first
    else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

private func scan(maxDepth: Int, maxNodes: Int) -> [CandidateRef]? {
    guard let root = logicRoot() else { return nil }
    return Walker(maxDepth: maxDepth, maxNodes: maxNodes).all(from: root)
}

private func numericCandidates(_ refs: [CandidateRef], query: String) -> [CandidateRef] {
    refs.filter {
        $0.candidate.role == kAXSliderRole &&
        $0.candidate.enabled != false &&
        $0.candidate.valueSettable &&
        AX.number($0.element) != nil &&
        matches($0.candidate, query: query)
    }
}

private func chooseUnique(_ refs: [CandidateRef], query: String) -> (CandidateRef?, String?) {
    let candidates = numericCandidates(refs, query: query)
    let exact = candidates.filter { exactMatches($0.candidate, query: query) }
    if exact.count == 1 { return (exact[0], nil) }
    if exact.count > 1 { return (nil, "ambiguous exact numeric matches=\(exact.count)") }
    if candidates.count == 1 { return (candidates[0], nil) }
    if candidates.isEmpty { return (nil, "no safe numeric candidate") }
    return (nil, "ambiguous numeric matches=\(candidates.count)")
}

private func resolveFresh(query: String, preferredPath: String, maxDepth: Int, maxNodes: Int) -> CandidateRef? {
    guard let refs = scan(maxDepth: maxDepth, maxNodes: maxNodes) else { return nil }
    let candidates = numericCandidates(refs, query: query)
    if let pathMatch = candidates.first(where: { $0.candidate.path == preferredPath }) { return pathMatch }
    let exact = candidates.filter { exactMatches($0.candidate, query: query) }
    if exact.count == 1 { return exact[0] }
    if candidates.count == 1 { return candidates[0] }
    return nil
}

private func freshValue(query: String, preferredPath: String, maxDepth: Int, maxNodes: Int, retries: Int = 3) -> Double? {
    for attempt in 0..<retries {
        if let ref = resolveFresh(query: query, preferredPath: preferredPath, maxDepth: maxDepth, maxNodes: maxNodes),
           let value = AX.number(ref.element) {
            return value
        }
        if attempt + 1 < retries { usleep(120_000) }
    }
    return nil
}

private func writeJSON(_ result: A5RoundTripResult, path: String?) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(result) else { return }
    if let path {
        try? data.write(to: URL(fileURLWithPath: path))
    } else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

private func finish(_ result: A5RoundTripResult, path: String?, code: Int32) -> Never {
    writeJSON(result, path: path)
    print("RESULT=\(result.result) restoration_verified=\(result.restorationVerified ? "true" : "false") reason=\(result.reason ?? "none")")
    exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())
let query = option("--query", args: args) ?? ""
let out = option("--out", args: args)
let maxDepth = Int(option("--depth", args: args) ?? "22") ?? 22
let maxNodes = Int(option("--max-nodes", args: args) ?? "50000") ?? 50_000
let tolerance = 1e-6

func result(
    _ status: String,
    reason: String?,
    target: Candidate?,
    before: Double?,
    requested: Double?,
    changed: Double?,
    restored: Double?,
    writeError: AXError?,
    restoreErrors: [AXError],
    restoreAttempts: [String],
    restorationVerified: Bool
) -> A5RoundTripResult {
    A5RoundTripResult(
        schema: "logic-coproducer-a5-safe-roundtrip/1.0",
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        query: query,
        result: status,
        reason: reason,
        target: target,
        before: before,
        requested: requested,
        changed: changed,
        restored: restored,
        writeError: writeError.map { Int($0.rawValue) },
        restoreErrors: restoreErrors.map { Int($0.rawValue) },
        restoreAttempts: restoreAttempts,
        restorationVerified: restorationVerified
    )
}

guard !query.isEmpty else {
    finish(result("FAIL", reason: "missing --query", target: nil, before: nil, requested: nil, changed: nil, restored: nil, writeError: nil, restoreErrors: [], restoreAttempts: [], restorationVerified: true), path: out, code: 2)
}
guard AXIsProcessTrusted() else {
    finish(result("FAIL", reason: "Accessibility permission unavailable", target: nil, before: nil, requested: nil, changed: nil, restored: nil, writeError: nil, restoreErrors: [], restoreAttempts: [], restorationVerified: true), path: out, code: 3)
}
guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first != nil else {
    finish(result("FAIL", reason: "Logic Pro is not running", target: nil, before: nil, requested: nil, changed: nil, restored: nil, writeError: nil, restoreErrors: [], restoreAttempts: [], restorationVerified: true), path: out, code: 4)
}
guard let initialRefs = scan(maxDepth: maxDepth, maxNodes: maxNodes) else {
    finish(result("FAIL", reason: "initial AX scan failed", target: nil, before: nil, requested: nil, changed: nil, restored: nil, writeError: nil, restoreErrors: [], restoreAttempts: [], restorationVerified: true), path: out, code: 5)
}

let (selectedMaybe, selectionReason) = chooseUnique(initialRefs, query: query)
guard let selected = selectedMaybe,
      let before = AX.number(selected.element)
else {
    finish(result("SKIP", reason: selectionReason ?? "parameter resolution failed", target: nil, before: nil, requested: nil, changed: nil, restored: nil, writeError: nil, restoreErrors: [], restoreAttempts: [], restorationVerified: true), path: out, code: 10)
}

let minValue = selected.candidate.minimum
let maxValue = selected.candidate.maximum
let step: Double
if let minValue, let maxValue, maxValue > minValue {
    step = max((maxValue - minValue) * 0.05, 0.001)
} else {
    step = abs(before) <= 1.0 ? 0.05 : 1.0
}
var requested = before + step
if let maxValue, requested > maxValue { requested = before - step }
if let minValue { requested = max(requested, minValue) }
if let maxValue { requested = min(requested, maxValue) }
guard abs(requested - before) > 1e-9 else {
    finish(result("SKIP", reason: "could not derive reversible in-range test value", target: selected.candidate, before: before, requested: nil, changed: nil, restored: before, writeError: nil, restoreErrors: [], restoreAttempts: [], restorationVerified: true), path: out, code: 10)
}

let writeError = AX.setNumber(selected.element, requested)
usleep(250_000)
let changed = freshValue(query: query, preferredPath: selected.candidate.path, maxDepth: maxDepth, maxNodes: maxNodes)

var restoreErrors: [AXError] = []
var restoreAttempts: [String] = []
var restored: Double? = nil
var restorationVerified = false

func verifyRestored() -> Bool {
    if let value = freshValue(query: query, preferredPath: selected.candidate.path, maxDepth: maxDepth, maxNodes: maxNodes) {
        restored = value
        return abs(value - before) <= tolerance
    }
    return false
}

if verifyRestored() {
    restorationVerified = true
    restoreAttempts.append("already-at-baseline-after-write-phase")
} else {
    for pass in 1...3 where !restorationVerified {
        if let fresh = resolveFresh(query: query, preferredPath: selected.candidate.path, maxDepth: maxDepth, maxNodes: maxNodes) {
            restoreAttempts.append("fresh-target-pass-\(pass):\(fresh.candidate.path)")
            let err = AX.setNumber(fresh.element, before)
            restoreErrors.append(err)
            usleep(180_000)
            if verifyRestored() {
                restorationVerified = true
                break
            }
        }

        if !restorationVerified {
            restoreAttempts.append("original-element-pass-\(pass)")
            let err = AX.setNumber(selected.element, before)
            restoreErrors.append(err)
            usleep(180_000)
            if verifyRestored() {
                restorationVerified = true
                break
            }
        }
    }
}

if !restorationVerified {
    finish(result("RESTORE_FAIL", reason: "baseline could not be independently reverified after write phase", target: selected.candidate, before: before, requested: requested, changed: changed, restored: restored, writeError: writeError, restoreErrors: restoreErrors, restoreAttempts: restoreAttempts, restorationVerified: false), path: out, code: 30)
}

if writeError != .success {
    finish(result("FAIL", reason: "AXValue write failed; baseline independently verified", target: selected.candidate, before: before, requested: requested, changed: changed, restored: restored, writeError: writeError, restoreErrors: restoreErrors, restoreAttempts: restoreAttempts, restorationVerified: true), path: out, code: 20)
}

guard let changed, abs(changed - before) > 1e-9 else {
    finish(result("FAIL", reason: "write returned success but independent readback did not prove a changed value; baseline independently verified", target: selected.candidate, before: before, requested: requested, changed: changed, restored: restored, writeError: writeError, restoreErrors: restoreErrors, restoreAttempts: restoreAttempts, restorationVerified: true), path: out, code: 21)
}

finish(result("PASS", reason: nil, target: selected.candidate, before: before, requested: requested, changed: changed, restored: restored, writeError: writeError, restoreErrors: restoreErrors, restoreAttempts: restoreAttempts, restorationVerified: true), path: out, code: 0)
