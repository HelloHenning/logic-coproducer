import Foundation

private struct Snapshot: Decodable {
    let rows: [RawRow]
}

private struct RawRow: Decodable {
    let position: String?
    let status: String?
    let channelRaw: String?
    let channelDescription: String?
    let numberRaw: String?
    let numberDescription: String?
    let valueRaw: String?
    let valueDescription: String?
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
        lhs.sortKey < rhs.sortKey
    }

    private var sortKey: String {
        [position, status, channel, numberRaw, numberDescription, valueRaw, valueDescription, length]
            .joined(separator: "\u{1f}")
    }
}

private struct DiffResult: Codable {
    let schema: String
    let generatedAt: String
    let preCount: Int
    let postCount: Int
    let removedCount: Int
    let addedCount: Int
    let removed: [CanonicalRow]
    let added: [CanonicalRow]
    let result: String
}

private struct Plan: Codable {
    let schema: String
    let label: String
    let removed: [CanonicalRow]
    let added: [CanonicalRow]
}

private func option(_ name: String, args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

private func normalizeWhitespace(_ value: String?) -> String {
    (value ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func canonical(_ row: RawRow) -> CanonicalRow {
    CanonicalRow(
        position: normalizeWhitespace(row.position),
        status: normalizeWhitespace(row.status),
        channel: normalizeWhitespace(row.channelDescription ?? row.channelRaw),
        numberRaw: normalizeWhitespace(row.numberRaw),
        numberDescription: normalizeWhitespace(row.numberDescription),
        valueRaw: normalizeWhitespace(row.valueRaw),
        valueDescription: normalizeWhitespace(row.valueDescription),
        length: normalizeWhitespace(row.length)
    )
}

private func load<T: Decodable>(_ type: T.Type, path: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

private func write<T: Encodable>(_ value: T, path: String?) throws {
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

private func multisetDifference(_ lhs: [CanonicalRow], _ rhs: [CanonicalRow]) -> [CanonicalRow] {
    var counts: [CanonicalRow: Int] = [:]
    for row in rhs { counts[row, default: 0] += 1 }
    var output: [CanonicalRow] = []
    for row in lhs {
        let count = counts[row, default: 0]
        if count > 0 {
            counts[row] = count - 1
        } else {
            output.append(row)
        }
    }
    return output.sorted()
}

private func nowISO() -> String {
    ISO8601DateFormatter().string(from: Date())
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fputs("Usage: logic-blind-diff compare --pre PRE --post POST [--out FILE] | verify --diff DIFF --plan PLAN\n", stderr)
    exit(2)
}

switch command {
case "compare":
    guard let prePath = option("--pre", args: args), let postPath = option("--post", args: args) else {
        fputs("compare requires --pre and --post.\n", stderr)
        exit(2)
    }
    do {
        let pre = try load(Snapshot.self, path: prePath)
        let post = try load(Snapshot.self, path: postPath)
        let preRows = pre.rows.map(canonical)
        let postRows = post.rows.map(canonical)
        let removed = multisetDifference(preRows, postRows)
        let added = multisetDifference(postRows, preRows)
        let resultName = removed.isEmpty && added.isEmpty ? "EQUAL" : "CHANGED"
        let result = DiffResult(
            schema: "logic-coproducer-blind-diff/1.0",
            generatedAt: nowISO(),
            preCount: preRows.count,
            postCount: postRows.count,
            removedCount: removed.count,
            addedCount: added.count,
            removed: removed,
            added: added,
            result: resultName
        )
        try write(result, path: option("--out", args: args))
        print("RESULT=\(resultName) removed=\(removed.count) added=\(added.count)")
    } catch {
        fputs("Blind diff failed: \(error)\n", stderr)
        exit(5)
    }

case "verify":
    guard let diffPath = option("--diff", args: args), let planPath = option("--plan", args: args) else {
        fputs("verify requires --diff and --plan.\n", stderr)
        exit(2)
    }
    do {
        let diff = try load(DiffResult.self, path: diffPath)
        let plan = try load(Plan.self, path: planPath)
        let removedOK = diff.removed.sorted() == plan.removed.sorted()
        let addedOK = diff.added.sorted() == plan.added.sorted()
        if removedOK && addedOK {
            print("RESULT=PASS label=\(plan.label) removed=\(diff.removedCount) added=\(diff.addedCount)")
        } else {
            print("RESULT=FAIL label=\(plan.label) expected_removed=\(plan.removed.count) observed_removed=\(diff.removedCount) expected_added=\(plan.added.count) observed_added=\(diff.addedCount)")
            exit(20)
        }
    } catch {
        fputs("Diff verification failed: \(error)\n", stderr)
        exit(5)
    }

case "assert-equal":
    guard let prePath = option("--pre", args: args), let postPath = option("--post", args: args) else {
        fputs("assert-equal requires --pre and --post.\n", stderr)
        exit(2)
    }
    do {
        let pre = try load(Snapshot.self, path: prePath).rows.map(canonical)
        let post = try load(Snapshot.self, path: postPath).rows.map(canonical)
        let removed = multisetDifference(pre, post)
        let added = multisetDifference(post, pre)
        if removed.isEmpty && added.isEmpty {
            print("RESULT=PASS equal rows=\(pre.count)")
        } else {
            print("RESULT=FAIL removed=\(removed.count) added=\(added.count)")
            exit(20)
        }
    } catch {
        fputs("Equality check failed: \(error)\n", stderr)
        exit(5)
    }

case "row-plan":
    // Utility used by evidence tooling: derive a one-row plan directly from two
    // authoritative snapshots. This is intentionally separate from `compare` so
    // the observer can first produce a blind diff without mutation intent.
    guard let prePath = option("--pre", args: args), let postPath = option("--post", args: args), let label = option("--label", args: args) else {
        fputs("row-plan requires --pre, --post, and --label.\n", stderr)
        exit(2)
    }
    do {
        let pre = try load(Snapshot.self, path: prePath).rows.map(canonical)
        let post = try load(Snapshot.self, path: postPath).rows.map(canonical)
        let removed = multisetDifference(pre, post)
        let added = multisetDifference(post, pre)
        let plan = Plan(schema: "logic-coproducer-external-actor-plan/1.0", label: label, removed: removed, added: added)
        try write(plan, path: option("--out", args: args))
        print("RESULT=PLAN removed=\(removed.count) added=\(added.count)")
    } catch {
        fputs("Plan derivation failed: \(error)\n", stderr)
        exit(5)
    }

default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(2)
}
