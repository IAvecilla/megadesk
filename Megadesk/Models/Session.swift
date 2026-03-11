import Foundation

/// Caches child-process counts so that `Session.needsConfirmation` never
/// spawns a process on the main thread.  StatusStore calls `refresh(pids:)`
/// every second from its timer; the actual `pgrep` calls run on a background
/// queue and the results are swapped in atomically.
final class ChildProcessCache {
    static let shared = ChildProcessCache()

    private let queue = DispatchQueue(label: "megadesk.childproc", qos: .utility)
    private var cache: [Int32: Int] = [:]
    private let lock = NSLock()

    func childCount(pid: Int32) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cache[pid] ?? 0
    }

    /// Called by StatusStore on its 1-second timer.
    func refresh(pids: Set<Int32>) {
        queue.async { [weak self] in
            var results: [Int32: Int] = [:]
            for pid in pids {
                results[pid] = Self.pgrepChildCount(pid: pid)
            }
            self?.lock.lock()
            self?.cache = results
            self?.lock.unlock()
        }
    }

    /// Uses `pgrep -P` because sysctl(KERN_PROC_PPID) returns EOPNOTSUPP on
    /// macOS Sequoia+.
    private static func pgrepChildCount(pid: Int32) -> Int {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-P", "\(pid)"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return 0 }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.split(separator: "\n").count
        } catch {
            return 0
        }
    }
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
    let claudePid: Int32?
    let childCount: Int

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
    /// Compares the child-process count at PreToolUse time (snapshotted by the hook)
    /// against the live count (cached by StatusStore). If new children appeared,
    /// the tool started executing. If the count is unchanged, it's still waiting
    /// for user confirmation.
    /// For non-Bash tools (Agent, etc.) that run in-process without spawning
    /// children, a longer timeout avoids false positives.
    var needsConfirmation: Bool {
        guard isWorking && lastEvent == "PreToolUse" else { return false }
        let elapsed = Date().timeIntervalSince1970 - lastUpdated
        guard elapsed > 4 else { return false }
        guard let pid = claudePid else { return false }
        let liveCount = ChildProcessCache.shared.childCount(pid: pid)
        // More children now than at PreToolUse → tool started executing
        if liveCount > childCount {
            return false
        }
        // Same or fewer children: for Bash this means confirmation dialog is showing.
        // For other tools, use a longer timeout since they may run in-process.
        return toolName == "Bash" || elapsed > 30
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
        case claudePid = "claude_pid"
        case childCount = "child_count"
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
        claudePid = try c.decodeIfPresent(Int32.self, forKey: .claudePid)
        childCount = try c.decodeIfPresent(Int.self, forKey: .childCount) ?? 0
    }
}
