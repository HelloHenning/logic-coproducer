import Foundation

private struct FixtureNote: Decodable {
    let index: Int
    let startTick: Int
    let lengthTicks: Int
    let channel: Int
    let noteNumber: Int
    let velocity: Int
}

private struct FixtureCounts: Decodable {
    let notes: Int
    let controllers: Int
    let pitchBends: Int
    let channelPressure: Int
    let polyPressure: Int
    let programChanges: Int
    let expectedEventListRows: Int
}

private struct FixtureManifest: Decodable {
    let schema: String
    let fixture: String
    let ppq: Int
    let tempoBPM: Int
    let timeSignature: String
    let counts: FixtureCounts
    let notes: [FixtureNote]
}

private struct ObservedRow: Decodable {
    let index: Int
    let cellCount: Int
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

private struct ObservedDocument: Decodable {
    let schema: String
    let logicVersion: String
    let hydrationMode: String?
    let hydrationSteps: Int?
    let rowsWithPosition: Int?
    let rowsWithChannel: Int?
    let rows: [ObservedRow]
}

private struct ExpectedEvent {
    let tick: Int
    let order: Int
    let status: String
    let channel: Int
    let number: Int?
    let value: Int?
    let lengthTicks: Int?
}

private struct SemanticRow: Codable, Equatable {
    let position: String?
    let status: String?
    let channel: Int?
    let number: Int?
    let value: Int?
    let length: String?
}

private struct Mismatch: Codable {
    let run: Int
    let row: Int?
    let field: String
    let expected: String
    let observed: String
}

private struct RunSummary: Codable {
    let run: Int
    let logicVersion: String
    let rowCount: Int
    let rowsWithPosition: Int
    let rowsWithChannel: Int
    let channels: [Int]
    let goldenMismatchCount: Int
}

private struct CompareReport: Codable {
    let schema: String
    let createdAt: Date
    let result: String
    let manifestPath: String
    let run1Path: String
    let run2Path: String
    let runs: [RunSummary]
    let repeatabilityMismatchCount: Int
    let mismatches: [Mismatch]
    let notes: [String]
}

private enum CompareError: Error, CustomStringConvertible {
    case usage(String)
    case invalid(String)

    var description: String {
        switch self {
        case .usage(let text), .invalid(let text): return text
        }
    }
}

private func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

private func expanded(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
}

private func load<T: Decodable>(_ type: T.Type, path: String) throws -> T {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw CompareError.invalid("Could not read \(path): \(error)")
    }
}

private func trimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func intValue(_ value: String?) -> Int? {
    guard let text = trimmed(value), !text.isEmpty else { return nil }
    return Int(text)
}

private func semanticRows(_ rows: [ObservedRow]) -> [SemanticRow] {
    rows.map { row in
        let status = trimmed(row.status)
        return SemanticRow(
            position: trimmed(row.position),
            status: status,
            channel: intValue(row.channelDescription) ?? intValue(row.channelRaw),
            number: intValue(row.numberRaw),
            value: intValue(row.valueDescription),
            length: status == "Note" ? trimmed(row.length) : nil
        )
    }
}

private func channels(in rows: [ObservedRow]) -> Set<Int> {
    Set(rows.compactMap { intValue($0.channelDescription) ?? intValue($0.channelRaw) })
}

private func positionString(tick: Int, ppq: Int) -> String {
    let ticksPerBar = ppq * 4
    let ticksPerDivision = ppq / 4
    let bar = tick / ticksPerBar + 1
    let inBar = tick % ticksPerBar
    let beat = inBar / ppq + 1
    let inBeat = inBar % ppq
    let division = inBeat / ticksPerDivision + 1
    let subTick = inBeat % ticksPerDivision + 1
    return "\(bar) \(beat) \(division) \(subTick)"
}

private func lengthString(ticks: Int, ppq: Int) -> String {
    let ticksPerBar = ppq * 4
    let ticksPerDivision = ppq / 4
    let bars = ticks / ticksPerBar
    let afterBars = ticks % ticksPerBar
    let beats = afterBars / ppq
    let afterBeats = afterBars % ppq
    let divisions = afterBeats / ticksPerDivision
    let subTicks = afterBeats % ticksPerDivision
    return "\(bars) \(beats) \(divisions) \(subTicks)"
}

private func expectedEvents(manifest: FixtureManifest, selectedChannels: Set<Int>) throws -> [ExpectedEvent] {
    guard manifest.schema == "logic-coproducer-midi-fixture/1.0" else {
        throw CompareError.invalid("Unsupported fixture schema: \(manifest.schema)")
    }
    guard manifest.ppq == 960, manifest.timeSignature == "4/4" else {
        throw CompareError.invalid("The A1 comparator currently qualifies only the PPQ-960, 4/4 golden fixture.")
    }
    guard manifest.counts.notes == 1_024,
          manifest.notes.count == 1_024,
          manifest.counts.controllers == 16,
          manifest.counts.pitchBends == 8,
          manifest.counts.channelPressure == 8,
          manifest.counts.polyPressure == 8,
          manifest.counts.programChanges == 4
    else {
        throw CompareError.invalid("Manifest counts do not match the qualified A1 golden fixture.")
    }
    guard !selectedChannels.isEmpty else {
        throw CompareError.invalid("Could not detect a MIDI channel from the Event List export.")
    }

    var events: [ExpectedEvent] = []

    for channel in selectedChannels.sorted() {
        guard (1...4).contains(channel) else {
            throw CompareError.invalid("Unexpected MIDI channel in Event List: \(channel)")
        }
        events.append(ExpectedEvent(
            tick: 0,
            order: -5 + channel - 1,
            status: "Program",
            channel: channel,
            number: -1,
            value: (channel - 1) * 10,
            lengthTicks: nil
        ))
    }

    for note in manifest.notes where selectedChannels.contains(note.channel) {
        events.append(ExpectedEvent(
            tick: note.startTick,
            order: 20,
            status: "Note",
            channel: note.channel,
            number: note.noteNumber,
            value: note.velocity,
            lengthTicks: note.lengthTicks
        ))
    }

    for fixtureIndex in stride(from: 0, to: 1_024, by: 64) {
        let ordinal = fixtureIndex / 64
        let channel = ordinal % 4 + 1
        guard selectedChannels.contains(channel) else { continue }
        events.append(ExpectedEvent(
            tick: fixtureIndex * 120 + 30,
            order: 10,
            status: "Control",
            channel: channel,
            number: 1 + ordinal % 20,
            value: 10 + (ordinal * 7) % 118,
            lengthTicks: nil
        ))
    }

    let bendValues = [0, 2_048, 4_096, 8_192, 12_288, 14_336, 16_383, 6_144]
    for fixtureIndex in stride(from: 0, to: 1_024, by: 128) {
        let ordinal = fixtureIndex / 128
        let channel = ordinal % 4 + 1
        guard selectedChannels.contains(channel) else { continue }
        let baseTick = fixtureIndex * 120
        let bend = bendValues[ordinal]

        events.append(ExpectedEvent(
            tick: baseTick + 45,
            order: 10,
            status: "PitchBd",
            channel: channel,
            number: bend & 0x7F,
            value: (bend >> 7) & 0x7F,
            lengthTicks: nil
        ))
        events.append(ExpectedEvent(
            tick: baseTick + 60,
            order: 10,
            status: "A-Touch",
            channel: channel,
            number: nil,
            value: 20 + (ordinal * 13) % 108,
            lengthTicks: nil
        ))
        events.append(ExpectedEvent(
            tick: baseTick + 90,
            order: 10,
            status: "P-Touch",
            channel: channel,
            number: 48 + ordinal % 24,
            value: 30 + (ordinal * 11) % 98,
            lengthTicks: nil
        ))
    }

    return events.sorted {
        if $0.tick != $1.tick { return $0.tick < $1.tick }
        return $0.order < $1.order
    }
}

private func compareGolden(
    run: Int,
    document: ObservedDocument,
    manifest: FixtureManifest,
    selectedChannels: Set<Int>
) throws -> [Mismatch] {
    let expected = try expectedEvents(manifest: manifest, selectedChannels: selectedChannels)
    let observed = semanticRows(document.rows)
    var mismatches: [Mismatch] = []

    func append(row: Int?, field: String, expected: String, observed: String) {
        mismatches.append(Mismatch(run: run, row: row, field: field, expected: expected, observed: observed))
    }

    if document.hydrationMode != "scroll-sweep" {
        append(row: nil, field: "hydrationMode", expected: "scroll-sweep", observed: document.hydrationMode ?? "nil")
    }
    if document.rowsWithPosition != document.rows.count {
        append(
            row: nil,
            field: "rowsWithPosition",
            expected: String(document.rows.count),
            observed: document.rowsWithPosition.map(String.init) ?? "nil"
        )
    }
    if document.rowsWithChannel != document.rows.count {
        append(
            row: nil,
            field: "rowsWithChannel",
            expected: String(document.rows.count),
            observed: document.rowsWithChannel.map(String.init) ?? "nil"
        )
    }
    if observed.count != expected.count {
        append(row: nil, field: "rowCount", expected: String(expected.count), observed: String(observed.count))
    }

    for index in 0..<min(observed.count, expected.count) {
        let actual = observed[index]
        let wanted = expected[index]

        func check(_ field: String, _ expected: String?, _ observed: String?) {
            if expected != observed {
                append(row: index, field: field, expected: expected ?? "nil", observed: observed ?? "nil")
            }
        }

        check("position", positionString(tick: wanted.tick, ppq: manifest.ppq), actual.position)
        check("status", wanted.status, actual.status)
        check("channel", String(wanted.channel), actual.channel.map(String.init))
        if let number = wanted.number {
            check("number", String(number), actual.number.map(String.init))
        }
        if let value = wanted.value {
            check("value", String(value), actual.value.map(String.init))
        }
        if let ticks = wanted.lengthTicks {
            check("length", lengthString(ticks: ticks, ppq: manifest.ppq), actual.length)
        }
    }

    return mismatches
}

private func repeatabilityMismatchCount(_ leftDocument: ObservedDocument, _ rightDocument: ObservedDocument) -> Int {
    let left = semanticRows(leftDocument.rows)
    let right = semanticRows(rightDocument.rows)
    var count = abs(left.count - right.count)
    for index in 0..<min(left.count, right.count) where left[index] != right[index] {
        count += 1
    }
    return count
}

private func writeReport(_ report: CompareReport, path: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    try data.write(to: URL(fileURLWithPath: path), options: Data.WritingOptions.atomic)
}

private func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let manifestArg = option("--expected", in: args),
          let run1Arg = option("--run1", in: args),
          let run2Arg = option("--run2", in: args),
          let outArg = option("--out", in: args)
    else {
        throw CompareError.usage(
            "Usage: logic-a1-compare --expected MANIFEST.json --run1 OBSERVED1.json --run2 OBSERVED2.json --out REPORT.json"
        )
    }

    let manifestPath = expanded(manifestArg)
    let run1Path = expanded(run1Arg)
    let run2Path = expanded(run2Arg)
    let outPath = expanded(outArg)

    let manifest = try load(FixtureManifest.self, path: manifestPath)
    let run1 = try load(ObservedDocument.self, path: run1Path)
    let run2 = try load(ObservedDocument.self, path: run2Path)

    let channels1 = channels(in: run1.rows)
    let channels2 = channels(in: run2.rows)
    var mismatches: [Mismatch] = []
    mismatches += try compareGolden(run: 1, document: run1, manifest: manifest, selectedChannels: channels1)
    mismatches += try compareGolden(run: 2, document: run2, manifest: manifest, selectedChannels: channels2)

    if channels1 != channels2 {
        mismatches.append(Mismatch(
            run: 2,
            row: nil,
            field: "detectedChannels",
            expected: channels1.sorted().map(String.init).joined(separator: ","),
            observed: channels2.sorted().map(String.init).joined(separator: ",")
        ))
    }

    let repeatability = repeatabilityMismatchCount(run1, run2)
    let result = mismatches.isEmpty && repeatability == 0 ? "PASS" : "FAIL"

    let summaries = [
        RunSummary(
            run: 1,
            logicVersion: run1.logicVersion,
            rowCount: run1.rows.count,
            rowsWithPosition: run1.rowsWithPosition ?? 0,
            rowsWithChannel: run1.rowsWithChannel ?? 0,
            channels: channels1.sorted(),
            goldenMismatchCount: mismatches.filter { $0.run == 1 }.count
        ),
        RunSummary(
            run: 2,
            logicVersion: run2.logicVersion,
            rowCount: run2.rows.count,
            rowsWithPosition: run2.rowsWithPosition ?? 0,
            rowsWithChannel: run2.rowsWithChannel ?? 0,
            channels: channels2.sorted(),
            goldenMismatchCount: mismatches.filter { $0.run == 2 }.count
        )
    ]

    let report = CompareReport(
        schema: "logic-coproducer-a1-test/1.0",
        createdAt: Date(),
        result: result,
        manifestPath: manifestPath,
        run1Path: run1Path,
        run2Path: run2Path,
        runs: summaries,
        repeatabilityMismatchCount: repeatability,
        mismatches: mismatches,
        notes: [
            "Comparison uses human-readable AX value descriptions for MIDI values because raw AXValue is not a direct MIDI value for several Event List cell types.",
            "Pitch bend is qualified as the Event List's two displayed 7-bit fields: Num=LSB and Val=MSB.",
            "Program/controller descriptive labels are not compared because they are presentation strings rather than MIDI semantics."
        ]
    )
    try writeReport(report, path: outPath)

    print("A1 exact comparison")
    for summary in summaries {
        print(
            "run\(summary.run): rows=\(summary.rowCount) hydrated_position=\(summary.rowsWithPosition)/\(summary.rowCount) " +
            "hydrated_channel=\(summary.rowsWithChannel)/\(summary.rowCount) channels=\(summary.channels.map(String.init).joined(separator: ",")) " +
            "golden_mismatches=\(summary.goldenMismatchCount)"
        )
    }
    print("repeatability_mismatches=\(repeatability)")
    if !mismatches.isEmpty {
        for mismatch in mismatches.prefix(12) {
            print(
                "mismatch run=\(mismatch.run) row=\(mismatch.row.map(String.init) ?? "-") field=\(mismatch.field) " +
                "expected=\(mismatch.expected.debugDescription) observed=\(mismatch.observed.debugDescription)"
            )
        }
        if mismatches.count > 12 {
            print("... \(mismatches.count - 12) additional mismatches; see report JSON")
        }
    }
    print("report=\(outPath)")
    print("RESULT=\(result)")

    if result != "PASS" { exit(6) }
}

do {
    try main()
} catch {
    fputs("logic-a1-compare: \(error)\n", stderr)
    exit(2)
}
