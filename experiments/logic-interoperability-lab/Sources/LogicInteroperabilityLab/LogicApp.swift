import AppKit
import ApplicationServices
import Foundation

struct LogicProcess {
    let app: NSRunningApplication

    var pid: pid_t { app.processIdentifier }
    var axApplication: AXUIElement { AXUIElementCreateApplication(pid) }
    var bundleIdentifier: String { app.bundleIdentifier ?? "unknown" }
    var bundlePath: String { app.bundleURL?.path ?? "unknown" }

    var version: String {
        guard let url = app.bundleURL,
              let bundle = Bundle(url: url)
        else { return "unknown" }

        return (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "unknown"
    }
}

enum LogicDiscovery {
    private static let knownBundleIdentifiers = [
        "com.apple.logic10"
    ]

    static func runningLogic() -> LogicProcess? {
        for bundleID in knownBundleIdentifiers {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                return LogicProcess(app: app)
            }
        }

        if let app = NSWorkspace.shared.runningApplications.first(where: {
            let name = $0.localizedName?.lowercased() ?? ""
            return name == "logic pro" || name.hasPrefix("logic pro ")
        }) {
            return LogicProcess(app: app)
        }

        return nil
    }
}

enum AccessibilityTrust {
    static func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            // The public constant's string value is stable, but Swift 6 treats
            // the imported global CFStringRef as shared mutable state. Using the
            // documented dictionary key value avoids that concurrency warning.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }

        return AXIsProcessTrusted()
    }
}
