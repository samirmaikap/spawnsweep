import Foundation

/// `--scan --json`: what the fast scan sees, as JSON for other tools (the SpawnSweep pane for Claude among them).
/// Version 1. Times are ISO 8601 and sizes are bytes. Fields are only ever added; a change that breaks a reader bumps
/// `version`.
extension CLI {
    static func printScanJSON() {
        let ws = scanNow()
        let prefs = Store.loadState().prefs
        // The disk scan also finds repos through agent worktree folders (~/.codex/worktrees, …); its cache has them.
        let known = Set((Store.loadDisk()?.repos ?? []).map(\.path))
        let worktrees = DiskScanner.linkedWorktrees(repos: DiskScanner.findRepos(prefs).union(known))
        let data = try! JSONSerialization.data(withJSONObject: scanJSON(ws, worktrees: worktrees),
                                               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        print(String(decoding: data, as: UTF8.self))
    }

    /// The JSON object, apart from the scanning, so the self-test can check it.
    static func scanJSON(_ ws: Workspace, worktrees: [Worktree]) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        func date(_ d: Date?) -> Any { d.map { iso.string(from: $0) } ?? NSNull() }
        func resource(_ r: Resource) -> [String: Any] {
            ["kind": r.kind.rawValue, "title": r.title, "detail": r.detail, "ports": r.ports, "memoryBytes": r.memoryBytes,
             "startedAt": date(r.startedAt), "cwd": r.cwd ?? NSNull()]
        }
        // A worktree is in use while a session or a live agent works in it.
        let busy = ws.sessions.map(\.folder) + ws.agentFolders.keys
        func inUse(_ path: String) -> Bool { busy.contains { DiskScanner.samePath($0, path) || $0.hasPrefix(path + "/") } }

        return [
            "version": 1,
            "scannedAt": date(ws.scannedAt),
            "running": ws.allResources.count,
            "ports": ws.openPorts.sorted(),
            "sessions": ws.sessions.map { s -> [String: Any] in
                let (state, since): (String, Date?) = {
                    switch s.state {
                    case .active: return ("active", nil)
                    case .idle(let d): return ("idle", d)
                    case .ended(let d): return ("ended", d)
                    }
                }()
                return ["project": s.project, "agent": s.agent.rawValue, "folder": s.folder, "branch": s.branch ?? NSNull(),
                        "state": state, "since": date(since), "pinned": s.pinned, "resources": s.resources.map(resource)]
            },
            "unattached": ws.unattached.map(resource),
            "simulators": ws.devices.filter(\.booted).map { ["name": $0.name, "runtime": $0.runtime, "bootedAt": date($0.bootedAt)] },
            "worktrees": worktrees.sorted { $0.path < $1.path }.map { w -> [String: Any] in
                ["repo": w.repoName, "repoPath": w.repoPath, "path": w.path, "branch": w.branch ?? NSNull(),
                 "agent": (w.agent ?? Scanner.worktreeFolder(w.path + "/")?.1)?.rawValue ?? NSNull(), "inUse": inUse(w.path)]
            },
        ]
    }

    /// `scanJSON` turns into JSON a reader can rely on: every field there, nulls where nothing is known.
    static func selfTestScanJSON() {
        let r = Resource(id: "r", kind: .server, title: "Vite :5173", detail: "Server", ports: [5173], memoryBytes: 12_000_000,
                         cwd: "/w/app")
        let s = Session(folder: "/w/app", project: "app", branch: "main", agent: .claudeCode, state: .idle(since: Date(timeIntervalSince1970: 0)),
                        resources: [r], agentPids: [], startedAt: nil, lastActivity: nil, pinned: false, isWorktree: false)
        var ws = Workspace(sessions: [s], scannedAt: Date(timeIntervalSince1970: 60))
        ws.agentFolders = ["/w/app-feature": .codex]
        let wt = Worktree(path: "/w/app-feature", repoPath: "/w/app", repoName: "app", branch: "feature", head: "")
        let data = try! JSONSerialization.data(withJSONObject: scanJSON(ws, worktrees: [wt]), options: .sortedKeys)
        let back = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        assert(back["version"] as? Int == 1 && back["running"] as? Int == 1 && back["ports"] as? [Int] == [5173], "scan json totals: \(back)")
        let session = (back["sessions"] as! [[String: Any]])[0]
        assert(session["state"] as? String == "idle" && session["since"] as? String == "1970-01-01T00:00:00Z", "scan json session: \(session)")
        assert((session["resources"] as! [[String: Any]])[0]["memoryBytes"] as? Int == 12_000_000, "scan json resource")
        let w = (back["worktrees"] as! [[String: Any]])[0]
        assert(w["branch"] as? String == "feature" && w["inUse"] as? Bool == true, "scan json worktree: \(w)")
        assert(back["unattached"] as? [Any] != nil && back["simulators"] as? [Any] != nil, "scan json lists")
    }
}
