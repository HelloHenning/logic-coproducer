import Foundation

struct EventListExportRow: Codable {
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

struct EventListExportDocument: Codable {
    let schema: String
    let capturedAt: Date
    let logicVersion: String
    let columns: [String]
    let childRowCount: Int
    let axRowCount: Int
    let visibleRowCount: Int
    let rowSource: String
    let rows: [EventListExportRow]
}
