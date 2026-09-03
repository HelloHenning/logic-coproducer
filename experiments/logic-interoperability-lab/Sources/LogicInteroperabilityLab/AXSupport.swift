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

enum AXReader {
    static func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &raw)
        guard error == .success else { return nil }
        return raw
    }

    static func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
        copyAttribute(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        if let value = copyAttribute(element, attribute) as? Bool {
            return value
        }
        if let number = copyAttribute(element, attribute) as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    static func element(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        copyAttribute(element, attribute) as! AXUIElement?
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let raw = copyAttribute(element, kAXChildrenAttribute) else { return [] }
        return raw as? [AXUIElement] ?? []
    }

    static func simpleValue(_ element: AXUIElement) -> String? {
        guard let raw = copyAttribute(element, kAXValueAttribute) else { return nil }
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
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

    private func snapshot(_ element: AXUIElement, depth: Int) -> AXSnapshotNode {
        visitedNodes += 1
        let summary = AXReader.summary(element)

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
        guard visitedNodes < maxNodes else { return }
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
        ("enabled", summary.enabled.map(String.init)),
        ("focused", summary.focused.map(String.init))
    ]

    print(prefix + fields.compactMap { key, value in
        value.map { "\(key)=\($0.debugDescription)" }
    }.joined(separator: "  "))
}
