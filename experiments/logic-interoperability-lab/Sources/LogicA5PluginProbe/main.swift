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

    static func number(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> Double? {
        guard let raw = copy(element, attribute) else { return nil }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
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

    static func settable(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> Bool {
        var flag = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &flag) == .success && flag.boolValue
    }

    static func perform(_ element: AXUIElement, action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }

    static func setNumber(_ element: AXUIElement, _ value: Double) -> AXError {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, NSNumber(value: value))
    }

    static func point(_ element: AXUIElement, _ attribute: String = kAXPositionAttribute) -> CGPoint? {
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

    static func titleUIElementText(_ element: AXUIElement) -> String? {
        guard let raw = copy(element, kAXTitleUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let titleElement = raw as! AXUIElement
        let values = [
            string(titleElement, kAXTitleAttribute),
            string(titleElement, kAXDescriptionAttribute),
            simple(titleElement, kAXValueAttribute),
            simple(titleElement, "AXValueDescription")
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.joined(separator: " ")
    }
}

struct Candidate: Codable {
    let path: String
    let role: String?
    let title: String?
    let identifier: String?
    let elementDescription: String?
    let value: String?
    let valueDescription: String?
    let minimum: Double?
    let maximum: Double?
    let enabled: Bool?
    let valueSettable: Bool
    let titleUIElementText: String?
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let actions: [String]
}

struct Ref {
    let candidate: Candidate
    let element: AXUIElement
}

struct ParameterBinding: Codable {
    let name: String
    let label: Candidate?
    let slider: Candidate
    let value: Double
    let minimum: Double?
    let maximum: Double?
    let association: String
    let score: Int
}

struct InventoryResult: Codable {
    let schema: String
    let generatedAt: String
    let result: String
    let reason: String?
    let pluginWindow: Candidate?
    let semanticParameterHits: [String]
    let parameters: [ParameterBinding]
    let actionsPerformed: [String]
    let visitedNodes: Int
}

struct RoundTripResult: Codable {
    let schema: String
    let generatedAt: String
    let query: String
    let result: String
    let reason: String?
    let target: ParameterBinding?
    let before: Double?
    let requested: Double?
    let changed: Double?
    let restored: Double?
    let writeError: Int?
    let restoreErrors: [Int]
    let restoreAttempts: [String]
    let restorationVerified: Bool
    let actionsPerformed: [String]
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
            let point = AX.point(element)
            let size = AX.size(element)
            let candidate = Candidate(
                path: path,
                role: role,
                title: AX.string(element, kAXTitleAttribute),
                identifier: AX.string(element, kAXIdentifierAttribute),
                elementDescription: AX.string(element, kAXDescriptionAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                minimum: AX.number(element, kAXMinValueAttribute),
                maximum: AX.number(element, kAXMaxValueAttribute),
                enabled: AX.bool(element, kAXEnabledAttribute),
                valueSettable: AX.settable(element),
                titleUIElementText: AX.titleUIElementText(element),
                x: point.map { Double($0.x) },
                y: point.map { Double($0.y) },
                width: size.map { Double($0.width) },
                height: size.map { Double($0.height) },
                actions: AX.actions(element)
            )
            output.append(Ref(candidate: candidate, element: element))

            guard depth < maxDepth else { continue }
            if role == kAXMenuBarRole || role == kAXMenuRole { continue }
            for (index, child) in AX.children(element).enumerated().reversed() {
                let childRole = AX.string(child, kAXRoleAttribute) ?? "AXElement"
                stack.append((child, depth + 1, "\(path)/\(childRole)[\(index)]"))
            }
        }
        return output
    }
}

@main
struct LogicA5PluginProbe {
    static let parameterPatterns: [(String, [String])] = [
        ("Stereo Mic A", ["stereo mic a"]),
        ("Stereo Mic B", ["stereo mic b"]),
        ("Mono Mic", ["mono mic"]),
        ("Main Volume", ["main volume"]),
        ("Pedal Noise", ["pedal noise"]),
        ("Key Noise", ["key noise"]),
        ("Release Samples", ["release samples"]),
        ("Sympathetic Resonance", ["sympathetic resonance", "sympathetic resonances", "sympathetic res"])
    ]

    static let pressAction = kAXPressAction as String
    static let showMenuAction = "AXShowMenu"
    static let pickAction = "AXPick"

    static func norm(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func fields(_ candidate: Candidate) -> [String] {
        [candidate.title, candidate.identifier, candidate.elementDescription, candidate.valueDescription, candidate.titleUIElementText]
            .compactMap { $0 }
    }

    static func text(_ candidate: Candidate) -> String {
        fields(candidate).joined(separator: " ").lowercased()
    }

    static func containsPattern(_ candidate: Candidate, patterns: [String]) -> Bool {
        let t = text(candidate)
        return patterns.contains { t.contains($0) }
    }

    static func exactField(_ candidate: Candidate, _ wanted: String) -> Bool {
        let q = norm(wanted)
        return fields(candidate).contains { norm($0) == q }
    }

    static func subtree(_ refs: [Ref], _ prefix: String) -> [Ref] {
        refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") }
    }

    static func parentPath(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    static func grandparentPath(_ path: String) -> String {
        parentPath(parentPath(path))
    }

    static func center(_ candidate: Candidate) -> (x: Double, y: Double)? {
        guard let x = candidate.x, let y = candidate.y, let w = candidate.width, let h = candidate.height else { return nil }
        return (x + w / 2.0, y + h / 2.0)
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
            refs.contains { containsPattern($0.candidate, patterns: patterns) } ? name : nil
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

    static func associationScore(label: Candidate, slider: Candidate, patterns: [String]) -> (score: Int, method: String)? {
        if containsPattern(slider, patterns: patterns) {
            if let linked = slider.titleUIElementText, patterns.contains(where: { norm(linked).contains($0) }) {
                return (180, "AXTitleUIElement")
            }
            return (150, "slider-semantic-field")
        }

        guard let lc = center(label), let sc = center(slider) else { return nil }
        let dy = abs(lc.y - sc.y)
        let labelHeight = label.height ?? 0
        let sliderHeight = slider.height ?? 0
        let tolerance = max(14.0, max(labelHeight, sliderHeight) * 0.85)
        guard dy <= tolerance else { return nil }
        guard sc.x >= lc.x - 20 else { return nil }

        var score = 60
        if parentPath(label.path) == parentPath(slider.path) { score += 70 }
        else if grandparentPath(label.path) == grandparentPath(slider.path) { score += 35 }
        if dy <= 2 { score += 35 }
        else if dy <= 6 { score += 28 }
        else if dy <= 10 { score += 20 }
        else { score += 10 }
        if sc.x > lc.x { score += 10 }
        let dx = abs(sc.x - lc.x)
        if dx < 300 { score += 8 }
        else if dx < 500 { score += 4 }
        return (score, "same-row-geometry")
    }

    static func bindings(in refs: [Ref]) -> [ParameterBinding] {
        let sliders = refs.filter {
            $0.candidate.role == kAXSliderRole &&
            $0.candidate.valueSettable &&
            AX.number($0.element) != nil
        }

        var output: [ParameterBinding] = []
        for (name, patterns) in parameterPatterns {
            let labels = refs.filter {
                $0.candidate.role != kAXSliderRole && containsPattern($0.candidate, patterns: patterns)
            }

            var scored: [(slider: Ref, label: Ref?, score: Int, method: String)] = []
            for slider in sliders {
                if containsPattern(slider.candidate, patterns: patterns) {
                    let method = slider.candidate.titleUIElementText.map { linked in
                        patterns.contains(where: { norm(linked).contains($0) }) ? "AXTitleUIElement" : "slider-semantic-field"
                    } ?? "slider-semantic-field"
                    let score = method == "AXTitleUIElement" ? 180 : 150
                    scored.append((slider, nil, score, method))
                    continue
                }
                for label in labels {
                    if let association = associationScore(label: label.candidate, slider: slider.candidate, patterns: patterns) {
                        scored.append((slider, label, association.score, association.method))
                    }
                }
            }

            var bestByPath: [String: (slider: Ref, label: Ref?, score: Int, method: String)] = [:]
            for item in scored {
                if let existing = bestByPath[item.slider.candidate.path], existing.score >= item.score { continue }
                bestByPath[item.slider.candidate.path] = item
            }
            let ranked = bestByPath.values.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.slider.candidate.path < $1.slider.candidate.path
            }
            guard let best = ranked.first, best.score >= 70 else { continue }
            if ranked.count > 1 && ranked[1].score >= best.score - 6 { continue }
            guard let value = AX.number(best.slider.element) else { continue }
            output.append(ParameterBinding(
                name: name,
                label: best.label?.candidate,
                slider: best.slider.candidate,
                value: value,
                minimum: best.slider.candidate.minimum,
                maximum: best.slider.candidate.maximum,
                association: best.method,
                score: best.score
            ))
        }
        return output.sorted { $0.name < $1.name }
    }

    static func isPercentLike(_ value: String?) -> Bool {
        let raw = norm(value)
        guard raw.hasSuffix("%") else { return false }
        return Double(raw.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)) != nil
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
                ref.candidate.actions.contains(pickAction) || ref.candidate.x != nil
            return menuStructural && actionable
        }
        let menuItems = matches.filter { $0.candidate.role == kAXMenuItemRole }
        return (menuItems.isEmpty ? matches : menuItems).sorted { $0.candidate.path < $1.candidate.path }
    }

    static func clickCenter(_ ref: Ref) -> Bool {
        guard let origin = AX.point(ref.element), let size = AX.size(ref.element), size.width > 2, size.height > 2 else { return false }
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
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) else { return }
        down.post(tap: .cgAnnotatedSessionEventTap)
        usleep(40_000)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    static func openView(_ ref: Ref, actions: inout [String]) -> Bool {
        if ref.candidate.actions.contains(showMenuAction), AX.perform(ref.element, action: showMenuAction) == .success {
            actions.append("opened-View-via-AXShowMenu")
            return true
        }
        if ref.candidate.actions.contains(pressAction), AX.perform(ref.element, action: pressAction) == .success {
            actions.append("opened-View-via-AXPress")
            return true
        }
        if clickCenter(ref) {
            actions.append("opened-View-via-semantic-center-click")
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

    static func ensureControls(actions: inout [String]) -> (plugin: Ref, refs: [Ref], semantic: [String], bindings: [ParameterBinding], visited: Int)? {
        guard let initial = scan(), let plugin = pluginWindow(in: initial.refs) else { return nil }
        let pluginRefs = subtree(initial.refs, plugin.candidate.path)
        let semantic = semanticHits(in: pluginRefs)
        let initialBindings = bindings(in: pluginRefs)
        if semantic.count >= 3 && initialBindings.count >= 3 {
            actions.append("Controls-surface-verified-with-semantic-slider-pairs")
            return (plugin, initial.refs, semantic, initialBindings, initial.visited)
        }

        let views = viewCandidates(window: plugin, refs: initial.refs)
        for view in views.prefix(8) {
            guard openView(view, actions: &actions) else { continue }
            usleep(300_000)
            guard let menu = scan() else { postEscape(); continue }
            let controls = controlsCandidates(in: menu.refs)
            guard controls.count == 1, chooseControls(controls[0], actions: &actions) else {
                postEscape()
                usleep(120_000)
                continue
            }
            usleep(700_000)
            guard let after = scan(), let afterPlugin = pluginWindow(in: after.refs) else { continue }
            let afterRefs = subtree(after.refs, afterPlugin.candidate.path)
            let afterSemantic = semanticHits(in: afterRefs)
            let afterBindings = bindings(in: afterRefs)
            if afterSemantic.count >= 3 && afterBindings.count >= 3 {
                actions.append("Controls-surface-verified-after-switch")
                return (afterPlugin, after.refs, afterSemantic, afterBindings, after.visited)
            }
        }
        return nil
    }

    static func option(_ name: String, args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func writeJSON<T: Encodable>(_ value: T, to path: String?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        if let path { try? data.write(to: URL(fileURLWithPath: path)) }
        else { FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8)) }
    }

    static func freshBinding(query: String, preferredPath: String, retries: Int = 3) -> (ParameterBinding, Ref)? {
        for attempt in 0..<retries {
            if let scanned = scan(), let plugin = pluginWindow(in: scanned.refs) {
                let pluginRefs = subtree(scanned.refs, plugin.candidate.path)
                let mapped = bindings(in: pluginRefs).filter { norm($0.name) == norm(query) }
                if let binding = mapped.first(where: { $0.slider.path == preferredPath }),
                   let ref = pluginRefs.first(where: { $0.candidate.path == binding.slider.path }) {
                    return (binding, ref)
                }
                if mapped.count == 1, let binding = mapped.first,
                   let ref = pluginRefs.first(where: { $0.candidate.path == binding.slider.path }) {
                    return (binding, ref)
                }
            }
            if attempt + 1 < retries { usleep(140_000) }
        }
        return nil
    }

    static func inventory(out: String?) -> Never {
        var actions: [String] = []
        guard AXIsProcessTrusted() else {
            let result = InventoryResult(schema: "logic-coproducer-a5-plugin-inventory/1.0", generatedAt: ISO8601DateFormatter().string(from: Date()), result: "FAIL", reason: "accessibility-unavailable", pluginWindow: nil, semanticParameterHits: [], parameters: [], actionsPerformed: actions, visitedNodes: 0)
            writeJSON(result, to: out); print("RESULT=FAIL reason=accessibility-unavailable"); exit(3)
        }
        guard activateLogic() else {
            let result = InventoryResult(schema: "logic-coproducer-a5-plugin-inventory/1.0", generatedAt: ISO8601DateFormatter().string(from: Date()), result: "FAIL", reason: "logic-not-running", pluginWindow: nil, semanticParameterHits: [], parameters: [], actionsPerformed: actions, visitedNodes: 0)
            writeJSON(result, to: out); print("RESULT=FAIL reason=logic-not-running"); exit(4)
        }
        usleep(200_000)
        guard let ready = ensureControls(actions: &actions) else {
            let result = InventoryResult(schema: "logic-coproducer-a5-plugin-inventory/1.0", generatedAt: ISO8601DateFormatter().string(from: Date()), result: "FAIL", reason: "studio-piano-controls-surface-not-resolved", pluginWindow: nil, semanticParameterHits: [], parameters: [], actionsPerformed: actions, visitedNodes: 0)
            writeJSON(result, to: out); print("RESULT=FAIL reason=studio-piano-controls-surface-not-resolved actions=\(actions.joined(separator: ","))"); exit(20)
        }
        let result = InventoryResult(schema: "logic-coproducer-a5-plugin-inventory/1.0", generatedAt: ISO8601DateFormatter().string(from: Date()), result: "PASS", reason: nil, pluginWindow: ready.plugin.candidate, semanticParameterHits: ready.semantic, parameters: ready.bindings, actionsPerformed: actions, visitedNodes: ready.visited)
        writeJSON(result, to: out)
        print("RESULT=PASS semantic_hits=\(ready.semantic.count) mapped_parameters=\(ready.bindings.count) parameters=\(ready.bindings.map { $0.name.replacingOccurrences(of: " ", with: "_") }.joined(separator: ",")) actions=\(actions.joined(separator: ","))")
        exit(0)
    }

    static func roundtrip(query: String, out: String?) -> Never {
        var actions: [String] = []
        var restoreErrors: [AXError] = []
        var restoreAttempts: [String] = []
        let tolerance = 1e-6

        func finish(_ status: String, reason: String?, target: ParameterBinding?, before: Double?, requested: Double?, changed: Double?, restored: Double?, writeError: AXError?, restorationVerified: Bool, code: Int32) -> Never {
            let result = RoundTripResult(
                schema: "logic-coproducer-a5-plugin-roundtrip/1.0",
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
                restorationVerified: restorationVerified,
                actionsPerformed: actions
            )
            writeJSON(result, to: out)
            print("RESULT=\(status) restoration_verified=\(restorationVerified ? "true" : "false") reason=\(reason ?? "none")")
            exit(code)
        }

        guard !query.isEmpty else { finish("FAIL", reason: "missing-query", target: nil, before: nil, requested: nil, changed: nil, restored: nil, writeError: nil, restorationVerified: true, code: 2) }
        guard AXIsProcessTrusted(), activateLogic() else { finish("FAIL", reason: "environment-unavailable", target: nil, before: nil, requested: nil, changed: nil, restored: nil, writeError: nil, restorationVerified: true, code: 3) }
        usleep(200_000)
        guard let ready = ensureControls(actions: &actions) else { finish("FAIL", reason: "studio-piano-controls-surface-not-resolved", target: nil, before: nil, requested: nil, changed: nil, restored: nil, writeError: nil, restorationVerified: true, code: 5) }
        let matches = ready.bindings.filter { norm($0.name) == norm(query) }
        guard matches.count == 1, let selected = matches.first,
              let selectedRef = subtree(ready.refs, ready.plugin.candidate.path).first(where: { $0.candidate.path == selected.slider.path })
        else { finish("SKIP", reason: "parameter-binding-not-unique", target: nil, before: nil, requested: nil, changed: nil, restored: nil, writeError: nil, restorationVerified: true, code: 10) }

        let before = selected.value
        let step: Double
        if let lo = selected.minimum, let hi = selected.maximum, hi > lo { step = max((hi - lo) * 0.05, 0.001) }
        else { step = abs(before) <= 1 ? 0.05 : 1.0 }
        var requested = before + step
        if let hi = selected.maximum, requested > hi { requested = before - step }
        if let lo = selected.minimum { requested = max(requested, lo) }
        if let hi = selected.maximum { requested = min(requested, hi) }
        guard abs(requested - before) > 1e-9 else { finish("SKIP", reason: "no-reversible-test-value", target: selected, before: before, requested: nil, changed: nil, restored: before, writeError: nil, restorationVerified: true, code: 10) }

        let writeError = AX.setNumber(selectedRef.element, requested)
        usleep(250_000)
        let changed = freshBinding(query: query, preferredPath: selected.slider.path)?.0.value

        var restored: Double? = nil
        var restorationVerified = false
        func verifyRestored() -> Bool {
            if let value = freshBinding(query: query, preferredPath: selected.slider.path)?.0.value {
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
                if let fresh = freshBinding(query: query, preferredPath: selected.slider.path) {
                    restoreAttempts.append("fresh-target-pass-\(pass):\(fresh.0.slider.path)")
                    let error = AX.setNumber(fresh.1.element, before)
                    restoreErrors.append(error)
                    usleep(180_000)
                    if verifyRestored() { restorationVerified = true; break }
                }
                restoreAttempts.append("original-element-pass-\(pass)")
                let error = AX.setNumber(selectedRef.element, before)
                restoreErrors.append(error)
                usleep(180_000)
                if verifyRestored() { restorationVerified = true; break }
            }
        }

        guard restorationVerified else { finish("RESTORE_FAIL", reason: "baseline-could-not-be-independently-reverified", target: selected, before: before, requested: requested, changed: changed, restored: restored, writeError: writeError, restorationVerified: false, code: 30) }
        guard writeError == .success else { finish("FAIL", reason: "AXValue-write-failed-baseline-restored", target: selected, before: before, requested: requested, changed: changed, restored: restored, writeError: writeError, restorationVerified: true, code: 20) }
        guard let changed, abs(changed - before) > 1e-9 else { finish("FAIL", reason: "independent-readback-did-not-prove-change-baseline-restored", target: selected, before: before, requested: requested, changed: changed, restored: restored, writeError: writeError, restorationVerified: true, code: 21) }
        finish("PASS", reason: nil, target: selected, before: before, requested: requested, changed: changed, restored: restored, writeError: writeError, restorationVerified: true, code: 0)
    }

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            fputs("Usage: logic-a5-plugin-probe inventory|roundtrip [--query NAME] [--out PATH]\n", stderr)
            exit(2)
        }
        let out = option("--out", args: args)
        if command == "inventory" { inventory(out: out) }
        if command == "roundtrip" { roundtrip(query: option("--query", args: args) ?? "", out: out) }
        fputs("Unknown command: \(command)\n", stderr)
        exit(2)
    }
}
