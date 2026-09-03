import Foundation

private struct ScheduledMIDIEvent {
    let tick: Int
    let order: Int
    let bytes: [UInt8]
}

private struct FixtureNote: Codable {
    let index: Int
    let startTick: Int
    let lengthTicks: Int
    let channel: Int
    let noteNumber: Int
    let velocity: Int
}

private struct FixtureCounts: Codable {
    let notes: Int
    let controllers: Int
    let pitchBends: Int
    let channelPressure: Int
    let polyPressure: Int
    let programChanges: Int
    let expectedEventListRows: Int
}

private struct MIDIFixtureManifest: Codable {
    let schema: String
    let fixture: String
    let ppq: Int
    let tempoBPM: Int
    let timeSignature: String
    let counts: FixtureCounts
    let notes: [FixtureNote]
    let notesAboutFixture: [String]
}

private enum GoldenA1Fixture {
    static let ppq = 960
    static let noteCount = 1_024
    static let controllerCount = 16
    static let pitchBendCount = 8
    static let channelPressureCount = 8
    static let polyPressureCount = 8
    static let programChangeCount = 4
    static let expectedEventListRows = noteCount + controllerCount + pitchBendCount + channelPressureCount + polyPressureCount + programChangeCount

    static func write(to midiURL: URL) throws -> URL {
        var scheduled: [ScheduledMIDIEvent] = []
        var notes: [FixtureNote] = []

        // Track name, 120 BPM, 4/4.
        scheduled.append(ScheduledMIDIEvent(
            tick: 0,
            order: -30,
            bytes: [0xFF, 0x03, 0x13] + Array("Logic A1 Golden POC".utf8)
        ))
        scheduled.append(ScheduledMIDIEvent(
            tick: 0,
            order: -20,
            bytes: [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]
        ))
        scheduled.append(ScheduledMIDIEvent(
            tick: 0,
            order: -10,
            bytes: [0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]
        ))

        // One program change on each of four channels.
        for channel in 0..<4 {
            scheduled.append(ScheduledMIDIEvent(
                tick: 0,
                order: -5 + channel,
                bytes: [UInt8(0xC0 | channel), UInt8(channel * 10)]
            ))
        }

        let offsets = [0, 1, 7, 31, 79]
        let lengths = [60, 119, 120, 239, 240, 479, 960, 1_441]
        var lastEndByChannelPitch: [String: Int] = [:]

        for index in 0..<noteCount {
            let start = index * 120 + offsets[index % offsets.count]
            let channel: Int
            let pitch: Int

            // Every 64-note block starts with two deliberately overlapping
            // same-pitch notes on different channels. Pitch 61 is reserved
            // from the ordinary channel-1/channel-2 pitch patterns so a later
            // same-channel note cannot create ambiguous MIDI note-off pairing.
            if index % 64 == 0 {
                channel = 0
                pitch = 61
            } else if index % 64 == 1 {
                channel = 1
                pitch = 61
            } else {
                channel = index % 4
                pitch = 36 + ((index * 7) % 48)
            }

            let velocity = 20 + ((index * 37) % 108)
            var length = lengths[index % lengths.count]
            if index % 64 == 0 || index % 64 == 1 {
                length = 960
            }

            let overlapKey = "\(channel):\(pitch)"
            if let previousEnd = lastEndByChannelPitch[overlapKey] {
                precondition(
                    start >= previousEnd,
                    "Fixture contains ambiguous same-channel/same-pitch overlap for \(overlapKey)"
                )
            }
            lastEndByChannelPitch[overlapKey] = start + length

            notes.append(FixtureNote(
                index: index,
                startTick: start,
                lengthTicks: length,
                channel: channel + 1,
                noteNumber: pitch,
                velocity: velocity
            ))

            scheduled.append(ScheduledMIDIEvent(
                tick: start,
                order: 20,
                bytes: [UInt8(0x90 | channel), UInt8(pitch), UInt8(velocity)]
            ))
            scheduled.append(ScheduledMIDIEvent(
                tick: start + length,
                order: 0,
                bytes: [UInt8(0x80 | channel), UInt8(pitch), 0]
            ))
        }

        var generatedControllers = 0
        for index in stride(from: 0, to: noteCount, by: 64) {
            let channel = (index / 64) % 4
            let tick = index * 120 + 30
            let controller = 1 + ((index / 64) % 20)
            let value = 10 + ((index / 64) * 7) % 118
            scheduled.append(ScheduledMIDIEvent(
                tick: tick,
                order: 10,
                bytes: [UInt8(0xB0 | channel), UInt8(controller), UInt8(value)]
            ))
            generatedControllers += 1
        }
        precondition(generatedControllers == controllerCount)

        let bendValues = [0, 2_048, 4_096, 8_192, 12_288, 14_336, 16_383, 6_144]
        var generatedBends = 0
        var generatedChannelPressure = 0
        var generatedPolyPressure = 0
        for index in stride(from: 0, to: noteCount, by: 128) {
            let ordinal = index / 128
            let channel = ordinal % 4
            let baseTick = index * 120

            let bend = bendValues[ordinal % bendValues.count]
            let lsb = UInt8(bend & 0x7F)
            let msb = UInt8((bend >> 7) & 0x7F)
            scheduled.append(ScheduledMIDIEvent(
                tick: baseTick + 45,
                order: 10,
                bytes: [UInt8(0xE0 | channel), lsb, msb]
            ))
            generatedBends += 1

            let pressure = 20 + (ordinal * 13) % 108
            scheduled.append(ScheduledMIDIEvent(
                tick: baseTick + 60,
                order: 10,
                bytes: [UInt8(0xD0 | channel), UInt8(pressure)]
            ))
            generatedChannelPressure += 1

            let polyPitch = 48 + (ordinal % 24)
            let polyValue = 30 + (ordinal * 11) % 98
            scheduled.append(ScheduledMIDIEvent(
                tick: baseTick + 90,
                order: 10,
                bytes: [UInt8(0xA0 | channel), UInt8(polyPitch), UInt8(polyValue)]
            ))
            generatedPolyPressure += 1
        }
        precondition(generatedBends == pitchBendCount)
        precondition(generatedChannelPressure == channelPressureCount)
        precondition(generatedPolyPressure == polyPressureCount)

        scheduled.sort {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            return $0.order < $1.order
        }

        var track = Data()
        var previousTick = 0
        for event in scheduled {
            let delta = event.tick - previousTick
            precondition(delta >= 0)
            track.append(contentsOf: variableLengthQuantity(delta))
            track.append(contentsOf: event.bytes)
            previousTick = event.tick
        }
        track.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])

        var midi = Data()
        midi.append(contentsOf: Array("MThd".utf8))
        appendBE32(6, to: &midi)
        appendBE16(0, to: &midi) // format 0
        appendBE16(1, to: &midi) // one track
        appendBE16(UInt16(ppq), to: &midi)
        midi.append(contentsOf: Array("MTrk".utf8))
        appendBE32(UInt32(track.count), to: &midi)
        midi.append(track)

        try midi.write(to: midiURL, options: .atomic)

        let counts = FixtureCounts(
            notes: noteCount,
            controllers: controllerCount,
            pitchBends: pitchBendCount,
            channelPressure: channelPressureCount,
            polyPressure: polyPressureCount,
            programChanges: programChangeCount,
            expectedEventListRows: expectedEventListRows
        )

        let manifest = MIDIFixtureManifest(
            schema: "logic-coproducer-midi-fixture/1.0",
            fixture: "A1 complete Event List read golden fixture",
            ppq: ppq,
            tempoBPM: 120,
            timeSignature: "4/4",
            counts: counts,
            notes: notes,
            notesAboutFixture: [
                "Synthetic/public-safe fixture; contains no user music.",
                "1,024 note events with deterministic pitch, velocity, channel, timing, and length.",
                "Each 64-note block starts with overlapping pitch-61 notes on channels 1 and 2; pitch 61 is reserved from ordinary channel-1/channel-2 notes to avoid ambiguous same-channel MIDI note-off pairing.",
                "Includes controller, pitch-bend, channel-pressure, poly-pressure, and program-change events.",
                "Looped/cropped Logic-region behavior and articulation-specific Logic metadata are separate later tests because SMF does not encode those Logic project semantics."
            ]
        )

        let manifestURL = midiURL.deletingPathExtension().appendingPathExtension("expected.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return manifestURL
    }

    private static func variableLengthQuantity(_ value: Int) -> [UInt8] {
        precondition(value >= 0)
        var buffer = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            buffer.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        }
        return Array(buffer.reversed())
    }

    private static func appendBE16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendBE32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }
}

private func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
guard let output = option("--out", in: args) else {
    fputs("Usage: logic-fixture --out PATH.mid\n", stderr)
    exit(2)
}

let expandedPath = NSString(string: output).expandingTildeInPath
let midiURL = URL(fileURLWithPath: expandedPath)

do {
    let manifestURL = try GoldenA1Fixture.write(to: midiURL)
    print("Wrote MIDI fixture: \(midiURL.path)")
    print("Wrote expected manifest: \(manifestURL.path)")
    print("expected_note_rows=\(GoldenA1Fixture.noteCount)")
    print("expected_event_list_rows_if_all_filters_visible=\(GoldenA1Fixture.expectedEventListRows)")
} catch {
    fputs("Could not generate fixture: \(error)\n", stderr)
    exit(5)
}
