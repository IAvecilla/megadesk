import Foundation
import AppKit

struct TerminalFocuser {

    /// Focuses the correct terminal tab/session based on the session's terminal type.
    /// Returns true if the terminal was found and focused.
    @discardableResult
    static func focus(session: Session) -> Bool {
        switch session.terminal {
        case .iterm2:
            return focusiTerm2(sessionId: session.itermSessionId)
        case .ghostty:
            return focusGhostty(cwd: session.cwd, tty: session.tty)
        case .unknown:
            return false
        }
    }

    // MARK: - iTerm2

    @discardableResult
    static func focusiTerm2(sessionId: String) -> Bool {
        // sessionId is the bare UUID (hook script strips the "w0t0p0:" prefix).
        // Inside tmux the format is "{uuid}:{tmux_pane}" — strip the suffix.
        let rawId = sessionId.components(separatedBy: ":").first ?? sessionId
        guard !rawId.isEmpty else { return false }

        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is "\(rawId)" then
                            tell t to select
                            tell s to select
                            tell w to select
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if let error {
                print("[Megadesk] AppleScript error: \(error)")
                showPermissionAlert(terminal: "iTerm2")
                return false
            }
            return result.booleanValue
        }
        return false
    }

    // MARK: - Ghostty
    //
    // Ghostty does not yet provide per-tab/session IDs or an AppleScript dictionary
    // for focusing individual tabs (see https://github.com/ghostty-org/ghostty/discussions/10603).
    // As a workaround, we use the macOS Accessibility API (System Events) to:
    //   1. Click each tab's radio button and read the AXImage element in the title bar,
    //      which reflects the focused pane's working directory name.
    //   2. For tabs with split panes, cycle through panes using Cmd+] (goto_split:next)
    //      to read each pane's directory, then restore the original pane.
    //   3. Cache this tab→directories mapping so subsequent focuses are instant.
    //   4. For multiple tabs in the same directory, assign each session's TTY to a
    //      different tab index.
    //
    // Split pane support: the scan discovers all pane directories per tab, so clicking
    // a session card focuses the correct tab even if the session is in a non-focused pane.
    // Pane-level focus within a tab is not possible — Ghostty doesn't expose per-pane
    // identifiers or AX actions for direct pane focus. Depends on the default Cmd+]
    // keybinding (goto_split:next); if remapped, falls back to single-directory behavior.
    //
    // When Ghostty adds GHOSTTY_SESSION_ID or native AppleScript tab focusing,
    // this workaround can be replaced with a direct lookup like iTerm2 uses.

    /// Info about a single Ghostty tab, including directories from all panes.
    private struct GhosttyTabInfo {
        let directories: Set<String>
    }

    /// Cached mapping of tab index (1-based) → tab info with all pane directories.
    /// Invalidated when the tab count changes.
    private static var ghosttyTabMap: [Int: GhosttyTabInfo] = [:]
    private static var ghosttyTabCount: Int = 0

    /// Tracks which tab index each TTY was assigned to for same-directory disambiguation.
    private static var ttyTabAssignments: [String: Int] = [:]

    /// Focuses the Ghostty tab whose working directory matches the session's cwd.
    ///
    /// Uses a cached tab→directory mapping so that only the first focus (or after
    /// tab count changes) requires scanning all tabs. Subsequent focuses click the
    /// target tab directly with no flicker.
    @discardableResult
    static func focusGhostty(cwd: String, tty: String) -> Bool {
        let projectName = URL(fileURLWithPath: cwd).lastPathComponent

        // Check if cache is still valid by comparing tab count
        let currentTabCount = getGhosttyTabCount()
        if currentTabCount != ghosttyTabCount || ghosttyTabMap.isEmpty {
            rebuildGhosttyTabMap()
        }

        // Find all tabs matching this directory (check all pane directories per tab)
        let matches = ghosttyTabMap.filter { $0.value.directories.contains(projectName) }.map(\.key).sorted()

        if matches.isEmpty {
            // Cache might be stale — force rebuild and retry once
            rebuildGhosttyTabMap()
            let retryMatches = ghosttyTabMap.filter { $0.value.directories.contains(projectName) }.map(\.key).sorted()
            if retryMatches.isEmpty { return false }
            return selectGhosttyTab(matches: retryMatches, tty: tty)
        }

        return selectGhosttyTab(matches: matches, tty: tty)
    }

    /// Returns the current number of Ghostty tabs (fast, no tab switching).
    private static func getGhosttyTabCount() -> Int {
        let script = """
        tell application "System Events"
            tell process "Ghostty"
                try
                    return count of radio buttons of tab group 1 of window 1
                end try
            end tell
        end tell
        return 0
        """
        var error: NSDictionary?
        if let as_ = NSAppleScript(source: script) {
            let result = as_.executeAndReturnError(&error)
            if error == nil { return Int(result.int32Value) }
        }
        return 0
    }

    /// Scans all Ghostty tabs by clicking each and reading the AXImage title,
    /// then restores the originally-active tab. For tabs with split panes,
    /// cycles through panes using Cmd+] to read each pane's directory.
    ///
    /// Uses JXA (JavaScript for Automation) instead of AppleScript because
    /// AppleScript's System Events resolves `window 1` references by title.
    /// Clicking a tab changes the window title, making cached refs stale
    /// (error -1728). JXA uses stable index-based object proxies.
    private static func rebuildGhosttyTabMap() {
        let jxa = """
        (() => {
            const se = Application("System Events");
            const p = se.processes["Ghostty"];
            const tg = p.windows[0].tabGroups[0];
            const n = tg.radioButtons.length;
            if (n === 0) return "";

            // Remember active tab
            let orig = -1;
            for (let i = 0; i < n; i++) {
                if (tg.radioButtons[i].value() === 1) { orig = i; break; }
            }

            // Helper: read AXImage title (directory name) from the current window state.
            // Must re-fetch p.windows[0] each time — refs go stale after tab/pane changes.
            function readDirName() {
                try {
                    const w = p.windows[0];
                    const imgs = w.uiElements.whose({ role: "AXImage" })();
                    for (const el of imgs) {
                        try { return el.title(); } catch(e) {}
                    }
                } catch(e) {}
                return "";
            }

            // Helper: count split panes in the current tab's content area.
            // The content area's inner AXGroup contains N AXGroup children (panes)
            // plus AXButton elements (splitters).
            function countPanes() {
                try {
                    const w = p.windows[0];
                    // Navigate to the content area: window > AXGroup (content) > AXGroup (inner)
                    const groups = w.groups;
                    for (let g = 0; g < groups.length; g++) {
                        const inner = groups[g].groups;
                        if (inner.length > 0) {
                            let count = 0;
                            const children = inner[0].uiElements();
                            for (let c = 0; c < children.length; c++) {
                                try {
                                    if (children[c].role() === "AXGroup") count++;
                                } catch(e) {}
                            }
                            if (count > 0) return count;
                        }
                    }
                } catch(e) {}
                return 1;
            }

            // Scan each tab: click it, count panes, read all pane directories
            let results = [];
            for (let i = 0; i < n; i++) {
                tg.radioButtons[i].click();
                delay(0.03);

                let dirs = [];
                const dir0 = readDirName();
                if (dir0) dirs.push(dir0);

                const paneCount = countPanes();
                if (paneCount > 1) {
                    // Cycle through remaining panes with Cmd+]
                    const ghostty = Application("Ghostty");
                    for (let pi = 1; pi < paneCount; pi++) {
                        se.keystroke("]", { using: "command down" });
                        delay(0.05);
                        const d = readDirName();
                        if (d) dirs.push(d);
                    }
                    // One more Cmd+] to restore original pane focus
                    se.keystroke("]", { using: "command down" });
                    delay(0.03);
                }

                // Deduplicate and join with pipe separator
                const unique = [...new Set(dirs)];
                results.push((i + 1) + ":" + unique.join("|"));
            }

            // Restore original tab
            if (orig >= 0) tg.radioButtons[orig].click();

            return results.join(",");
        })()
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", jxa]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else {
            return
        }

        var newMap: [Int: GhosttyTabInfo] = [:]
        for entry in str.split(separator: ",") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let idx = Int(parts[0]) {
                let dirs = String(parts[1]).split(separator: "|").map(String.init)
                newMap[idx] = GhosttyTabInfo(directories: Set(dirs))
            }
        }

        ghosttyTabMap = newMap
        ghosttyTabCount = newMap.count
        ttyTabAssignments.removeAll()
    }

    /// Clicks the correct tab from a list of matching indices, using TTY
    /// to disambiguate when multiple tabs share the same directory.
    private static func selectGhosttyTab(matches: [Int], tty: String) -> Bool {
        let targetIndex: Int
        if matches.count == 1 {
            targetIndex = matches[0]
        } else if !tty.isEmpty {
            let usedIndices = Set(ttyTabAssignments.values)
            if let existing = ttyTabAssignments[tty], matches.contains(existing) {
                targetIndex = existing
            } else {
                let available = matches.first { !usedIndices.contains($0) } ?? matches[0]
                ttyTabAssignments[tty] = available
                targetIndex = available
            }
        } else {
            targetIndex = matches[0]
        }

        let clickScript = """
        tell application "Ghostty" to activate
        tell application "System Events"
            tell process "Ghostty"
                set frontmost to true
                try
                    set tg to tab group 1 of window 1
                    click radio button \(targetIndex) of tg
                    perform action "AXRaise" of window 1
                    return true
                end try
            end tell
        end tell
        return false
        """

        var error: NSDictionary?
        if let as_ = NSAppleScript(source: clickScript) {
            let result = as_.executeAndReturnError(&error)
            if error != nil { return false }
            return result.booleanValue
        }
        return false
    }

    // MARK: - Permissions

    private static var hasShownPermissionAlert = false

    private static func showPermissionAlert(terminal: String) {
        guard !hasShownPermissionAlert else { return }
        hasShownPermissionAlert = true
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Megadesk needs Automation permission"
            alert.informativeText = "Megadesk needs permission to control \(terminal).\nGo to System Settings → Privacy & Security → Automation → enable \(terminal) under Megadesk."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
