import Foundation

struct Export: Decodable {
    let rows: [Row]
}

struct Row: Codable, Equatable {
    let index: Int
    let cellCount: Int
    let lock: String?
    let muted: String?
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

func option(_ name: String, args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func load(_ path: String) throws -> Export {
    try JSONDecoder().decode(Export.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

func normalized(_ value: String?) -> String {
    (value ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

let args = Array(CommandLine.arguments.dropFirst())
guard let prePath = option("--pre", args: args),
      let postPath = option("--post", args: args)
else {
    fputs("Usage: logic-a2-compare --pre PRE.json --post POST.json [--mode mutation|restore] [--position '1 1 1 1'] [--channel 1] [--from 61] [--to 62] [--velocity 20]\n", stderr)
    exit(2)
}

let mode = option("--mode", args: args) ?? "mutation"
let expectedPosition = normalized(option("--position", args: args) ?? "1 1 1 1")
let expectedChannel = option("--channel", args: args) ?? "1"
let expectedFrom = option("--from", args: args) ?? "61"
let expectedTo = option("--to", args: args) ?? "62"
let expectedVelocity = option("--velocity", args: args) ?? "20"

let pre: Export
let post: Export
do {
    pre = try load(prePath)
    post = try load(postPath)
} catch {
    fputs("Could not decode A2 evidence: \(error)\n", stderr)
    exit(3)
}

guard pre.rows.count == post.rows.count else {
    fputs("Row count changed: pre=\(pre.rows.count) post=\(post.rows.count)\n", stderr)
    exit(4)
}

let diffs = pre.rows.indices.filter { pre.rows[$0] != post.rows[$0] }
print("mode=\(mode) rows=\(pre.rows.count) differing_rows=\(diffs.count)")

if mode == "restore" {
    if diffs.isEmpty {
        print("RESULT=PASS")
        exit(0)
    }
    fputs("Restored state differs at row indices: \(diffs.prefix(12).map(String.init).joined(separator: ","))\n", stderr)
    exit(5)
}

guard mode == "mutation" else {
    fputs("Unknown mode: \(mode)\n", stderr)
    exit(2)
}

guard diffs.count == 1, let index = diffs.first else {
    fputs("Expected exactly one changed row; got \(diffs.count).\n", stderr)
    exit(6)
}

let a = pre.rows[index]
let b = post.rows[index]
let aChannel = a.channelDescription ?? a.channelRaw
let bChannel = b.channelDescription ?? b.channelRaw

let targetIdentityOK = normalized(a.position) == expectedPosition &&
    normalized(b.position) == expectedPosition &&
    a.status == "Note" && b.status == "Note" &&
    aChannel == expectedChannel && bChannel == expectedChannel &&
    a.valueDescription == expectedVelocity && b.valueDescription == expectedVelocity &&
    a.numberRaw == expectedFrom && b.numberRaw == expectedTo

guard targetIdentityOK else {
    fputs("The single changed row is not the requested target: position=\(expectedPosition) channel=\(expectedChannel) velocity=\(expectedVelocity) pitch=\(expectedFrom)->\(expectedTo).\n", stderr)
    exit(7)
}

// Verify every field except note number/description stayed identical.
let unrelatedFieldsEqual =
    a.index == b.index &&
    a.cellCount == b.cellCount &&
    a.lock == b.lock &&
    a.muted == b.muted &&
    a.position == b.position &&
    a.status == b.status &&
    a.channelRaw == b.channelRaw &&
    a.channelDescription == b.channelDescription &&
    a.valueRaw == b.valueRaw &&
    a.valueDescription == b.valueDescription &&
    a.valueMinimum == b.valueMinimum &&
    a.valueMaximum == b.valueMaximum &&
    a.length == b.length

guard unrelatedFieldsEqual else {
    fputs("Target row changed in fields other than note number/description.\n", stderr)
    exit(8)
}

print("changed_row=\(index) position=\(expectedPosition) number=\(a.numberRaw ?? "nil")->\(b.numberRaw ?? "nil") desc=\(a.numberDescription ?? "nil")->\(b.numberDescription ?? "nil")")
print("RESULT=PASS")
