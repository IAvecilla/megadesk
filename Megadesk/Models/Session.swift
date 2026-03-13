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
    /// For Bash: checks the process tree — when the confirmation dialog is showing,
    /// Bash hasn't launched yet so there's no child process under claude.
    /// When Bash is legitimately running it appears as a child of the claude process.
    var needsConfirmation: Bool {
        guard isWorking && lastEvent == "PreToolUse" else { return false }
        guard Date().timeIntervalSince1970 - lastUpdated > 4 else { return false }
        if toolName == "Bash" {
            guard let pid = claudePid else { return false }
            return !hasChildProcess(parentPid: pid)
        }
        return true
    }

    /// Returns true if the given PID has at least one child process.
    /// Uses proc_listchildpids to list child PIDs into a buffer —
    /// returns the number of bytes filled, so > 0 means at least one child exists.
    private func hasChildProcess(parentPid: Int32) -> Bool {
        var pid: pid_t = 0
        let bytes = proc_listchildpids(parentPid, &pid, Int32(MemoryLayout<pid_t>.size))
        return bytes > 0
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
