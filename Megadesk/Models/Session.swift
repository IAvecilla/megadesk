import Foundation
import Darwin

enum TerminalType: String, Codable {
    case iterm2 = "iterm2"
    case ghostty = "ghostty"
    case unknown = "unknown"
}

struct Session: Identifiable, Codable {
    let sessionId: String
    let cwd: String
    let state: String
    let stateSince: Double
    let createdAt: Double?
    let lastUpdated: Double
    let toolName: String
    let lastEvent: String
    let itermSessionId: String
    let terminal: TerminalType
    let claudePid: Int32?
    let ghosttyTerminalId: String

    var id: String { sessionId }

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var isWorking: Bool { state == "working" }

    var isStale: Bool {
        Date().timeIntervalSince1970 - lastUpdated > 300
    }

    var timeInState: TimeInterval {
        Date().timeIntervalSince1970 - stateSince
    }

    /// True when Claude is waiting for the user to approve/deny a tool call.
    /// For non-Bash tools: >4s since PreToolUse with no update is conclusive.
    /// For Bash: checks whether any child process was spawned *after* the PreToolUse
    /// timestamp. MCP servers (GitHub, sourcekit-lsp, etc.) are long-running children
    /// started at session begin, so they must be excluded from the check.
    var needsConfirmation: Bool {
        guard isWorking && lastEvent == "PreToolUse" else { return false }
        guard Date().timeIntervalSince1970 - lastUpdated > 4 else { return false }
        if toolName == "Bash" {
            guard let pid = claudePid else { return false }
            return !hasChildStartedAfter(parentPid: pid, timestamp: lastUpdated)
        }
        return true
    }

    /// Returns true if any child of `parentPid` was started after `timestamp`.
    /// Uses proc_listchildpids to enumerate children, then proc_pidinfo to
    /// read each child's start time.
    private func hasChildStartedAfter(parentPid: Int32, timestamp: Double) -> Bool {
        let maxChildren = 64
        let buffer = UnsafeMutablePointer<pid_t>.allocate(capacity: maxChildren)
        defer { buffer.deallocate() }

        let bytes = proc_listchildpids(parentPid, buffer, Int32(maxChildren * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return false }

        let count = Int(bytes) / MemoryLayout<pid_t>.size
        for i in 0..<count {
            var info = proc_bsdinfo()
            let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(buffer[i], PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize {
                let startTime = Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000.0
                if startTime > timestamp {
                    return true
                }
            }
        }
        return false
    }

    /// Session has been in "waiting" state for longer than the configured threshold — effectively idle.
    var isForgotten: Bool {
        !isWorking && timeInState > TimeInterval(AppSettings.shared.forgottenMinutes * 60)
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case state
        case stateSince = "state_since"
        case createdAt = "created_at"
        case lastUpdated = "last_updated"
        case toolName = "tool_name"
        case lastEvent = "last_event"
        case itermSessionId = "iterm_session_id"
        case terminal
        case claudePid = "claude_pid"
        case ghosttyTerminalId = "ghostty_terminal_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        cwd = try c.decode(String.self, forKey: .cwd)
        state = try c.decode(String.self, forKey: .state)
        stateSince = try c.decode(Double.self, forKey: .stateSince)
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt)
        lastUpdated = try c.decode(Double.self, forKey: .lastUpdated)
        toolName = try c.decode(String.self, forKey: .toolName)
        lastEvent = try c.decode(String.self, forKey: .lastEvent)
        itermSessionId = try c.decode(String.self, forKey: .itermSessionId)
        terminal = try c.decodeIfPresent(TerminalType.self, forKey: .terminal) ?? .iterm2
        claudePid = try c.decodeIfPresent(Int32.self, forKey: .claudePid)
        ghosttyTerminalId = try c.decodeIfPresent(String.self, forKey: .ghosttyTerminalId) ?? ""
    }
}
