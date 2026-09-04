@preconcurrency import CoreMIDI
import Foundation

private let destinationName = "CoProducer MCU From Logic"

private func stringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
    var value: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(object, property, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

private func findDestination(named name: String) -> MIDIEndpointRef {
    for index in 0..<MIDIGetNumberOfDestinations() {
        let endpoint = MIDIGetDestination(index)
        guard endpoint != 0 else { continue }
        let endpointName = stringProperty(endpoint, kMIDIPropertyName)
        let displayName = stringProperty(endpoint, kMIDIPropertyDisplayName)
        if endpointName == name || displayName == name { return endpoint }
    }
    return 0
}

let destination = findDestination(named: destinationName)
guard destination != 0 else {
    fputs("RESULT=FAIL reason=destination-not-found name=\(destinationName)\n", stderr)
    exit(2)
}

var client: MIDIClientRef = 0
var outputPort: MIDIPortRef = 0
guard MIDIClientCreateWithBlock("Logic Co-Producer MIDI Smoke Client" as CFString, &client, { _ in }) == noErr else {
    fputs("RESULT=FAIL reason=client-create\n", stderr)
    exit(3)
}
defer { if client != 0 { _ = MIDIClientDispose(client) } }

guard MIDIOutputPortCreate(client, "Smoke Output" as CFString, &outputPort) == noErr else {
    fputs("RESULT=FAIL reason=output-port-create\n", stderr)
    exit(4)
}
defer { if outputPort != 0 { _ = MIDIPortDispose(outputPort) } }

let bytes: [UInt8] = [0x90, 0x7F, 0x01]
var list = MIDIPacketList()
let packet = MIDIPacketListInit(&list)
let added = bytes.withUnsafeBufferPointer { buffer -> UnsafeMutablePointer<MIDIPacket>? in
    guard let base = buffer.baseAddress else { return nil }
    return MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, base)
}
guard added != nil else {
    fputs("RESULT=FAIL reason=packet-build\n", stderr)
    exit(5)
}

guard MIDISend(outputPort, destination, &list) == noErr else {
    fputs("RESULT=FAIL reason=midi-send\n", stderr)
    exit(6)
}

usleep(150_000)
print("RESULT=PASS sent=90_7F_01 destination=\(destinationName)")
