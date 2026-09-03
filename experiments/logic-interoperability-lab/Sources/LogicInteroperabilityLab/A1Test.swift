import Foundation

struct A1FixtureNote: Decodable {
    let index: Int
    let startTick: Int
    let lengthTicks: Int
    let channel: Int
    let noteNumber: Int
    let velocity: Int
}

struct A1FixtureCounts: Decodable {
    let notes: Int
    let controllers: Int
    let pitchBends: Int
    let channelPressure: Int
    let polyPressure: Int
    let programChanges: Int
    let expectedEventListRows: Int
}

struct A1FixtureManifest: Decodable {
    let schema: String
    let fixture: String
    let ppq: Int
    let tempoBPM: Int
    let timeSignature: String
    let counts: A1FixtureCounts
    let notes: [A1FixtureNote]
}

struct A1ExpectedEvent {
    let tick: Int
    let order: Int
    let status: String
    let channel: Int
    let number: Int?
    let value: Int?
    let lengthTicks: Int?
}

struct A1SemanticRow: Codable, Equatable {
    let position: String?
    let status: String?
    let channel: Int?
    let number: Int?
    let value: Int?
    let length: String?
}

struct A1Mismatch: Codable {
    let row: Int?
    let field: String
    let expected: String
    let observed: String
}

struct A1RunSummary: Codable {
    let run: Int
    let rowCount: Int
    let rowsWithPosition: Int
    let rowsWithChannel: Int
    let channels: [Int]
    let goldenMismatchCount: Int
    let hydrationStatusMismatchCount: Int
    let scrollRestoreVerified: Bool
    let observedFile: String
}

struct A1TestReport: Codable {
    let schema: String
    let capturedAt: Date
    let logicVersion: String
    let manifestPath: String
    let result: String
    let runs: [A1RunSummary]
    let repeatabilityMismatchCount: Int
    let goldenMismatches: [A1Mismatch]
    let notes: [String]
}

enum A1TestError: Error, CustomStringConvertible {
    case unreadableManifest(String)
    case unsupportedFixture(String)

    var description: String {
        switch self {
        case .unreadableManifest(let message): return message
        case .unsupportedFixture(let message): return message
        }
    }
}

func loadA1FixtureManifest(path: String) throws -> A1FixtureManifest {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(A1FixtureManifest.self, from: data)
    } catch {
        throw A1TestError.unreadableManifest("Could not read A1 expected manifest at \(path): \(error)")
    }
}

func expectedA1Events(manifest: A1FixtureManifest, channels: Set<Int>) throws -> [A1ExpectedEvent] {
    guard manifest.schema == "logic-coproducer-midi-fixture/1.0" else {
        throw A1TestError.unsupportedFixture("Unsupported fixture schema: \(manifest.schema)")
    }
    guard manifest.ppq == 960, manifest.timeSignature == "4/4" else {
        throw A1TestError.unsupportedFixture(
            "A1 comparator currently qualifies the golden fixture only at PPQ 960 and 4/4."
        )
    }
    guard manifest.counts.notes == 1_024,
          manifest.notes.count == 1_024,
          manifest.counts.controllers == 16,
          manifest.counts.pitchBends == 8,
          manifest.counts.channelPressure == 8,
          manifest.counts.polyPressure == 8,
          manifest.counts.programChanges == 4
    else {
        throw A1TestError.unsupportedFixture("Manifest counts do not match the qualified A1 golden fixture.")
    }

    var events: [A1ExpectedEvent] = []

    for channel in channels.sorted() {
        guard (1...4).contains(channel) else {
            throw A1TestError.unsupportedFixture("Unexpected MIDI channel in Event List: \(channel)")
        }
        events.append(A1ExpectedEvent(
            tick: 0,
            order: -5 + (channel - 1),
            status: "Program",
            channel: channel,
            number: -1,
            value: (channel - 1) * 10,
            lengthTicks: nil
        ))
    }

    for note in manifest.notes where channels.contains(note.channel) {
        events.append(A1ExpectedEvent(
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
        let channel = (ordinal % 4) + 1
        guard channels.contains(channel) else { continue }
        events.append(A1ExpectedEvent(
            tick: fixtureIndex * 120 + 30,
            order: 10,
            status: "Control",
            channel: channel,
            number: 1 + (ordinal % 20),
            value: 10 + (ordinal * 7) % 118,
            lengthTicks: nil
        ))
    }

    let bendValues = [0, 2_048, 4_096, 8_192, 12_288, 14_336, 16_383, 6_144]
    for fixtureIndex in stride(from: 0, to: 1_024, by: 128) {
        let ordinal = fixtureIndex / 128
        let channel = (ordinal % 4) + 1
        guard channels.contains(channel) else { continue }
        let baseTick = fixtureIndex * 120
        let bend = bendValues[ordinal]

        events.append(A1ExpectedEvent(
            tick: baseTick + 45,
            order: 10,
            status: "PitchBd",
            channel: channel,
            number: bend & 0x7F,
            value: (bend >> 7) & 0x7F,
            lengthTicks: nil
        ))

        events.append(A1ExpectedEvent(
            tick: baseTick + 60,
            order: 10,
            status: "A-Touch",
            channel: channel,
            number: nil,
            value: 20 + (ordinal * 13) % 108,
            lengthTicks: nil
        ))

        events.append(A1ExpectedEvent(
            tick: baseTick + 90,
            order: 10,
            status: "P-Touch",
            channel: channel,
            number: 48 + (ordinal % 24),
            value: 30 + (ordinal * 11) % 98,
            lengthTicks: nil
        ))
    }

    return events.sorted {
        if $0.tick != $1.tick { return $0.tick < $1.tick }
        return $0.order < $1.order
    }
}

func a1PositionString(tick: Int, ppq: Int = 960) -> String {
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

func a1LengthString(ticks: Int, ppq: Int = 960) -> String {
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

private func a1Trim(_ value: String?) -> String? {
    guard let value else { return nil }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func a1Int(_ value: String?) -> Int? {
    guard let trimmed = a1Trim(value), !trimmed.isEmpty else { return nil }
    return Int(trimmed)
}

func a1SemanticRows(_ rows: [EventListExportRow]) -> [A1SemanticRow] {
    rows.map { row in
        let status = a1Trim(row.status)
        let channel = a1Int(row.channelDescription) ?? a1Int(row.channelRaw)
        let number = a1Int(row.numberRaw)
        let value = a1Int(row.valueDescription)
        let qualifiedLength = status == "Note" ? a1Trim(row.length) : nil
        return A1SemanticRow(
            position: a1Trim(row.position),
            status: status,
            channel: channel,
            number: number,
            value: value,
            length: qualifiedLength
        )
    }
}

func a1DetectedChannels(_ rows: [EventListExportRow]) -> Set<Int> {
    Set(rows.compactMap { a1Int($0.channelDescription) ?? a1Int($0.channelRaw) })
}

func compareA1Golden(
    observedRows: [EventListExportRow],
    manifest: A1FixtureManifest,
    channels: Set<Int>
) throws -> [A1Mismatch] {
    let expected = try expectedA1Events(manifest: manifest, channels: channels)
    let observed = a1SemanticRows(observedRows)
    var mismatches: [A1Mismatch] = []

    if observed.count != expected.count {
        mismatches.append(A1Mismatch(
            row: nil,
            field: "rowCount",
            expected: String(expected.count),
            observed: String(observed.count)
        ))
    }

    for index in 0..<min(observed.count, expected.count) {
        let actual = observed[index]
        let wanted = expected[index]

        func check(_ field: String, expected: String?, observed: String?) {
            if expected != observed {
                mismatches.append(A1Mismatch(
                    row: index,
                    field: field,
                    expected: expected ?? "nil",
                    observed: observed ?? "nil"
                ))
            }
        }

        check("position", expected: a1PositionString(tick: wanted.tick, ppq: manifest.ppq), observed: actual.position)
        check("status", expected: wanted.status, observed: actual.status)
        check("channel", expected: String(wanted.channel), observed: actual.channel.map(String.init))

        if let expectedNumber = wanted.number {
            check("number", expected: String(expectedNumber), observed: actual.number.map(String.init))
        }
        if let expectedValue = wanted.value {
            check("value", expected: String(expectedValue), observed: actual.value.map(String.init))
        }
        if let expectedLength = wanted.lengthTicks {
            check("length", expected: a1LengthString(ticks: expectedLength, ppq: manifest.ppq), observed: actual.length)
        }
    }

    return mismatches
}

func a1RepeatabilityMismatchCount(_ baseline: [EventListExportRow], _ candidate: [EventListExportRow]) -> Int {
    let left = a1SemanticRows(baseline)
    let right = a1SemanticRows(candidate)
    var mismatchCount = abs(left.count - right.count)
    for index in 0..<min(left.count, right.count) where left[index] != right[index] {
        mismatchCount += 1
    }
    return mismatchCount
}
