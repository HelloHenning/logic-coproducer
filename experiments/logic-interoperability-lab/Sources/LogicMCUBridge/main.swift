@preconcurrency import CoreMIDI
import Foundation

private let sourceName = "CoProducer MCU To Logic"
private let destinationName = "CoProducer MCU From Logic"
private let sourceUniqueID: Int32 = 0x434F5001
private let destinationUniqueID: Int32 = 0x434F5002
private let deviceID: UInt8 = 0x14
private let serial: [UInt8] = Array("COP001A".utf8)
private let challenge: [UInt8] = [1, 2, 3, 4]

private func nowISO() -> String { ISO8601DateFormatter().string(from: Date()) }
private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
private func option(_ name: String, args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

final class PacketQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [[UInt8]] = []
    func push(_ bytes: [UInt8]) { lock.lock(); packets.append(bytes); lock.unlock() }
    func drain() -> [[UInt8]] {
        lock.lock(); defer { lock.unlock() }
        let out = packets
        packets.removeAll(keepingCapacity: true)
        return out
    }
}

final class BridgeState {
    let statusURL: URL
    let eventsURL: URL
    var source: MIDIEndpointRef = 0
    var hostPacketCount = 0
    var handshakeQueryCount = 0
    var handshakeReplyCount = 0
    var handshakeConfirmedCount = 0
    var fader0Counter = 0
    var ring0Counter = 0
    var mute0Counter = 0
    var solo0Counter = 0
    var lastFader0Raw: Int?
    var lastRing0Value: Int?
    var lastMute0Value: Int?
    var lastSolo0Value: Int?
    var commandAck = 0
    var lastCommand: String?
    var lastHostTraffic: String?
    var ready = false
    var shouldQuit = false

    init(statusURL: URL, eventsURL: URL) {
        self.statusURL = statusURL
        self.eventsURL = eventsURL
    }

    func appendEvent(direction: String, bytes: [UInt8], note: String? = nil) {
        var object: [String: Any] = [
            "timestamp": nowISO(), "direction": direction,
            "hex": hex(bytes), "bytes": bytes.map(Int.init)
        ]
        if let note { object["note"] = note }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else { return }
        let payload = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: eventsURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: payload)
        }
    }

    func writeStatus() {
        func nullable<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
        let object: [String: Any] = [
            "schema": "logic-coproducer-mcu-bridge-status/1.0",
            "generatedAt": nowISO(), "ready": ready,
            "sourceName": sourceName, "destinationName": destinationName,
            "hostPacketCount": hostPacketCount,
            "handshakeQueryCount": handshakeQueryCount,
            "handshakeReplyCount": handshakeReplyCount,
            "handshakeConfirmedCount": handshakeConfirmedCount,
            "fader0Counter": fader0Counter, "ring0Counter": ring0Counter,
            "mute0Counter": mute0Counter, "solo0Counter": solo0Counter,
            "lastFader0Raw": nullable(lastFader0Raw),
            "lastRing0Value": nullable(lastRing0Value),
            "lastMute0Value": nullable(lastMute0Value),
            "lastSolo0Value": nullable(lastSolo0Value),
            "commandAck": commandAck,
            "lastCommand": nullable(lastCommand),
            "lastHostTraffic": nullable(lastHostTraffic)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: statusURL, options: .atomic)
    }

    func send(_ bytes: [UInt8], note: String? = nil) -> OSStatus {
        guard source != 0 else { return -1 }
        var list = MIDIPacketList()
        let packet = MIDIPacketListInit(&list)
        let result: OSStatus = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return -1 }
            _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, base)
            return MIDIReceived(source, &list)
        }
        appendEvent(direction: "device-to-logic", bytes: bytes, note: note)
        return result
    }

    func sendSysEx(_ command: UInt8, _ params: [UInt8], _ note: String) {
        _ = send([0xF0, 0x00, 0x00, 0x66, deviceID, command] + params + [0xF7], note: note)
    }

    func expectedResponse() -> [UInt8] {
        let c = challenge.map(Int.init)
        return [
            0x7F & (c[0] + (c[1] ^ 0x0A) - c[3]),
            0x7F & ((c[2] >> 4) ^ (c[0] + c[3])),
            0x7F & ((c[3] - (c[2] << 2)) ^ (c[0] | c[1])),
            0x7F & (c[1] - c[2] + (0xF0 ^ (c[3] << 4)))
        ].map(UInt8.init)
    }

    func sendConnectionQuery() {
        sendSysEx(0x01, serial + challenge, "host-connection-query")
    }

    func processSysEx(_ bytes: [UInt8]) {
        guard bytes.count >= 7,
              Array(bytes.prefix(5)) == [0xF0, 0x00, 0x00, 0x66, deviceID],
              bytes.last == 0xF7 else { return }
        let command = bytes[5]
        let params = Array(bytes.dropFirst(6).dropLast())
        if command == 0x00 {
            handshakeQueryCount += 1
            sendConnectionQuery()
        } else if command == 0x02 {
            handshakeReplyCount += 1
            guard params.count >= 11 else { return }
            let receivedSerial = Array(params.prefix(7))
            let response = Array(params.dropFirst(7).prefix(4))
            if receivedSerial == serial && response == expectedResponse() {
                handshakeConfirmedCount += 1
                sendSysEx(0x03, serial, "host-connection-confirmation")
            }
        } else if command == 0x13 {
            sendSysEx(0x14, Array("V1.0 ".utf8), "firmware-version-reply")
        }
    }

    func processIncoming(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        hostPacketCount += 1
        lastHostTraffic = nowISO()
        appendEvent(direction: "logic-to-device", bytes: bytes)

        var i = 0
        while i < bytes.count {
            let status = bytes[i]
            if status == 0xF0 {
                guard let end = bytes[i...].firstIndex(of: 0xF7) else { break }
                processSysEx(Array(bytes[i...end]))
                i = end + 1
                continue
            }
            let kind = status & 0xF0
            if [UInt8(0x80), 0x90, 0xB0, 0xE0].contains(kind), i + 2 < bytes.count {
                let d1 = bytes[i + 1], d2 = bytes[i + 2]
                let channel = Int(status & 0x0F)
                if kind == 0xE0 && channel == 0 {
                    lastFader0Raw = Int(d1) | (Int(d2) << 7); fader0Counter += 1
                } else if kind == 0xB0 && channel == 0 && d1 == 48 {
                    lastRing0Value = Int(d2); ring0Counter += 1
                } else if (kind == 0x80 || kind == 0x90) && channel == 0 && d1 == 16 {
                    lastMute0Value = Int(d2); mute0Counter += 1
                } else if (kind == 0x80 || kind == 0x90) && channel == 0 && d1 == 8 {
                    lastSolo0Value = Int(d2); solo0Counter += 1
                }
                i += 3
            } else if [UInt8(0xC0), 0xD0].contains(kind), i + 1 < bytes.count {
                i += 2
            } else {
                i += 1
            }
        }
    }

    func performCommand(_ line: String) {
        let parts = line.split(separator: " ").map(String.init)
        guard let first = parts.first else { return }
        lastCommand = line
        defer { commandAck += 1 }
        switch first.uppercased() {
        case "FADER" where parts.count == 3:
            guard let strip = Int(parts[1]), (0...8).contains(strip),
                  let raw = Int(parts[2]), (0...16383).contains(raw) else { return }
            if strip <= 7 { _ = send([0x90, UInt8(104 + strip), 0x7F], note: "fader-touch-on") }
            _ = send([UInt8(0xE0 + strip), UInt8(raw & 0x7F), UInt8((raw >> 7) & 0x7F)], note: "fader-position")
            if strip <= 7 { _ = send([0x80, UInt8(104 + strip), 0], note: "fader-touch-off") }
        case "PAN" where parts.count == 3:
            guard let strip = Int(parts[1]), (0...7).contains(strip),
                  let delta = Int(parts[2]), delta != 0 else { return }
            let mag = UInt8(min(abs(delta), 63))
            _ = send([0xB0, UInt8(16 + strip), delta > 0 ? mag : (0x40 | mag)], note: "vpot-rotate")
        case "BUTTON" where parts.count == 3:
            guard let strip = Int(parts[2]), (0...7).contains(strip) else { return }
            let base: Int
            if parts[1].uppercased() == "SOLO" { base = 8 }
            else if parts[1].uppercased() == "MUTE" { base = 16 }
            else { return }
            let note = UInt8(base + strip)
            _ = send([0x90, note, 0x7F], note: "button-down")
            _ = send([0x80, note, 0], note: "button-up")
        case "HANDSHAKE": sendConnectionQuery()
        case "QUIT": shouldQuit = true
        default: break
        }
    }
}

private func assignStableProperties(_ endpoint: MIDIEndpointRef, uniqueID: Int32, model: String) {
    _ = MIDIObjectSetIntegerProperty(endpoint, kMIDIPropertyUniqueID, uniqueID)
    _ = MIDIObjectSetStringProperty(endpoint, kMIDIPropertyManufacturer, "Logic Co-Producer" as CFString)
    _ = MIDIObjectSetStringProperty(endpoint, kMIDIPropertyModel, model as CFString)
}

private func packetBytes(_ list: UnsafePointer<MIDIPacketList>) -> [[UInt8]] {
    // Use CoreMIDI's Swift-native unsafe sequence rather than manufacturing a
    // pointer to a copied `packet` field. The previous implementation could
    // hand MIDIPacketNext a pointer that did not belong to the original packet
    // list, which is unsafe as soon as Logic sends data to the virtual input.
    var output: [[UInt8]] = []
    for packet in list.unsafeSequence() {
        let bytes = withUnsafePointer(to: packet) { packetPointer in
            Array(packetPointer.sequence())
        }
        if !bytes.isEmpty { output.append(bytes) }
    }
    return output
}

let args = Array(CommandLine.arguments.dropFirst())
guard let commandPath = option("--commands", args: args),
      let statusPath = option("--status", args: args),
      let eventsPath = option("--events", args: args) else {
    fputs("Usage: logic-mcu-bridge --commands PATH --status PATH --events PATH\n", stderr)
    exit(2)
}
let commandsURL = URL(fileURLWithPath: commandPath)
let statusURL = URL(fileURLWithPath: statusPath)
let eventsURL = URL(fileURLWithPath: eventsPath)
try? "".write(to: commandsURL, atomically: true, encoding: .utf8)
try? "".write(to: eventsURL, atomically: true, encoding: .utf8)

let queue = PacketQueue()
let state = BridgeState(statusURL: statusURL, eventsURL: eventsURL)
var client: MIDIClientRef = 0
let clientStatus = MIDIClientCreateWithBlock("Logic Co-Producer MCU" as CFString, &client) { _ in }
guard clientStatus == noErr else { fputs("MIDIClientCreate failed: \(clientStatus)\n", stderr); exit(3) }

var source: MIDIEndpointRef = 0
let sourceStatus = MIDISourceCreate(client, sourceName as CFString, &source)
guard sourceStatus == noErr else { fputs("MIDISourceCreate failed: \(sourceStatus)\n", stderr); exit(4) }
state.source = source
assignStableProperties(source, uniqueID: sourceUniqueID, model: "Virtual Mackie Control output")

var destination: MIDIEndpointRef = 0
let destinationStatus = MIDIDestinationCreateWithBlock(client, destinationName as CFString, &destination) { packetList, _ in
    for bytes in packetBytes(packetList) { queue.push(bytes) }
}
guard destinationStatus == noErr else { fputs("MIDIDestinationCreate failed: \(destinationStatus)\n", stderr); exit(5) }
assignStableProperties(destination, uniqueID: destinationUniqueID, model: "Virtual Mackie Control input")

defer {
    if source != 0 { _ = MIDIEndpointDispose(source) }
    if destination != 0 { _ = MIDIEndpointDispose(destination) }
    if client != 0 { _ = MIDIClientDispose(client) }
}
state.ready = true
state.writeStatus()
print("READY source=\(sourceName) destination=\(destinationName)")
fflush(stdout)

var processedCommandLines = 0
while !state.shouldQuit {
    for bytes in queue.drain() { state.processIncoming(bytes) }
    if let text = try? String(contentsOf: commandsURL, encoding: .utf8) {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        if lines.count > processedCommandLines {
            for line in lines[processedCommandLines...] { state.performCommand(line) }
            processedCommandLines = lines.count
        }
    }
    state.writeStatus()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
state.writeStatus()
print("RESULT=STOPPED host_packets=\(state.hostPacketCount) handshake_confirmed=\(state.handshakeConfirmedCount)")
