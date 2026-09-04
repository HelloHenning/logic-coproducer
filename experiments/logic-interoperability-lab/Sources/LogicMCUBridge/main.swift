@preconcurrency import CoreMIDI
import Foundation

private let sourceName = "CoProducer MCU To Logic"
private let destinationName = "CoProducer MCU From Logic"
private let sourceUniqueID: Int32 = 0x434F5001
private let destinationUniqueID: Int32 = 0x434F5002
private let deviceID: UInt8 = 0x14
private let serial: [UInt8] = Array("COP001A".utf8)
private let challenge: [UInt8] = [0x01, 0x02, 0x03, 0x04]

private func nowISO() -> String { ISO8601DateFormatter().string(from: Date()) }
private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
private func option(_ name: String, args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

private final class PacketQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [[UInt8]] = []

    func push(_ bytes: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        packets.append(bytes)
    }

    func drain() -> [[UInt8]] {
        lock.lock(); defer { lock.unlock() }
        let out = packets
        packets.removeAll(keepingCapacity: true)
        return out
    }
}

private final class BridgeState {
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
            "timestamp": nowISO(),
            "direction": direction,
            "hex": hex(bytes),
            "bytes": bytes.map(Int.init)
        ]
        if let note { object["note"] = note }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8) else { return }
        let text = line + "\n"
        if FileManager.default.fileExists(atPath: eventsURL.path), let handle = try? FileHandle(forWritingTo: eventsURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? text.write(to: eventsURL, atomically: true, encoding: .utf8)
        }
    }

    func writeStatus() {
        let object: [String: Any] = [
            "schema": "logic-coproducer-mcu-bridge-status/1.0",
            "generatedAt": nowISO(),
            "ready": ready,
            "sourceName": sourceName,
            "destinationName": destinationName,
            "hostPacketCount": hostPacketCount,
            "handshakeQueryCount": handshakeQueryCount,
            "handshakeReplyCount": handshakeReplyCount,
            "handshakeConfirmedCount": handshakeConfirmedCount,
            "fader0Counter": fader0Counter,
            "ring0Counter": ring0Counter,
            "mute0Counter": mute0Counter,
            "solo0Counter": solo0Counter,
            "lastFader0Raw": lastFader0Raw as Any,
            "lastRing0Value": lastRing0Value as Any,
            "lastMute0Value": lastMute0Value as Any,
            "lastSolo0Value": lastSolo0Value as Any,
            "commandAck": commandAck,
            "lastCommand": lastCommand as Any,
            "lastHostTraffic": lastHostTraffic as Any
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: statusURL, options: .atomic)
    }

    func send(_ bytes: [UInt8], note: String? = nil) -> OSStatus {
        guard source != 0 else { return -1 }
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        let status: OSStatus = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress,
                  MIDIPacketListAdd(&packetList, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, base) != nil else {
                return -1
            }
            return MIDIReceived(source, &packetList)
        }
        appendEvent(direction: "device-to-logic", bytes: bytes, note: note)
        return status
    }

    func sendSysEx(command: UInt8, params: [UInt8], note: String) {
        _ = send([0xF0, 0x00, 0x00, 0x66, deviceID, command] + params + [0xF7], note: note)
    }

    func sendConnectionQuery() {
        sendSysEx(command: 0x01, params: serial + challenge, note: "host-connection-query")
    }

    func expectedResponse() -> [UInt8] {
        let c = challenge.map(Int.init)
        let r0 = (c[0] + (c[1] ^ 0x0A) - c[3]) & 0x7F
        let r1 = ((c[2] >> 4) ^ (c[0] + c[3])) & 0x7F
        let r2 = ((c[3] - (c[2] << 2)) ^ (c[0] | c[1])) & 0x7F
        let r3 = (c[1] - c[2] + (0xF0 ^ (c[3] << 4))) & 0x7F
        return [r0, r1, r2, r3].map(UInt8.init)
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
                let sysex = Array(bytes[i...end])
                processSysEx(sysex)
                i = end + 1
                continue
            }
            let kind = status & 0xF0
            if [UInt8(0x80), 0x90, 0xB0, 0xE0].contains(kind), i + 2 < bytes.count {
                let d1 = bytes[i + 1]
                let d2 = bytes[i + 2]
                let channel = Int(status & 0x0F)
                switch kind {
                case 0xE0 where channel == 0:
                    lastFader0Raw = Int(d1) | (Int(d2) << 7)
                    fader0Counter += 1
                case 0xB0 where channel == 0 && d1 == 48:
                    lastRing0Value = Int(d2)
                    ring0Counter += 1
                case 0x80, 0x90 where channel == 0 && d1 == 16:
                    lastMute0Value = Int(d2)
                    mute0Counter += 1
                case 0x80, 0x90 where channel == 0 && d1 == 8:
                    lastSolo0Value = Int(d2)
                    solo0Counter += 1
                default:
                    break
                }
                i += 3
            } else if [UInt8(0xC0), 0xD0].contains(kind), i + 1 < bytes.count {
                i += 2
            } else {
                i += 1
            }
        }
    }

    func processSysEx(_ bytes: [UInt8]) {
        guard bytes.count >= 7,
              Array(bytes.prefix(5)) == [0xF0, 0x00, 0x00, 0x66, deviceID],
              bytes.last == 0xF7 else { return }
        let command = bytes[5]
        let params = Array(bytes.dropFirst(6).dropLast())
        switch command {
        case 0x00:
            handshakeQueryCount += 1
            sendConnectionQuery()
        case 0x02:
            handshakeReplyCount += 1
            guard params.count >= 11 else { return }
            let receivedSerial = Array(params.prefix(7))
            let response = Array(params.dropFirst(7).prefix(4))
            if receivedSerial == serial && response == expectedResponse() {
                handshakeConfirmedCount += 1
                sendSysEx(command: 0x03, params: serial, note: "host-connection-confirmation")
            }
        case 0x13:
            sendSysEx(command: 0x14, params: Array("V1.0 ".utf8), note: "firmware-version-reply")
        default:
            break
        }
    }

    func performCommand(_ line: String) {
        let parts = line.split(separator: " ").map(String.init)
        guard let first = parts.first else { return }
        let upper = first.uppercased()
        lastCommand = line
        defer { commandAck += 1 }

        switch upper {
        case "FADER" where parts.count == 3:
            guard let strip = Int(parts[1]), (0...8).contains(strip), let raw = Int(parts[2]), (0...16383).contains(raw) else { return }
            if strip <= 7 { _ = send([0x90, UInt8(104 + strip), 0x7F], note: "fader-touch-on") }
            let lsb = UInt8(raw & 0x7F)
            let msb = UInt8((raw >> 7) & 0x7F)
            _ = send([UInt8(0xE0 + strip), lsb, msb], note: "fader-position")
            if strip <= 7 { _ = send([0x80, UInt8(104 + strip), 0x00], note: "fader-touch-off") }
        case "PAN" where parts.count == 3:
            guard let strip = Int(parts[1]), (0...7).contains(strip), let delta = Int(parts[2]), delta != 0 else { return }
            let magnitude = UInt8(min(abs(delta), 63))
            let value = delta > 0 ? magnitude : (0x40 | magnitude)
            _ = send([0xB0, UInt8(16 + strip), value], note: "vpot-rotate")
        case "BUTTON" where parts.count == 3:
            guard let strip = Int(parts[2]), (0...7).contains(strip) else { return }
            let base: Int
            switch parts[1].uppercased() {
            case "SOLO": base = 8
            case "MUTE": base = 16
            default: return
            }
            let note = UInt8(base + strip)
            _ = send([0x90, note, 0x7F], note: "button-down")
            _ = send([0x80, note, 0x00], note: "button-up")
        case "HANDSHAKE":
            sendConnectionQuery()
        case "QUIT":
            shouldQuit = true
        default:
            break
        }
    }
}

private func assignStableProperties(_ endpoint: MIDIEndpointRef, uniqueID: Int32, model: String) {
    _ = MIDIObjectSetIntegerProperty(endpoint, kMIDIPropertyUniqueID, uniqueID)
    _ = MIDIObjectSetStringProperty(endpoint, kMIDIPropertyManufacturer, "Logic Co-Producer" as CFString)
    _ = MIDIObjectSetStringProperty(endpoint, kMIDIPropertyModel, model as CFString)
}

private func packetBytes(_ list: UnsafePointer<MIDIPacketList>) -> [[UInt8]] {
    var output: [[UInt8]] = []
    for packet in list.pointee {
        let bytes = withUnsafeBytes(of: packet.data) { raw -> [UInt8] in
            Array(raw.bindMemory(to: UInt8.self).prefix(Int(packet.length)))
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
var lastHandshakeSend = Date.distantPast
while !state.shouldQuit {
    for bytes in queue.drain() { state.processIncoming(bytes) }

    if let text = try? String(contentsOf: commandsURL, encoding: .utf8) {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        if lines.count > processedCommandLines {
            for line in lines[processedCommandLines...] { state.performCommand(line) }
            processedCommandLines = lines.count
        }
    }

    if state.handshakeConfirmedCount == 0 && Date().timeIntervalSince(lastHandshakeSend) >= 2.0 {
        state.sendConnectionQuery()
        lastHandshakeSend = Date()
    }

    state.writeStatus()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}

state.writeStatus()
print("RESULT=STOPPED host_packets=\(state.hostPacketCount) handshake_confirmed=\(state.handshakeConfirmedCount)")
