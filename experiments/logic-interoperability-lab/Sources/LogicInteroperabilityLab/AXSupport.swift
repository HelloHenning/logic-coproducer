import ApplicationServices
import Foundation

struct AXElementSummary: Codable {
    let role: String?
    let subrole: String?
    let title: String?
    let identifier: String?
    let elementDescription: String?
    let value: String?
    let enabled: Bool?
    let focused: Bool?

    var searchableText: String {
        [role, subrole, title, identifier, elementDescription, value]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

struct AXSnapshotNode: Codable {
    let summary: AXElementSummary
    let children: [AXSnapshotNode]
}

struct AXMatch {
    let path: String
    let summary: AXElementSummary
}

private struct AXElementIdentity: Hashable {
    let element: AXUIElement

    static func == (lhs: AXElementIdentity, rhs: AXElementIdentity) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

enum AXReader {
    // Newer Swift/macOS SDKs import the AX attribute constants as String.
    // Keep that type at our boundary and bridge only for the C API call.
    static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
        guard error == .success else { return nil }
        return raw
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let raw = copyAttribute(element, attribute) else { return nil }
        if let value = raw as? Bool { return value }
        if let number = raw as? NSNumber { return number.boolValue }
        return nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copyAttribute(element, attribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID()
        else {
            return nil
        }

        // CFTypeRef is intentionally untyped at the API boundary. The type-ID
        // check above makes this cast qualified rather than assuming every AX
        // attribute contains another AXUIElement.
        return (raw as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let raw = copyAttribute(element, attribute) else { return [] }
        return raw as? [AXUIElement] ?? []
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        // Logic can transiently expose an AXApplication as one of its own
        // children. Filter direct self-links here so specialized traversals
        // that do not use AXWalker cannot recurse forever.
        elements(element, kAXChildrenAttribute).filter { !CFEqual($0, element) }
    }

    static func simpleValue(_ element: AXUIElement, attribute: String = kAXValueAttribute) -> String? {
        guard let raw = copyAttribute(element, attribute) else { return nil }
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }

    static func doubleValue(_ element: AXUIElement, attribute: String = kAXValueAttribute) -> Double? {
        guard let raw = copyAttribute(element, attribute) else { return nil }
        if let number = raw as? NSNumber { return number.doubleValue }
        if let string = raw as? String { return Double(string) }
        return nil
    }

    static func valueDescription(_ element: AXUIElement) -> String? {
        simpleValue(element, attribute: "AXValueDescription")
    }

    static func isAttributeSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    @discardableResult
    static func setNumber(_ element: AXUIElement, _ value: Double, attribute: String = kAXValueAttribute) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, NSNumber(value: value))
    }

    static func summary(_ element: AXUIElement) -> AXElementSummary {
        AXElementSummary(
            role: string(element, kAXRoleAttribute),
            subrole: string(element, kAXSubroleAttribute),
            title: string(element, kAXTitleAttribute),
            identifier: string(element, kAXIdentifierAttribute),
            elementDescription: string(element, kAXDescriptionAttribute),
            value: simpleValue(element),
            enabled: bool(element, kAXEnabledAttribute),
            focused: bool(element, kAXFocusedAttribute)
        )
    }
}

final class AXWalker {
    let maxDepth: Int
    let maxNodes: Int
    private(set) var visitedNodes = 0
    private var seenElements: Set<AXElementIdentity> = []

    init(maxDepth: Int, maxNodes: Int) {
        self.maxDepth = max(0, maxDepth)
        self.maxNodes = max(1, maxNodes)
    }

    func snapshot(_ element: AXUIElement) -> AXSnapshotNode {
        snapshot(element, depth: 0)
    }

    func find(_ element: AXUIElement, query: String) -> [AXMatch] {
        var matches: [AXMatch] = []
        let needle = query.lowercased()
        find(element, query: needle, depth: 0, path: "app", matches: &matches)
        return matches
    }

    private func firstVisit(_ element: AXUIElement) -> Bool {
        seenElements.insert(AXElementIdentity(element: element)).inserted
    }

    private func snapshot(_ element: AXUIElement, depth: Int) -> AXSnapshotNode {
        let summary = AXReader.summary(element)
        guard firstVisit(element) else {
            return AXSnapshotNode(summary: summary, children: [])
        }

        visitedNodes += 1
        guard depth < maxDepth, visitedNodes < maxNodes else {
            return AXSnapshotNode(summary: summary, children: [])
        }

        var nodes: [AXSnapshotNode] = []
        for child in AXReader.children(element) {
            guard visitedNodes < maxNodes else { break }
            nodes.append(snapshot(child, depth: depth + 1))
        }

        return AXSnapshotNode(summary: summary, children: nodes)
    }

    private func find(
        _ element: AXUIElement,
        query: String,
        depth: Int,
        path: String,
        matches: inout [AXMatch]
    ) {
        guard visitedNodes < maxNodes, firstVisit(element) else { return }
        visitedNodes += 1

        let summary = AXReader.summary(element)
        if summary.searchableText.lowercased().contains(query) {
            matches.append(AXMatch(path: path, summary: summary))
        }

        guard depth < maxDepth else { return }

        for (index, child) in AXReader.children(element).enumerated() {
            guard visitedNodes < maxNodes else { break }
            let role = AXReader.string(child, kAXRoleAttribute) ?? "AXElement"
            let childPath = "\(path)/\(role)[\(index)]"
            find(child, query: query, depth: depth + 1, path: childPath, matches: &matches)
        }
    }
}

func printSummary(_ summary: AXElementSummary, prefix: String = "") {
    let fields: [(String, String?)] = [
        ("role", summary.role),
        ("subrole", summary.subrole),
        ("title", summary.title),
        ("identifier", summary.identifier),
        ("description", summary.elementDescription),
        ("value", summary.value),
        ("enabled", summary.enabled.map { String($0) }),
        ("focused", summary.focused.map { String($0) })
    ]

    let rendered = fields.compactMap { key, value in
        value.map { "\(key)=\($0.debugDescription)" }
    }.joined(separator: "  ")

    print(prefix + rendered)
}
