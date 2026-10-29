import Foundation

/// Agent connections: detection, the Claude Code session-end hook, and the MCP server config.
enum Integrations {
    static let home = Shell.home

    /// Path of this binary, used in hook and MCP commands.
    static var executablePath: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }

    static var hookCommand: String { "\(Shell.quote(executablePath)) --session-end" }
    static var mcpCommand: String { "claude mcp add --scope user spawnsweep -- \(Shell.quote(executablePath)) --mcp" }

    /// What gets merged into ~/.claude/settings.json.
    static var hookSnippet: String {
        """
        "hooks": {
          "SessionEnd": [
            { "hooks": [ { "type": "command", "command": "\(hookCommand.replacingOccurrences(of: "\"", with: "\\\""))" } ] }
          ]
        }
        """
    }

    enum Status: Equatable { case connected(String), available(String), notFound }

    static func status(of agent: Agent) -> Status {
        let fm = FileManager.default
        switch agent {
        case .claudeCode:
            if claudeHookInstalled() { return .connected("Session-end hook installed") }
            return fm.fileExists(atPath: home + "/.claude") ? .available("Session-end hook available") : .notFound
        case .codex:
            return (fm.fileExists(atPath: home + "/.codex") || Shell.which("codex") != nil)
                ? .connected("Session tracking enabled") : .notFound
        case .cursor:
            return (fm.fileExists(atPath: "/Applications/Cursor.app") || fm.fileExists(atPath: home + "/.cursor"))
                ? .available("Workspace tracking available") : .notFound
        case .claudeApp:
            return fm.fileExists(atPath: "/Applications/Claude.app")
                ? .connected("Merged worktrees can be recycled here") : .notFound
        case .gemini, .aider:
            return (Shell.which("gemini") != nil || Shell.which("aider") != nil)
                ? .connected("Session tracking enabled") : .available("Connect local agent sessions")
        default:
            return .notFound
        }
    }

    static var claudeSettingsPath: String { home + "/.claude/settings.json" }

    static func claudeHookInstalled() -> Bool {
        guard let s = try? String(contentsOfFile: claudeSettingsPath, encoding: .utf8) else { return false }
        return s.contains("--session-end") && s.contains("SessionEnd")
    }

    /// Adds the SessionEnd hook to ~/.claude/settings.json, keeping everything else. Writes a .bak first.
    static func installClaudeHook() throws -> String {
        try editClaudeSettings { end in
            end = withoutOurHook(end)
            end.append(["hooks": [["type": "command", "command": hookCommand]]])
        }
    }

    static func removeClaudeHook() throws {
        _ = try editClaudeSettings { end in end = withoutOurHook(end) }
    }

    /// Only SpawnSweep's own entry goes; other tools' hooks, even in the same group, stay.
    static func withoutOurHook(_ groups: [[String: Any]]) -> [[String: Any]] {
        func ours(_ h: [String: Any]) -> Bool {
            guard let c = h["command"] as? String else { return false }
            return c == hookCommand || (c.contains("--session-end") && c.contains("SpawnSweep"))
        }
        return groups.compactMap { group in
            guard let hs = group["hooks"] as? [[String: Any]] else { return group }
            let kept = hs.filter { !ours($0) }
            if kept.count == hs.count { return group }
            if kept.isEmpty { return nil }
            var g = group; g["hooks"] = kept; return g
        }
    }

    /// Reads settings.json, changes only hooks.SessionEnd, and writes it back through any symlink with its
    /// permissions kept. Leaves the file alone if it, `hooks` or `SessionEnd` isn't the shape it expects.
    private static func editClaudeSettings(_ change: (inout [[String: Any]]) -> Void) throws -> String {
        let fm = FileManager.default
        let target = URL(fileURLWithPath: claudeSettingsPath).resolvingSymlinksInPath()
        let refuse = { (why: String) in NSError(domain: "SpawnSweep", code: 1, userInfo: [NSLocalizedDescriptionKey: why + " It was left alone."]) }
        var json: [String: Any] = [:]
        var perms: Any?
        if let data = fm.contents(atPath: target.path) {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw refuse("settings.json isn't a JSON object.") }
            json = obj
            perms = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
            try? fm.removeItem(atPath: claudeSettingsPath + ".bak")
            try fm.copyItem(atPath: target.path, toPath: claudeSettingsPath + ".bak")
        }
        if json["hooks"] != nil && !(json["hooks"] is [String: Any]) { throw refuse("settings.json has hooks in a shape SpawnSweep doesn't know.") }
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        if hooks["SessionEnd"] != nil && !(hooks["SessionEnd"] is [[String: Any]]) { throw refuse("settings.json has SessionEnd hooks in a shape SpawnSweep doesn't know.") }
        var end = hooks["SessionEnd"] as? [[String: Any]] ?? []
        change(&end)
        hooks["SessionEnd"] = end.isEmpty ? nil : end
        json["hooks"] = hooks.isEmpty ? nil : hooks
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let out = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: target, options: .atomic)
        if let perms { try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: target.path) }
        return claudeSettingsPath + ".bak"
    }

    static func mcpConfigured() -> Bool {
        guard let s = try? String(contentsOfFile: home + "/.claude.json", encoding: .utf8) else { return false }
        return s.contains("\"spawnsweep\"")
    }

    /// Registers the MCP server with Claude Code's CLI, if it's installed.
    static func addMCPToClaudeCode() -> Shell.Result {
        guard Shell.which("claude") != nil else { return Shell.Result(code: 127, out: "", err: "The claude command isn't on this Mac's PATH. Copy the command and run it in a terminal.") }
        return Shell.run("claude", ["mcp", "add", "--scope", "user", "spawnsweep", "--", executablePath, "--mcp"], timeout: 30)
    }
}
