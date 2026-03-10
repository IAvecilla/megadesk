import Foundation

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

    /// Last hook was PreToolUse for a non-Bash tool and nothing has updated in >4s —
    /// Claude is almost certainly waiting for the user to approve/deny a confirmation.
    /// Bash is excluded because it can run legitimately for minutes.
    var needsConfirmation: Bool {
        guard isWorking && lastEvent == "PreToolUse" else { return false }
        return Date().timeIntervalSince1970 - lastUpdated > 4
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
