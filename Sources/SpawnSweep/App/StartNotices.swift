import Foundation

/// What showed up since earlier scans. The first update only learns what's already there, so launching SpawnSweep
/// announces nothing. After that a key is announced once it has been seen for `settle` seconds, so a one-off
/// `claude -p` or a simulator that boots and quits right away never is. A key that goes away is forgotten, and
/// announced again when it comes back.
struct Arrivals {
    private var known: Set<String>?
    private var firstSeen: [String: Date] = [:]

    mutating func update(_ present: Set<String>, at now: Date, settle: TimeInterval = 5) -> Set<String> {
        guard var known else { self.known = present; return [] }
        known.formIntersection(present)
        firstSeen = firstSeen.filter { present.contains($0.key) }
        var fresh = Set<String>()
        for key in present.subtracting(known) {
            let seen = firstSeen[key] ?? now
            if now.timeIntervalSince(seen) >= settle { fresh.insert(key); firstSeen[key] = nil } else { firstSeen[key] = seen }
        }
        self.known = known.union(fresh)
        return fresh
    }
}

extension AppModel {
    /// After every scan: one notification per kind for agent sessions, booted simulators and worktrees that started
    /// since the last scans. A switch that's off resets its tracker, so turning it on later starts quietly.
    func noticeStarts(worktrees: [Worktree], now: Date = Date()) {
        func track(_ a: inout Arrivals, _ on: Bool, _ keys: Set<String>) -> Set<String> {
            guard on else { a = Arrivals(); return [] }
            return a.update(keys, at: now)
        }
        let p = prefs
        let agents = workspace.agentFolders
        let sessions = track(&sessionArrivals, p.notifyNewSessions, Set(agents.keys)).sorted()
        let booted = workspace.devices.filter(\.booted)
        let devices = track(&deviceArrivals, p.notifyNewSimulators, Set(booted.map(\.udid)))
        let byPath = Dictionary(worktrees.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        var newTrees = track(&worktreeArrivals, p.notifyNewWorktrees, Set(byPath.keys))
        // An agent that starts in a worktree it just made gets one notification, not two. Codex's session folder is
        // the worktree's parent (~/.codex/worktrees/<id>/<repo>), so either may hold the other.
        let inNewTree = Set(sessions.filter { f in newTrees.contains { Scanner.inside($0, f) || Scanner.inside(f, $0) } })
        newTrees = newTrees.filter { w in !inNewTree.contains { Scanner.inside(w, $0) || Scanner.inside($0, w) } }

        let id = "start:\(Int(now.timeIntervalSince1970))"
        func tilde(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
        if let f = sessions.first, let agent = agents[f] {
            let one = sessions.count == 1
            Notifier.shared.post(
                id: id + ":sessions",
                title: one ? "\(agent.rawValue) started in \(Scanner.projectName(f))" : "\(sessions.count) agent sessions started",
                body: one ? (inNewTree.contains(f) ? "New worktree · " : "") + tilde(f)
                          : sessions.map { "\(agents[$0]?.rawValue ?? "Agent") in \(Scanner.projectName($0))" }.joined(separator: ", "),
                actionable: false, open: one ? "session:" + f : "sessions")
        }
        let started = booted.filter { devices.contains($0.udid) }.sorted { $0.name < $1.name }
        if let d = started.first {
            let noun = started.allSatisfy(\.android) ? "emulators" : started.contains(where: \.android) ? "devices" : "simulators"
            Notifier.shared.post(id: id + ":devices",
                                 title: started.count == 1 ? "\(d.name) booted" : "\(started.count) \(noun) booted",
                                 body: started.count == 1 ? d.runtime : started.map(\.name).joined(separator: ", "),
                                 actionable: false, open: "devices")
        }
        let trees = newTrees.compactMap { byPath[$0] }.sorted { $0.path < $1.path }
        if let w = trees.first {
            let one = trees.count == 1
            Notifier.shared.post(id: id + ":worktrees",
                                 title: one ? "New worktree in \(w.repoName)" : "\(trees.count) new worktrees",
                                 body: one ? "\(w.branch ?? "Detached") · \(tilde(w.path))"
                                           : trees.map { "\($0.repoName) / \($0.branch ?? "detached")" }.joined(separator: ", "),
                                 actionable: false, open: one ? "repo:" + w.repoPath : "storage")
        }
    }

    /// Clicking a start notification: the session, the devices list, or the repo's worktrees.
    func openStart(_ target: String) {
        openMainWindow()
        if target.hasPrefix("session:"), session(String(target.dropFirst(8))) != nil {
            openSession(String(target.dropFirst(8)))
        } else if target == "devices" {
            go(.resources)
        } else if target.hasPrefix("repo:") || target == "storage" {
            refreshDisk()   // Storage only learns about a new worktree from the disk scan
            if target == "storage" { go(.storage) } else { openRepo(String(target.dropFirst(5))) }
        } else {
            go(.sessions)   // a session shows there once it starts something
        }
    }
}
