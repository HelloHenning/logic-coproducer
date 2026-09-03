import AppKit
import ApplicationServices
import Darwin
import Foundation

private let usageText = """
LogicInteroperabilityLab

Usage:
  logic-lab doctor [--prompt-accessibility]
  logic-lab windows
  logic-lab focused
  logic-lab find <text> [--depth N] [--max-nodes N]
  logic-lab event-list [--max-rows N] [--out PATH] [--hydrate-scroll] [--scroll-steps N]
  logic-lab snapshot --out PATH [--depth N] [--max-nodes N]

Commands:
  doctor      Report macOS/Logic process information and Accessibility trust.
  windows     List Logic's AX windows and basic semantic attributes.
  focused     Print the best available focused Logic AX element and parent chain.
  find        Search Logic's live AX hierarchy for semantic text such as
              "Event List", "Position", "Status", or "Channel".
  event-list  Locate Logic's Event List table, compare AX row collections, print
              a bounded sample, and optionally export every row as JSON.
              --hydrate-scroll temporarily moves the Event List's own scrollbar
              to hydrate virtualized AX cells, then restores its original value.
  snapshot    Write a bounded JSON snapshot of Logic's AX hierarchy.

Project data mutation remains disabled. --hydrate-scroll changes only temporary
Event List UI scroll position and restores it after capture.
"""

private let eventListColumnIDs = ["Lock", "Muted", "Position", "Status", "Ch", "Num", "Val", "Length"]

private func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

private func intOption(_ name: String, in args: [String], default defaultValue: Int) -> Int {
    guard let raw = option(name, in: args), let value = Int(raw) else { return defaultValue }
    return value
}

private func requireLogic() -> LogicProcess {
    guard let logic = LogicDiscovery.runningLogic() else {
        fputs("Logic Pro is not running. Open Logic Pro and try again.\n", stderr)
        exit(3)
    }
    return logic
}

private func requireAccessibility() {
    guard AccessibilityTrust.isTrusted(prompt: false) else {
        fputs(
            "Accessibility access is not currently granted. Run `logic-lab doctor --prompt-accessibility`, grant access in System Settings, then retry.\n",
            stderr
        )
        exit(4)
    }
}

private func doctor(args: [String]) {
    let prompt = args.contains("--prompt-accessibility")
    let trusted = AccessibilityTrust.isTrusted(prompt: prompt)

    print("LogicInteroperabilityLab doctor")
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("architecture process: \(ProcessInfo.processInfo.processorCount) logical CPUs visible")
    print("Accessibility trusted: \(trusted ? "yes" : "no")")

    guard let logic = LogicDiscovery.runningLogic() else {
        print("Logic Pro running: no")
        return
    }

    print("Logic Pro running: yes")
    print("Logic PID: \(logic.pid)")
    print("Logic bundle id: \(logic.bundleIdentifier)")
    print("Logic version: \(logic.version)")
    print("Logic path: \(logic.bundlePath)")

    if trusted {
        let focusedWindow = AXReader.element(logic.axApplication, kAXFocusedWindowAttribute)
        if let focusedWindow {
            print("Focused window:")
            printSummary(AXReader.summary(focusedWindow), prefix: "  ")
        } else {
            print("Focused window: unavailable")
        }
    }
}

private func windows() {
    requireAccessibility()
    let logic = requireLogic()

    guard let raw = AXReader.copyAttribute(logic.axApplication, kAXWindowsAttribute),
          let windows = raw as? [AXUIElement]
    else {
        print("No AX windows returned by Logic.")
        return
    }

    print("Logic AX windows: \(windows.count)")
    for (index, window) in windows.enumerated() {
        print("[\(index)]")
        printSummary(AXReader.summary(window), prefix: "  ")
        print("  children=\(AXReader.children(window).count)")
    }
}

private func focused() {
    requireAccessibility()
    let logic = requireLogic()

    var startingElement: AXUIElement?
    var source = ""

    // Some Logic builds do not expose AXFocusedUIElement directly on the
    // application object. Prefer it when available, then try the system-wide
    // focused element, and finally fall back to Logic's focused window.
    if let appFocused = AXReader.element(logic.axApplication, kAXFocusedUIElementAttribute) {
        startingElement = appFocused
        source = "Logic application AXFocusedUIElement"
    } else {
        let systemWide = AXUIElementCreateSystemWide()
        if let systemFocused = AXReader.element(systemWide, kAXFocusedUIElementAttribute) {
            var focusedPID: pid_t = 0
            if AXUIElementGetPid(systemFocused, &focusedPID) == .success, focusedPID == logic.pid {
                startingElement = systemFocused
                source = "system-wide AXFocusedUIElement (Logic PID)"
            } else if focusedPID != 0 {
                print("System-wide focused element belongs to PID \(focusedPID), not Logic PID \(logic.pid).")
            }
        }
    }

    if startingElement == nil,
       let focusedWindow = AXReader.element(logic.axApplication, kAXFocusedWindowAttribute) {
        startingElement = focusedWindow
        source = "Logic AXFocusedWindow fallback"
    }

    guard var current = startingElement else {
        print("No focused Logic AX element or focused Logic window is available.")
        return
    }

    print("Focus source: \(source)")
    print("Focused element → parent chain")
    for level in 0..<20 {
        print("[\(level)]")
        printSummary(AXReader.summary(current), prefix: "  ")

        guard let parent = AXReader.element(current, kAXParentAttribute) else { break }
        current = parent
    }
}

private func find(args: [String]) {
    requireAccessibility()
    let logic = requireLogic()

    guard let query = args.first, !query.hasPrefix("--") else {
        fputs("find requires a search string, e.g. `logic-lab find \"Event List\"`.\n", stderr)
        exit(2)
    }

    let depth = intOption("--depth", in: args, default: 14)
    let maxNodes = intOption("--max-nodes", in: args, default: 20_000)
    let walker = AXWalker(maxDepth: depth, maxNodes: maxNodes)
    let matches = walker.find(logic.axApplication, query: query)

    print("query=\(query.debugDescription) matches=\(matches.count) visited=\(walker.visitedNodes)")
    for (index, match) in matches.enumerated() {
        print("\n[\(index)] \(match.path)")
        printSummary(match.summary, prefix: "  ")
    }
}

private func columnIdentifiers(_ table: AXUIElement) -> [String] {
    let directColumns = AXReader.elements(table, "AXColumns")
    let columns = directColumns.isEmpty
        ? AXReader.children(table).filter { AXReader.string($0, kAXRoleAttribute) == kAXColumnRole }
        : directColumns
    return columns.compactMap { AXReader.string($0, kAXIdentifierAttribute) }
}

private func findEventListTable(
    _ element: AXUIElement,
    depth: Int,
    maxDepth: Int,
    visited: inout Int,
    maxNodes: Int
) -> AXUIElement? {
    guard visited < maxNodes else { return nil }
    visited += 1

    if AXReader.string(element, kAXRoleAttribute) == kAXTableRole {
        let identifiers = Set(columnIdentifiers(element))
        if Set(eventListColumnIDs).isSubset(of: identifiers) {
            return element
        }
    }

    guard depth < maxDepth else { return nil }
    for child in AXReader.children(element) {
        if let found = findEventListTable(
            child,
            depth: depth + 1,
            maxDepth: maxDepth,
            visited: &visited,
            maxNodes: maxNodes
        ) {
            return found
        }
    }
    return nil
}

private func primaryElement(in cell: AXUIElement) -> AXUIElement {
    AXReader.children(cell).first ?? cell
}

private func displayText(for cell: AXUIElement) -> String? {
    let element = primaryElement(in: cell)
    let summary = AXReader.summary(element)
    return summary.elementDescription
        ?? AXReader.valueDescription(element)
        ?? summary.value
        ?? summary.title
        ?? summary.identifier
}

private func diagnosticValue(for cell: AXUIElement) -> (raw: String?, described: String?, min: String?, max: String?) {
    let element = primaryElement(in: cell)
    return (
        AXReader.simpleValue(element),
        AXReader.valueDescription(element),
        AXReader.simpleValue(element, attribute: "AXMinValue"),
        AXReader.simpleValue(element, attribute: "AXMaxValue")
    )
}

private func eventListExportRow(index: Int, row: AXUIElement) -> EventListExportRow {
    let cells = AXReader.children(row).filter { AXReader.string($0, kAXRoleAttribute) == kAXCellRole }
    guard cells.count >= 8 else {
        return EventListExportRow(
            index: index,
            cellCount: cells.count,
            lock: nil,
            muted: nil,
            position: nil,
            status: nil,
            channelRaw: nil,
            channelDescription: nil,
            numberRaw: nil,
            numberDescription: nil,
            valueRaw: nil,
            valueDescription: nil,
            valueMinimum: nil,
            valueMaximum: nil,
            length: nil
        )
    }

    let channel = diagnosticValue(for: cells[4])
    let number = diagnosticValue(for: cells[5])
    let value = diagnosticValue(for: cells[6])

    return EventListExportRow(
        index: index,
        cellCount: cells.count,
        lock: displayText(for: cells[0]),
        muted: displayText(for: cells[1]),
        position: displayText(for: cells[2]),
        status: displayText(for: cells[3]),
        channelRaw: channel.raw,
        channelDescription: channel.described,
        numberRaw: number.raw,
        numberDescription: number.described,
        valueRaw: value.raw,
        valueDescription: value.described,
        valueMinimum: value.min,
        valueMaximum: value.max,
        length: displayText(for: cells[7])
    )
}

private func eventListRows(_ table: AXUIElement) -> [AXUIElement] {
    let axRows = AXReader.elements(table, "AXRows")
    if !axRows.isEmpty { return axRows }
    return AXReader.children(table).filter { AXReader.string($0, kAXRoleAttribute) == kAXRowRole }
}

private func eventListScrollBar(_ table: AXUIElement) -> AXUIElement? {
    guard let scrollArea = AXReader.element(table, kAXParentAttribute) else { return nil }
    let bars = AXReader.children(scrollArea).filter {
        AXReader.string($0, kAXRoleAttribute) == kAXScrollBarRole && AXReader.bool($0, kAXEnabledAttribute) != false
    }
    if let vertical = bars.first(where: {
        (AXReader.string($0, "AXOrientation") ?? "").localizedCaseInsensitiveContains("vertical")
    }) {
        return vertical
    }
    return bars.first
}

private func rowDetailScore(_ row: EventListExportRow) -> Int {
    let values: [String?] = [
        row.lock, row.muted, row.position, row.status,
        row.channelRaw, row.channelDescription,
        row.numberRaw, row.numberDescription,
        row.valueRaw, row.valueDescription,
        row.valueMinimum, row.valueMaximum, row.length
    ]
    return row.cellCount + values.reduce(0) { partial, value in
        partial + ((value?.isEmpty == false) ? 1 : 0)
    }
}

private func mergeHydratedRows(
    _ best: inout [EventListExportRow],
    candidates: [EventListExportRow],
    statusMismatchCount: inout Int
) {
    guard best.count == candidates.count else {
        print("hydrate_warning=row_count_changed expected=\(best.count) observed=\(candidates.count)")
        return
    }

    for index in best.indices {
        if let oldStatus = best[index].status,
           let newStatus = candidates[index].status,
           oldStatus != newStatus {
            statusMismatchCount += 1
            continue
        }
        if rowDetailScore(candidates[index]) > rowDetailScore(best[index]) {
            best[index] = candidates[index]
        }
    }
}

private func hydrateEventListRows(
    table: AXUIElement,
    initialRows: [EventListExportRow],
    steps: Int
) -> (rows: [EventListExportRow], completedSteps: Int, restored: Bool, statusMismatches: Int) {
    guard let scrollBar = eventListScrollBar(table) else {
        print("hydrate_scroll=unavailable reason=no_enabled_scrollbar_under_event_list")
        return (initialRows, 0, false, 0)
    }
    guard AXReader.isAttributeSettable(scrollBar, kAXValueAttribute) else {
        print("hydrate_scroll=unavailable reason=scrollbar_value_not_settable")
        return (initialRows, 0, false, 0)
    }
    guard let originalValue = AXReader.doubleValue(scrollBar) else {
        print("hydrate_scroll=unavailable reason=scrollbar_value_unreadable")
        return (initialRows, 0, false, 0)
    }

    let stepCount = max(2, steps)
    var best = initialRows
    var completed = 0
    var statusMismatches = 0

    print("hydrate_scroll=begin original_value=\(originalValue) steps=\(stepCount)")

    for step in 0...stepCount {
        let target = Double(step) / Double(stepCount)
        let error = AXReader.setNumber(scrollBar, target)
        guard error == .success else {
            print("hydrate_step=\(step) target=\(target) set_error=\(error.rawValue)")
            continue
        }

        usleep(140_000)
        let currentElements = eventListRows(table)
        let currentRows = currentElements.enumerated().map {
            eventListExportRow(index: $0.offset, row: $0.element)
        }
        mergeHydratedRows(&best, candidates: currentRows, statusMismatchCount: &statusMismatches)
        completed += 1

        let withPosition = best.filter { $0.position != nil }.count
        let withChannel = best.filter { $0.channelDescription != nil || $0.channelRaw != nil }.count
        let visible = AXReader.elements(table, "AXVisibleRows").count
        print(
            "hydrate_step=\(step)/\(stepCount) target=\(String(format: "%.4f", target)) " +
            "AXVisibleRows=\(visible) rows_with_position=\(withPosition)/\(best.count) " +
            "rows_with_channel=\(withChannel)/\(best.count)"
        )
    }

    let restoreError = AXReader.setNumber(scrollBar, originalValue)
    usleep(140_000)
    let restoredValue = AXReader.doubleValue(scrollBar)
    let restored = restoreError == .success && restoredValue.map { abs($0 - originalValue) < 0.002 } == true
    print(
        "hydrate_scroll=end completed_steps=\(completed) status_mismatches=\(statusMismatches) " +
        "restore=\(restored ? "ok" : "failed") restored_value=\(restoredValue.map(String.init(describing:)) ?? "nil")"
    )

    return (best, completed, restored, statusMismatches)
}

private func eventList(args: [String]) {
    requireAccessibility()
    let logic = requireLogic()
    let maxRows = max(1, intOption("--max-rows", in: args, default: 40))
    let shouldHydrate = args.contains("--hydrate-scroll")
    let scrollSteps = max(2, intOption("--scroll-steps", in: args, default: 16))

    var visited = 0
    guard let table = findEventListTable(
        logic.axApplication,
        depth: 0,
        maxDepth: 20,
        visited: &visited,
        maxNodes: 50_000
    ) else {
        print("Event List AX table not found. Keep the Event List open and retry.")
        return
    }

    let childRows = AXReader.children(table).filter { AXReader.string($0, kAXRoleAttribute) == kAXRowRole }
    let axRows = AXReader.elements(table, "AXRows")
    let visibleRows = AXReader.elements(table, "AXVisibleRows")
    let columns = columnIdentifiers(table)
    let rows = axRows.isEmpty ? childRows : axRows
    let initialExportedRows = rows.enumerated().map { eventListExportRow(index: $0.offset, row: $0.element) }

    var exportedRows = initialExportedRows
    var hydrationStepsCompleted: Int? = nil
    if shouldHydrate {
        let hydration = hydrateEventListRows(table: table, initialRows: initialExportedRows, steps: scrollSteps)
        exportedRows = hydration.rows
        hydrationStepsCompleted = hydration.completedSteps
        if hydration.statusMismatches > 0 {
            print("hydrate_warning=status_mismatches=\(hydration.statusMismatches)")
        }
        if !hydration.restored {
            print("hydrate_warning=scroll_position_restore_not_verified")
        }
    }

    let rowsWithPosition = exportedRows.filter { $0.position != nil }.count
    let rowsWithChannel = exportedRows.filter { $0.channelDescription != nil || $0.channelRaw != nil }.count

    print("Event List AX table found after visiting \(visited) nodes")
    print("columns=\(columns.joined(separator: ","))")
    print("child_rows=\(childRows.count)")
    print("AXRows=\(axRows.count)")
    print("AXVisibleRows=\(visibleRows.count)")
    print("row_source=\(axRows.isEmpty ? "AXChildren" : "AXRows")")
    print("rows_with_position=\(rowsWithPosition) of \(exportedRows.count)")
    print("rows_with_channel=\(rowsWithChannel) of \(exportedRows.count)")
    print("rows_printed=\(min(exportedRows.count, maxRows)) of \(exportedRows.count)")

    for rowData in exportedRows.prefix(maxRows) {
        guard rowData.cellCount >= 8 else {
            print("[\(rowData.index)] cells=\(rowData.cellCount) < expected 8")
            continue
        }

        print(
            "[\(rowData.index)] position=\((rowData.position ?? "?").debugDescription) " +
            "status=\((rowData.status ?? "?").debugDescription) " +
            "ch_raw=\((rowData.channelRaw ?? "?").debugDescription) " +
            "ch_desc=\((rowData.channelDescription ?? "nil").debugDescription) " +
            "num_raw=\((rowData.numberRaw ?? "?").debugDescription) " +
            "num_desc=\((rowData.numberDescription ?? "nil").debugDescription) " +
            "val_raw=\((rowData.valueRaw ?? "?").debugDescription) " +
            "val_desc=\((rowData.valueDescription ?? "nil").debugDescription) " +
            "val_min=\((rowData.valueMinimum ?? "nil").debugDescription) " +
            "val_max=\((rowData.valueMaximum ?? "nil").debugDescription) " +
            "length=\((rowData.length ?? "?").debugDescription)"
        )
    }

    if let outputPath = option("--out", in: args) {
        let document = EventListExportDocument(
            schema: "logic-coproducer-event-list-ax/1.1",
            capturedAt: Date(),
            logicVersion: logic.version,
            columns: columns,
            childRowCount: childRows.count,
            axRowCount: axRows.count,
            visibleRowCount: visibleRows.count,
            rowSource: axRows.isEmpty ? "AXChildren" : "AXRows",
            hydrationMode: shouldHydrate ? "scroll-sweep" : nil,
            hydrationSteps: hydrationStepsCompleted,
            rowsWithPosition: rowsWithPosition,
            rowsWithChannel: rowsWithChannel,
            rows: exportedRows
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(document)
            let url = URL(fileURLWithPath: outputPath)
            try data.write(to: url, options: .atomic)
            print("Wrote \(exportedRows.count) Event List rows to \(url.path)")
        } catch {
            fputs("Could not write Event List export: \(error)\n", stderr)
            exit(5)
        }
    }
}

private func snapshot(args: [String]) {
    requireAccessibility()
    let logic = requireLogic()

    guard let outputPath = option("--out", in: args) else {
        fputs("snapshot requires `--out PATH`.\n", stderr)
        exit(2)
    }

    let depth = intOption("--depth", in: args, default: 12)
    let maxNodes = intOption("--max-nodes", in: args, default: 20_000)
    let walker = AXWalker(maxDepth: depth, maxNodes: maxNodes)
    let root = walker.snapshot(logic.axApplication)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    do {
        let data = try encoder.encode(root)
        let url = URL(fileURLWithPath: outputPath)
        try data.write(to: url, options: .atomic)
        print("Wrote \(walker.visitedNodes) AX nodes to \(url.path)")
    } catch {
        fputs("Could not write snapshot: \(error)\n", stderr)
        exit(5)
    }
}

let args = Array(CommandLine.arguments.dropFirst())

guard let command = args.first else {
    print(usageText)
    exit(0)
}

let rest = Array(args.dropFirst())

switch command {
case "doctor":
    doctor(args: rest)
case "windows":
    windows()
case "focused":
    focused()
case "find":
    find(args: rest)
case "event-list":
    eventList(args: rest)
case "snapshot":
    snapshot(args: rest)
case "help", "--help", "-h":
    print(usageText)
default:
    fputs("Unknown command: \(command)\n\n", stderr)
    print(usageText)
    exit(2)
}
