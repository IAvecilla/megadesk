import AppKit
import Foundation

enum HookInstaller {

    private static let hookCommand = "python3 ~/.claude/megadesk-hook.py"
    private static let hookDest    = FileManager.default.homeDirectoryForCurrentUser
                                        .appendingPathComponent(".claude/megadesk-hook.py")
    private static let settingsURL = FileManager.default.homeDirectoryForCurrentUser
                                        .appendingPathComponent(".claude/settings.json")

    /// Returns true if the megadesk hook is already registered in settings.json.
    static func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            "\(value)".contains(hookCommand)
        }
    }

    /// Shows a prompt and installs if the user agrees. Call on first launch.
    static func installIfNeeded() {
        guard !isInstalled() else { return }

        let alert = NSAlert()
        alert.messageText = "Set up Megadesk"
        alert.informativeText = "Megadesk needs to add hooks to Claude Code to track session activity.\n\nThis will modify ~/.claude/settings.json."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try install()
            let done = NSAlert()
            done.messageText = "Megadesk is ready"
            done.informativeText = "Hooks installed. Open a new Claude Code session to start tracking."
            done.addButton(withTitle: "OK")
            done.runModal()
        } catch {
            let err = NSAlert()
            err.messageText = "Installation failed"
            err.informativeText = error.localizedDescription
            err.alertStyle = .critical
            err.addButton(withTitle: "OK")
            err.runModal()
        }
    }

    // MARK: - Private

    private static func install() throws {
        let fm = FileManager.default
        let claudeDir = hookDest.deletingLastPathComponent()

        // Create ~/.claude if needed
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // Copy bundled hook script
        guard let bundledHook = Bundle.main.url(forResource: "megadesk-hook", withExtension: "py") else {
            throw InstallError.hookScriptNotFound
        }
        if fm.fileExists(atPath: hookDest.path) {
            try fm.removeItem(at: hookDest)
        }
        try fm.copyItem(at: bundledHook, to: hookDest)

        // Patch settings.json
        try patchSettings()
    }

    private static func patchSettings() throws {
        let fm = FileManager.default
        var settings: [String: Any]

        if fm.fileExists(atPath: settingsURL.path),
           let data = try? Data(contentsOf: settingsURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        } else {
            settings = [:]
        }

        let hookEntry: [String: Any] = ["type": "command", "command": hookCommand, "timeout": 3]
        let withMatcher:    [[String: Any]] = [["matcher": ".*", "hooks": [hookEntry]]]
        let withoutMatcher: [[String: Any]] = [["hooks": [hookEntry]]]

        let events: [String: [[String: Any]]] = [
            "PreToolUse":       withMatcher,
            "PostToolUse":      withMatcher,
            "Stop":             withoutMatcher,
            "UserPromptSubmit": withoutMatcher,
            "SessionStart":     withoutMatcher,
        ]

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, config) in events {
            let existing = "\(hooks[event] ?? "")"
            if !existing.contains(hookCommand) {
                let current = hooks[event] as? [[String: Any]] ?? []
                hooks[event] = current + config
            }
        }
        settings["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        let tmp  = settingsURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try fm.replaceItemAt(settingsURL, withItemAt: tmp)
    }
}

private enum InstallError: LocalizedError {
    case hookScriptNotFound
    var errorDescription: String? {
        "megadesk-hook.py was not found inside the app bundle."
    }
}
