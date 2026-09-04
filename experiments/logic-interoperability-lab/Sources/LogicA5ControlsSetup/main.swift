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

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func simple(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> String? {
        guard let raw = copy(element, attribute) else { return nil }
        if let value = raw as? String { return value }
        if let value = raw as? NSNumber { return value.stringValue }
        return nil
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let raw = copy(element, attribute) else { return nil }
        if let value = raw as? Bool { return value }
        if let value = raw as? NSNumber { return value.boolValue }
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

    static func perform(_ element: AXUIElement, action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
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
    let actions: [String]
}

struct Ref {
    let candidate: Candidate
    let element: AXUIElement
}

struct ControlsEvidence: Codable {
    let schema: String
    let generatedAt: String
    let result: String
    let reason: String?
    let pluginWindow: Candidate?
    let semanticParameterHitsBefore: [String]
    let numericParameterHitsBefore: [String]
    let semanticParameterHitsAfter: [String]
    let numericParameterHitsAfter: [String]
    let viewCandidates: [Candidate]
    let controlsMenuCandidates: [Candidate]
    let actionsPerformed: [String]
    let visitedNodes: Int
}

final class Walker {
    let maxDepth: Int
    let maxNodes: Int
    private var seen: Set<AXIdentity> = []
    private(set) var visited = 0

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
            let candidate = Candidate(
                path: path,
                role: role,
                title: AX.string(element, kAXTitleAttribute),
                elementDescription: AX.string(element, kAXDescriptionAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                enabled: AX.bool(element, kAXEnabledAttribute),
                visible: AX.bool(element, "AXVisible"),
                actions: AX.actions(element)
            )
            output.append(Ref(candidate: candidate, element: element))

            guard depth < maxDepth else { continue }
            for (index, child) in AX.children(element).enumerated().reversed() {
                let childRole = AX.string(child, kAXRoleAttribute) ?? "AXElement"
                stack.append((child, depth + 1, "\(path)/\(childRole)[\(index)]"))
            }
        }
        return output
    }
}

@main
struct LogicA5ControlsSetup {
    static let parameterPatterns: [(String, [String])] = [
        ("Stereo Mic A", ["stereo mic a"]),
        ("Stereo Mic B", ["stereo mic b"]),
        ("Mono Mic", ["mono mic"]),
        ("Main Volume", ["main volume"]),
        ("Pedal Noise", ["pedal noise"]),
        ("Key Noise", ["key noise"]),
        ("Release Samples", ["release samples"]),
        ("Sympathetic Resonance", ["sympathetic resonance", "sympathetic res"])
    ]

    static let pressAction = kAXPressAction as String
    static let showMenuAction = "AXShowMenu"
    static let pickAction = "AXPick"

    static func norm(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func fields(_ candidate: Candidate) -> [String] {
        [candidate.title, candidate.elementDescription, candidate.value, candidate.valueDescription].compactMap { $0 }
    }

    static func text(_ candidate: Candidate) -> String {
        fields(candidate).joined(separator: " ").lowercased()
    }

    static func exactField(_ candidate: Candidate, _ wanted: String) -> Bool {
        let q = norm(wanted)
        return fields(candidate).contains { norm($0) == q }
    }

    static func subtree(_ refs: [Ref], _ prefix: String) -> [Ref] {
        refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") }
    }

    static func scan() -> (refs: [Ref], visited: Int)? {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first
        else { return nil }
        let walker = Walker()
        let refs = walker.all(from: AXUIElementCreateApplication(app.processIdentifier))
        return (refs, walker.visited)
    }

    static func activateLogic() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { return false }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    static func semanticHits(in refs: [Ref]) -> [String] {
        parameterPatterns.compactMap { name, patterns in
            refs.contains { ref in patterns.contains { text(ref.candidate).contains($0) } } ? name : nil
        }
    }

    static func numericHits(in refs: [Ref]) -> [String] {
        parameterPatterns.compactMap { name, patterns in
            let found = refs.contains { ref in
                guard ref.candidate.role == kAXSliderRole,
                      AX.isSettable(ref.element, kAXValueAttribute)
                else { return false }
                return patterns.contains { text(ref.candidate).contains($0) }
            }
            return found ? name : nil
        }
    }

    static func pluginWindow(in refs: [Ref]) -> Ref? {
        let windows = refs.filter { $0.candidate.role == kAXWindowRole }
        let scored = windows.compactMap { window -> (Ref, Int)? in
            let descendants = subtree(refs, window.candidate.path)
            let semanticCount = semanticHits(in: descendants).count
            let canonical = text(window.candidate).contains("studio piano") ||
                descendants.contains { text($0.candidate).contains("studio piano") }
            guard canonical || semanticCount >= 3 else { return nil }
            var score = semanticCount * 2
            if canonical { score += 12 }
            return (window, score)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.candidate.path < $1.0.candidate.path
        }
        guard let first = scored.first else { return nil }
        if scored.count > 1 && scored[1].1 == first.1 { return nil }
        return first.0
    }

    static func isPercentLike(_ value: String?) -> Bool {
        let raw = norm(value)
        guard raw.hasSuffix("%") else { return false }
        let number = raw.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(number) != nil
    }

    static func viewCandidates(window: Ref, refs: [Ref]) -> [Ref] {
        let acceptedRoles = Set([kAXPopUpButtonRole as String, kAXButtonRole as String, "AXMenuButton"])
        return subtree(refs, window.candidate.path).compactMap { ref -> (Ref, Int)? in
            guard let role = ref.candidate.role, acceptedRoles.contains(role) else { return nil }
            let t = text(ref.candidate)
            var score = 0
            if t.contains("view") { score += 10 }
            if fields(ref.candidate).contains(where: { isPercentLike($0) }) { score += 8 }
            if t.contains("editor") || t.contains("controls") { score += 6 }
            if ref.candidate.actions.contains(showMenuAction) { score += 4 }
            if ref.candidate.actions.contains(pressAction) { score += 3 }
            if role == kAXPopUpButtonRole as String || role == "AXMenuButton" { score += 2 }
            if ref.candidate.visible != false { score += 1 }
            guard score >= 6 else { return nil }
            return (ref, score)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.candidate.path < $1.0.candidate.path
        }.map { $0.0 }
    }

    static func controlsCandidates(in refs: [Ref]) -> [Ref] {
        let matches = refs.filter { ref in
            guard exactField(ref.candidate, "Controls") else { return false }
            let menuStructural = ref.candidate.role == kAXMenuItemRole || ref.candidate.path.contains("/AXMenu[")
            let actionable = ref.candidate.actions.contains(pressAction) ||
                ref.candidate.actions.contains(pickAction) ||
                ref.candidate.visible != false
            return menuStructural && actionable
        }

        let visible = matches.filter { $0.candidate.visible != false }
        let pool = visible.isEmpty ? matches : visible
        let menuItems = pool.filter { $0.candidate.role == kAXMenuItemRole }
        return (menuItems.isEmpty ? pool : menuItems).sorted { $0.candidate.path < $1.candidate.path }
    }

    static func clickCenter(_ ref: Ref) -> Bool {
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

    static func postEscape() {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)
        else { return }
        down.post(tap: .cgAnnotatedSessionEventTap)
        usleep(40_000)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    static func openViewControl(_ ref: Ref, actions: inout [String]) -> Bool {
        if ref.candidate.actions.contains(showMenuAction), AX.perform(ref.element, action: showMenuAction) == .success {
            actions.append("opened-view-control-via-AXShowMenu")
            return true
        }
        if ref.candidate.actions.contains(pressAction), AX.perform(ref.element, action: pressAction) == .success {
            actions.append("opened-view-control-via-AXPress")
            return true
        }
        if clickCenter(ref) {
            actions.append("opened-view-control-via-semantic-center-click")
            return true
        }
        return false
    }

    static func chooseControls(_ ref: Ref, actions: inout [String]) -> Bool {
        if ref.candidate.actions.contains(pressAction), AX.perform(ref.element, action: pressAction) == .success {
            actions.append("selected-Controls-via-AXPress")
            return true
        }
        if ref.candidate.actions.contains(pickAction), AX.perform(ref.element, action: pickAction) == .success {
            actions.append("selected-Controls-via-AXPick")
            return true
        }
        if clickCenter(ref) {
            actions.append("selected-Controls-via-semantic-center-click")
            return true
        }
        return false
    }

    static func option(_ name: String, args: [String]) -> String? {
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func writeEvidence(_ evidence: ControlsEvidence, path: String?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(evidence) else { return }
        if let path { try? data.write(to: URL(fileURLWithPath: path)) }
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let out = option("--out", args: args)
        var actions: [String] = []
        var visited = 0
        var windowCandidate: Candidate?
        var beforeSemantic: [String] = []
        var beforeNumeric: [String] = []
        var afterSemantic: [String] = []
        var afterNumeric: [String] = []
        var recordedViewCandidates: [Candidate] = []
        var recordedControlsCandidates: [Candidate] = []

        func finish(_ result: String, reason: String?, code: Int32) -> Never {
            let evidence = ControlsEvidence(
                schema: "logic-coproducer-a5-controls-setup/1.0",
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                result: result,
                reason: reason,
                pluginWindow: windowCandidate,
                semanticParameterHitsBefore: beforeSemantic,
                numericParameterHitsBefore: beforeNumeric,
                semanticParameterHitsAfter: afterSemantic,
                numericParameterHitsAfter: afterNumeric,
                viewCandidates: recordedViewCandidates,
                controlsMenuCandidates: recordedControlsCandidates,
                actionsPerformed: actions,
                visitedNodes: visited
            )
            writeEvidence(evidence, path: out)
            print("RESULT=\(result) reason=\(reason ?? "none") semantic_before=\(beforeSemantic.count) numeric_before=\(beforeNumeric.count) semantic_after=\(afterSemantic.count) numeric_after=\(afterNumeric.count) view_candidates=\(recordedViewCandidates.count) controls_candidates=\(recordedControlsCandidates.count) actions=\(actions.joined(separator: ","))")
            exit(code)
        }

        guard AXIsProcessTrusted() else { finish("FAIL", reason: "accessibility-unavailable", code: 3) }
        guard activateLogic() else { finish("FAIL", reason: "logic-not-running", code: 4) }
        usleep(250_000)
        guard let initial = scan(), let plugin = pluginWindow(in: initial.refs) else {
            finish("FAIL", reason: "studio-piano-window-not-resolved", code: 20)
        }
        visited = initial.visited
        windowCandidate = plugin.candidate
        let pluginRefs = subtree(initial.refs, plugin.candidate.path)
        beforeSemantic = semanticHits(in: pluginRefs)
        beforeNumeric = numericHits(in: pluginRefs)

        if beforeSemantic.count >= 3 && !beforeNumeric.isEmpty {
            afterSemantic = beforeSemantic
            afterNumeric = beforeNumeric
            actions.append("Controls-already-exposes-settable-semantic-sliders")
            finish("PASS", reason: nil, code: 0)
        }

        let views = viewCandidates(window: plugin, refs: initial.refs)
        recordedViewCandidates = Array(views.prefix(12).map { $0.candidate })
        guard !views.isEmpty else {
            finish("FAIL", reason: "view-control-not-semantically-resolved", code: 21)
        }

        for view in views.prefix(8) {
            guard openViewControl(view, actions: &actions) else { continue }
            usleep(350_000)

            guard let menuScan = scan() else {
                postEscape()
                usleep(120_000)
                continue
            }
            visited = max(visited, menuScan.visited)
            let controls = controlsCandidates(in: menuScan.refs)
            recordedControlsCandidates.append(contentsOf: controls.prefix(12).map { $0.candidate })

            guard controls.count == 1 else {
                actions.append("Controls-menu-candidate-count=\(controls.count)")
                postEscape()
                usleep(120_000)
                continue
            }

            guard chooseControls(controls[0], actions: &actions) else {
                postEscape()
                usleep(120_000)
                continue
            }
            usleep(800_000)

            guard let afterScan = scan(), let afterPlugin = pluginWindow(in: afterScan.refs) else {
                actions.append("Studio-Piano-window-not-resolved-after-Controls-selection")
                continue
            }
            visited = max(visited, afterScan.visited)
            let afterRefs = subtree(afterScan.refs, afterPlugin.candidate.path)
            afterSemantic = semanticHits(in: afterRefs)
            afterNumeric = numericHits(in: afterRefs)
            if afterSemantic.count >= 3 && !afterNumeric.isEmpty {
                finish("PASS", reason: nil, code: 0)
            }
            actions.append("Controls-selection-did-not-expose-semantic-sliders")
        }

        finish("FAIL", reason: "controls-view-not-verified", code: 22)
    }
}
