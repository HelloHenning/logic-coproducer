import AppKit
import ApplicationServices
import Foundation

private struct AXID: Hashable {
    let element: AXUIElement
    static func == (lhs: AXID, rhs: AXID) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

private enum AX {
    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success ? raw : nil
    }
    static func string(_ element: AXUIElement, _ attribute: String) -> String? { copy(element, attribute) as? String }
    static func simple(_ element: AXUIElement, _ attribute: String = kAXValueAttribute) -> String? {
        guard let raw = copy(element, attribute) else { return nil }
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }
    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let raw = copy(element, attribute) else { return nil }
        if let value = raw as? Bool { return value }
        if let number = raw as? NSNumber { return number.boolValue }
        return nil
    }
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (copy(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { !CFEqual($0, element) }
    }
    static func actions(_ element: AXUIElement) -> [String] {
        var raw: CFArray?
        guard AXUIElementCopyActionNames(element, &raw) == .success else { return [] }
        return raw as? [String] ?? []
    }
    static func settable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var flag = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &flag) == .success && flag.boolValue
    }
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
    static func press(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}

private struct Candidate {
    let path: String
    let role: String?
    let title: String?
    let elementDescription: String?
    let value: String?
    let valueDescription: String?
    let enabled: Bool?
    let selected: Bool?
    let actions: [String]
}

private struct Ref {
    let candidate: Candidate
    let element: AXUIElement
}

private final class Walker {
    private var seen: Set<AXID> = []
    func all(from root: AXUIElement) -> [Ref] {
        var stack: [(AXUIElement, Int, String)] = [(root, 0, "app")]
        var output: [Ref] = []
        while let (element, depth, path) = stack.popLast(), output.count < 100_000 {
            let identity = AXID(element: element)
            guard seen.insert(identity).inserted else { continue }
            let role = AX.string(element, kAXRoleAttribute)
            output.append(Ref(candidate: Candidate(
                path: path,
                role: role,
                title: AX.string(element, kAXTitleAttribute),
                elementDescription: AX.string(element, kAXDescriptionAttribute),
                value: AX.simple(element),
                valueDescription: AX.simple(element, "AXValueDescription"),
                enabled: AX.bool(element, kAXEnabledAttribute),
                selected: AX.bool(element, kAXSelectedAttribute),
                actions: AX.actions(element)
            ), element: element))
            guard depth < 30 else { continue }
            for (index, child) in AX.children(element).enumerated().reversed() {
                let childRole = AX.string(child, kAXRoleAttribute) ?? "AXElement"
                stack.append((child, depth + 1, "\(path)/\(childRole)[\(index)]"))
            }
        }
        return output
    }
}

private func option(_ name: String, _ args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}
private func norm(_ value: String?) -> String { (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
private func fields(_ candidate: Candidate) -> [String] { [candidate.title, candidate.elementDescription, candidate.value, candidate.valueDescription].compactMap { $0 } }
private func text(_ candidate: Candidate) -> String { fields(candidate).joined(separator: " ").lowercased() }
private func exact(_ candidate: Candidate, _ wanted: String) -> Bool { fields(candidate).contains { norm($0) == norm(wanted) } }
private func subtree(_ refs: [Ref], _ prefix: String) -> [Ref] { refs.filter { $0.candidate.path == prefix || $0.candidate.path.hasPrefix(prefix + "/") } }
private func depth(_ path: String) -> Int { path.reduce(into: 0) { if $1 == "/" { $0 += 1 } } }
private func parent(_ path: String) -> String? { path.lastIndex(of: "/").map { String(path[..<$0]) } }

private func logic() -> (NSRunningApplication, AXUIElement)? {
    guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { return nil }
    return (app, AXUIElementCreateApplication(app.processIdentifier))
}
private func scan() -> [Ref]? {
    guard let (_, root) = logic() else { return nil }
    return Walker().all(from: root)
}
private func activate() -> Bool {
    guard let (app, _) = logic() else { return false }
    return app.activate(options: [.activateIgnoringOtherApps])
}
private func postKey(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cgAnnotatedSessionEventTap)
    usleep(45_000)
    up.post(tap: .cgAnnotatedSessionEventTap)
}
private func paste(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    postKey(9, .maskCommand)
}
private func escape() { postKey(53) }
private func writeJSON(_ object: Any, path: String?) {
    guard let path, JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private func focusMain() {
    guard activate(), let refs = scan() else { return }
    if let window = refs.first(where: { $0.candidate.role == kAXWindowRole && norm($0.candidate.title).contains("tracks") }) {
        if AX.settable(window.element, kAXFocusedAttribute) { _ = AX.set(window.element, kAXFocusedAttribute, kCFBooleanTrue) }
        if AX.settable(window.element, kAXMainAttribute) { _ = AX.set(window.element, kAXMainAttribute, kCFBooleanTrue) }
    }
    usleep(100_000)
}

private func windows(_ refs: [Ref]) -> [Ref] { refs.filter { $0.candidate.role == kAXWindowRole } }
private func saveWindows(_ refs: [Ref]) -> [Ref] {
    windows(refs).filter { norm($0.candidate.title).contains("save a copy as") || text($0.candidate).contains("save a copy as") }
}
private func forbiddenModal(_ title: String) -> Bool {
    let value = norm(title)
    return value.contains("save a copy as") || value.contains("open") || value.contains("import")
}

private func modalStatus(out: String?) -> Int32 {
    guard let refs = scan() else { return 20 }
    let allWindows = windows(refs).map { $0.candidate.title ?? $0.candidate.path }
    let saves = saveWindows(refs).map { $0.candidate.title ?? $0.candidate.path }
    writeJSON(["schema": "logic-coproducer-modal-status/1.0", "windows": allWindows, "saveCopyWindows": saves], path: out)
    print("RESULT=PASS save_copy_windows=\(saves.count) windows=\(allWindows.count)")
    return 0
}

private func dismissSave() -> Int32 {
    guard var refs = scan() else { return 20 }
    var saves = saveWindows(refs)
    if saves.isEmpty { print("RESULT=PASS save_dialog_absent=true"); return 0 }
    guard saves.count == 1 else { print("RESULT=RESTORE_FAIL reason=save-dialog-count-ambiguous count=\(saves.count)"); return 30 }
    let descendants = subtree(refs, saves[0].candidate.path)
    let cancelButtons = descendants.filter {
        $0.candidate.role == kAXButtonRole && exact($0.candidate, "Cancel") &&
        $0.candidate.enabled != false && $0.candidate.actions.contains(kAXPressAction as String)
    }
    guard cancelButtons.count == 1, AX.press(cancelButtons[0].element) == .success else {
        print("RESULT=RESTORE_FAIL reason=save-dialog-cancel-not-unique count=\(cancelButtons.count)")
        return 30
    }
    for _ in 0..<30 {
        usleep(100_000)
        refs = scan() ?? []
        saves = saveWindows(refs)
        if saves.isEmpty { print("RESULT=PASS save_dialog_dismissed=true"); return 0 }
    }
    print("RESULT=RESTORE_FAIL reason=save-dialog-remained-after-cancel")
    return 30
}

private func pressExactMenu(_ title: String) -> Bool {
    guard let refs = scan() else { return false }
    let candidates = refs.filter {
        $0.candidate.role == kAXMenuItemRole && exact($0.candidate, title) &&
        $0.candidate.enabled != false && $0.candidate.actions.contains(kAXPressAction as String)
    }
    return candidates.count == 1 && AX.press(candidates[0].element) == .success
}

private func waitForSaveWindow() -> Ref? {
    for _ in 0..<30 {
        usleep(100_000)
        if let refs = scan() {
            let matches = saveWindows(refs)
            if matches.count == 1 { return matches[0] }
        }
    }
    return nil
}

private func isInsideScrollArea(_ ref: Ref, refs: [Ref], root: String) -> Bool {
    var current = parent(ref.candidate.path)
    while let path = current, path.hasPrefix(root) {
        if let ancestor = refs.first(where: { $0.candidate.path == path }), ancestor.candidate.role == kAXScrollAreaRole { return true }
        current = parent(path)
    }
    return false
}

private func filenameField(window: Ref, refs: [Ref]) -> Ref? {
    let descendants = subtree(refs, window.candidate.path)
    var scored: [(Ref, Int)] = []
    for ref in descendants where ref.candidate.role == kAXTextFieldRole && AX.settable(ref.element, kAXValueAttribute) && !isInsideScrollArea(ref, refs: refs, root: window.candidate.path) {
        var score = 0
        let value = (ref.candidate.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { score += 8 }
        if !value.contains("/") { score += 5 }
        let relativeDepth = depth(ref.candidate.path) - depth(window.candidate.path)
        if relativeDepth <= 4 { score += 6 } else if relativeDepth <= 7 { score += 2 }
        if text(ref.candidate).contains("search") { score -= 20 }
        scored.append((ref, score))
    }
    scored.sort { $0.1 == $1.1 ? $0.0.candidate.path < $1.0.candidate.path : $0.1 > $1.1 }
    guard let first = scored.first, first.1 > 0 else { return nil }
    if scored.count > 1 && scored[1].1 == first.1 { return nil }
    return first.0
}

private func saveCopy(path: String) -> Int32 {
    focusMain()
    var opened = pressExactMenu("Save a Copy As…")
    if !opened { opened = pressExactMenu("Save a Copy As...") }
    guard opened, waitForSaveWindow() != nil else { print("RESULT=SKIP reason=save-dialog-not-opened"); return 10 }
    guard let refs0 = scan(), let saveWindow0 = saveWindows(refs0).first, let nameField = filenameField(window: saveWindow0, refs: refs0) else {
        let cleanup = dismissSave()
        print("RESULT=FAIL reason=save-name-field-not-resolved cleanup_rc=\(cleanup)")
        return cleanup == 30 ? 30 : 20
    }
    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent().path
    let filename = url.deletingPathExtension().lastPathComponent
    guard AX.set(nameField.element, kAXValueAttribute, filename as CFString) == .success else {
        let cleanup = dismissSave()
        print("RESULT=FAIL reason=save-name-write cleanup_rc=\(cleanup)")
        return cleanup == 30 ? 30 : 20
    }
    postKey(5, [.maskShift, .maskCommand])
    usleep(120_000)
    paste(directory)
    postKey(36)
    usleep(300_000)
    guard let refs1 = scan(), let saveWindow1 = saveWindows(refs1).first else {
        print("RESULT=RESTORE_FAIL reason=save-dialog-lost-after-folder-navigation")
        return 30
    }
    let saveButtons = subtree(refs1, saveWindow1.candidate.path).filter {
        $0.candidate.role == kAXButtonRole && exact($0.candidate, "Save") &&
        $0.candidate.enabled != false && $0.candidate.actions.contains(kAXPressAction as String)
    }
    guard saveButtons.count == 1, AX.press(saveButtons[0].element) == .success else {
        let cleanup = dismissSave()
        print("RESULT=FAIL reason=save-button-not-unique count=\(saveButtons.count) cleanup_rc=\(cleanup)")
        return cleanup == 30 ? 30 : 20
    }
    for _ in 0..<50 {
        usleep(100_000)
        if let refs = scan(), saveWindows(refs).isEmpty { break }
    }
    guard let finalRefs = scan(), saveWindows(finalRefs).isEmpty else { print("RESULT=RESTORE_FAIL reason=save-dialog-remained-after-save"); return 30 }
    let fm = FileManager.default
    let candidates = [path, path.hasSuffix(".logicx") ? path : path + ".logicx", url.deletingPathExtension().appendingPathExtension("logicx").path]
    if let actual = candidates.first(where: { fm.fileExists(atPath: $0) }) {
        print("RESULT=PASS path=\(actual)")
        return 0
    }
    print("RESULT=FAIL reason=saved-copy-not-found modal_cleanup=verified")
    return 20
}

private func targetStrips(_ label: String, refs: [Ref]) -> [Ref] {
    let raw = refs.filter { ref in
        guard ref.candidate.role == kAXLayoutItemRole || ref.candidate.role == kAXGroupRole else { return false }
        let descendants = subtree(refs, ref.candidate.path)
        return descendants.contains { exact($0.candidate, label) } &&
            descendants.contains { $0.candidate.role == kAXSliderRole && text($0.candidate).contains("volume") } &&
            descendants.contains { $0.candidate.role == kAXSliderRole && text($0.candidate).contains("pan") }
    }
    return raw.filter { candidate in
        !raw.contains { other in other.candidate.path != candidate.candidate.path && other.candidate.path.hasPrefix(candidate.candidate.path + "/") }
    }.sorted { depth($0.candidate.path) > depth($1.candidate.path) }
}

@discardableResult private func selectTrack(_ label: String) -> Ref? {
    guard activate(), let refs = scan() else { return nil }
    let strips = targetStrips(label, refs: refs)
    guard !strips.isEmpty else { return nil }
    for strip in strips {
        if AX.settable(strip.element, kAXSelectedAttribute), AX.set(strip.element, kAXSelectedAttribute, kCFBooleanTrue) == .success {
            usleep(150_000)
            return strip
        }
        for labelRef in subtree(refs, strip.candidate.path).filter({ exact($0.candidate, label) }) {
            if labelRef.candidate.actions.contains(kAXPressAction as String), AX.press(labelRef.element) == .success {
                usleep(150_000)
                return strip
            }
        }
    }
    return nil
}

private func routeFingerprint(_ refs: [Ref]) -> [String] {
    let tokens = ["st out", "stereo out", "no output", "output", "send", "bus", "input"]
    return refs.compactMap { ref in
        let value = text(ref.candidate)
        return tokens.contains(where: { value.contains($0) }) ? "\(ref.candidate.path)|\(ref.candidate.role ?? "")|\(fields(ref.candidate).joined(separator: "~"))" : nil
    }.sorted()
}

private func outputMenuContract(_ refs: [Ref]) -> Bool {
    refs.contains { $0.candidate.role == kAXMenuItemRole && exact($0.candidate, "No Output") } &&
    refs.contains { $0.candidate.role == kAXMenuItemRole && exact($0.candidate, "Stereo Out") }
}

private func routeCandidates(strip: Ref, refs: [Ref], display: String) -> [Ref] {
    let descendants = subtree(refs, strip.candidate.path)
    var seen: Set<String> = []
    var output: [Ref] = []
    for hit in descendants where exact(hit.candidate, display) {
        var current: String? = hit.candidate.path
        while let path = current, path.hasPrefix(strip.candidate.path) {
            if let ref = refs.first(where: { $0.candidate.path == path }),
               ref.candidate.enabled != false,
               ref.candidate.actions.contains(kAXPressAction as String),
               seen.insert(path).inserted {
                output.append(ref)
            }
            current = parent(path)
        }
    }
    return output.sorted { depth($0.candidate.path) > depth($1.candidate.path) }
}

private func pressExactMenuItem(_ title: String) -> Bool {
    guard let refs = scan() else { return false }
    let candidates = refs.filter {
        $0.candidate.role == kAXMenuItemRole && exact($0.candidate, title) &&
        $0.candidate.enabled != false && $0.candidate.actions.contains(kAXPressAction as String)
    }
    return candidates.count == 1 && AX.press(candidates[0].element) == .success
}

private func qualifyingRouteControl(strip: Ref, refs: [Ref], display: String) -> Ref? {
    var matches: [Ref] = []
    for candidate in routeCandidates(strip: strip, refs: refs, display: display) {
        if AX.press(candidate.element) != .success { continue }
        usleep(120_000)
        if let menuRefs = scan(), outputMenuContract(menuRefs) { matches.append(candidate) }
        escape()
        usleep(100_000)
    }
    return matches.count == 1 ? matches[0] : nil
}

private func outputRoundtrip(track: String, out: String?) -> Int32 {
    guard let selected = selectTrack(track), let refs0 = scan(),
          let strip = targetStrips(track, refs: refs0).first(where: { $0.candidate.path == selected.candidate.path }) ?? targetStrips(track, refs: refs0).first else {
        print("RESULT=SKIP reason=track-not-resolved")
        return 10
    }
    let before = routeFingerprint(subtree(refs0, strip.candidate.path))
    guard let control = qualifyingRouteControl(strip: strip, refs: refs0, display: "St Out") ?? qualifyingRouteControl(strip: strip, refs: refs0, display: "Stereo Out") else {
        writeJSON(["schema": "logic-coproducer-a7-route-repair/1.0", "result": "SKIP", "before": before, "candidateCount": routeCandidates(strip: strip, refs: refs0, display: "St Out").count + routeCandidates(strip: strip, refs: refs0, display: "Stereo Out").count], path: out)
        print("RESULT=SKIP reason=no-unique-control-with-output-menu-contract")
        return 10
    }
    guard AX.press(control.element) == .success else { return 20 }
    usleep(100_000)
    guard pressExactMenuItem("No Output") else { escape(); print("RESULT=FAIL reason=no-output-menu-selection"); return 20 }
    usleep(250_000)
    guard let refs1 = scan(), let changedStrip = targetStrips(track, refs: refs1).first else { print("RESULT=RESTORE_FAIL reason=track-lost-after-route-change"); return 30 }
    let changed = routeFingerprint(subtree(refs1, changedStrip.candidate.path))
    guard let restoreControl = qualifyingRouteControl(strip: changedStrip, refs: refs1, display: "No Output") else { print("RESULT=RESTORE_FAIL reason=restore-output-control-not-resolved"); return 30 }
    guard AX.press(restoreControl.element) == .success else { return 30 }
    usleep(100_000)
    guard pressExactMenuItem("Stereo Out") else { escape(); print("RESULT=RESTORE_FAIL reason=stereo-out-restore-selection"); return 30 }
    usleep(250_000)
    guard let finalRefs = scan(), let finalStrip = targetStrips(track, refs: finalRefs).first else { return 30 }
    let final = routeFingerprint(subtree(finalRefs, finalStrip.candidate.path))
    writeJSON(["schema": "logic-coproducer-a7-route-repair/1.0", "result": final == before ? "PASS" : "RESTORE_FAIL", "before": before, "changed": changed, "final": final], path: out)
    if final == before {
        print("RESULT=PASS route=\(track.replacingOccurrences(of: " ", with: "_")) changed=No_Output restored=Stereo_Out")
        return 0
    }
    print("RESULT=RESTORE_FAIL reason=route-fingerprint-mismatch")
    return 30
}

private func tracksWindow(_ refs: [Ref]) -> Ref? {
    let candidates = windows(refs).filter { norm($0.candidate.title).contains("tracks") }
    return candidates.count == 1 ? candidates[0] : candidates.first
}
private func windowContains(_ window: Ref, refs: [Ref], needle: String) -> Bool {
    subtree(refs, window.candidate.path).contains { fields($0.candidate).contains(where: { $0.contains(needle) }) }
}
private func tracksHas(filename: String, expected: Bool) -> Int32 {
    guard let refs = scan(), let tracks = tracksWindow(refs) else { return 20 }
    let present = windowContains(tracks, refs: refs, needle: filename)
    print("RESULT=\(present == expected ? "PASS" : "FAIL") tracks_contains=\(present ? "true" : "false") filename=\(filename)")
    return present == expected ? 0 : 20
}

private func selectRegion(track: String, name: String) -> Int32 {
    guard selectTrack(track) != nil, let refs = scan(), let tracks = tracksWindow(refs) else { print("RESULT=SKIP reason=track-or-tracks-window"); return 10 }
    let descendants = subtree(refs, tracks.candidate.path)
    var candidates = descendants.filter { ref in
        fields(ref.candidate).contains(where: { $0.contains(name) }) &&
        (ref.candidate.role == kAXLayoutItemRole || ref.candidate.role == kAXGroupRole || ref.candidate.actions.contains(kAXPressAction as String))
    }
    candidates.sort { depth($0.candidate.path) > depth($1.candidate.path) }
    for ref in candidates {
        if AX.settable(ref.element, kAXSelectedAttribute), AX.set(ref.element, kAXSelectedAttribute, kCFBooleanTrue) == .success {
            usleep(120_000)
            print("RESULT=PASS region=\(name)")
            return 0
        }
        if ref.candidate.actions.contains(kAXPressAction as String), AX.press(ref.element) == .success {
            usleep(120_000)
            print("RESULT=PASS region=\(name)")
            return 0
        }
    }
    print("RESULT=SKIP reason=region-not-selectable filename=\(name)")
    return 10
}

private func strictSource(filename: String, out: String?) -> Int32 {
    guard let refs = scan() else { return 20 }
    var diagnostics: [[String: Any]] = []
    var qualified: [Ref] = []
    for window in windows(refs) {
        let title = window.candidate.title ?? ""
        let hasFilename = windowContains(window, refs: refs, needle: filename)
        let descendants = subtree(refs, window.candidate.path)
        let editorSemantic = norm(title).contains("audio file editor") || descendants.contains { text($0.candidate).contains("audio file editor") }
        let forbidden = forbiddenModal(title)
        diagnostics.append(["title": title, "containsFilename": hasFilename, "editorSemantic": editorSemantic, "forbiddenModal": forbidden])
        if hasFilename && editorSemantic && !forbidden { qualified.append(window) }
    }
    writeJSON(["schema": "logic-coproducer-a9-source-context-strict/1.0", "filename": filename, "windows": diagnostics, "qualifiedWindows": qualified.map { $0.candidate.title ?? $0.candidate.path }], path: out)
    if qualified.count == 1 {
        print("RESULT=PASS mapping_level=associated_source_file_only filename=\(filename) editor=\(qualified[0].candidate.title ?? "")")
        return 0
    }
    print("RESULT=SKIP reason=strict-audio-file-editor-context-not-unique count=\(qualified.count)")
    return 10
}

private func openNestedMenu(parentTitle: String, childTitles: [String]) -> Bool {
    guard let refs = scan() else { return false }
    let parents = refs.filter {
        $0.candidate.role == kAXMenuItemRole && exact($0.candidate, parentTitle) &&
        $0.candidate.enabled != false && $0.candidate.actions.contains(kAXPressAction as String)
    }
    guard parents.count == 1, AX.press(parents[0].element) == .success else { return false }
    usleep(120_000)
    guard let refs2 = scan() else { return false }
    for title in childTitles {
        let children = refs2.filter {
            $0.candidate.role == kAXMenuItemRole && exact($0.candidate, title) &&
            $0.candidate.enabled != false && $0.candidate.actions.contains(kAXPressAction as String)
        }
        if children.count == 1, AX.press(children[0].element) == .success { return true }
    }
    escape()
    return false
}

private func importMusicXML(path: String) -> Int32 {
    focusMain()
    var opened = pressExactMenu("MusicXML…") || pressExactMenu("MusicXML...") || pressExactMenu("MusicXML")
    if !opened { opened = openNestedMenu(parentTitle: "Import", childTitles: ["MusicXML…", "MusicXML...", "MusicXML"]) }
    guard opened else { print("RESULT=SKIP reason=musicxml-menu-not-resolved"); return 10 }
    usleep(350_000)
    postKey(5, [.maskShift, .maskCommand])
    usleep(120_000)
    paste(path)
    postKey(36)
    usleep(250_000)
    postKey(36)
    usleep(650_000)
    print("RESULT=PASS import_command_completed=true path=\(path)")
    return 0
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { exit(2) }
guard AXIsProcessTrusted(), logic() != nil else { exit(3) }
let out = option("--out", args)

switch command {
case "modal-status": exit(modalStatus(out: out))
case "dismiss-save-dialog": exit(dismissSave())
case "save-copy": guard let path = option("--path", args) else { exit(2) }; exit(saveCopy(path: path))
case "output-roundtrip": guard let track = option("--track", args) else { exit(2) }; exit(outputRoundtrip(track: track, out: out))
case "tracks-has":
    guard let name = option("--filename", args), let wanted = option("--present", args) else { exit(2) }
    exit(tracksHas(filename: name, expected: wanted == "yes" || wanted == "true"))
case "select-region": guard let track = option("--track", args), let name = option("--name", args) else { exit(2) }; exit(selectRegion(track: track, name: name))
case "source-context": guard let name = option("--filename", args) else { exit(2) }; exit(strictSource(filename: name, out: out))
case "import-musicxml": guard let path = option("--path", args) else { exit(2) }; exit(importMusicXML(path: path))
default: exit(2)
}
