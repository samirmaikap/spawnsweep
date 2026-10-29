import Foundation

/// Remembers which running processes an agent started, so they still count as the agent's
/// after the agent itself exits and the process is re-parented to launchd.
struct AgentMark: Codable, Hashable {
    let folder: String
    let agent: Agent
    let start: Double
}

/// Builds a `Workspace` snapshot: sessions, the resources they left running, devices, stacks, tunnels.
enum Scanner {
    static let home = Shell.home
    static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "login", "tmux", "screen", "disclaimer",
                                      "sandbox-exec", "launchd", "Terminal", "iTerm2", "ghostty", "Warp", "kitty",
                                      "alacritty", "wezterm-gui", "nohup", "env", "script", "sudo"]
    static let worktreeMarkers: [(String, Agent)] = [
        ("/.claude/worktrees/", .claude), ("/.codex/worktrees/", .codex),
        ("/.cursor/worktrees/", .cursor), ("/conductor/workspaces/", .claude)
    ]
    static let tunnelTools: Set<String> = ["ngrok", "cloudflared", "lt", "bore", "localtunnel", "zrok"]

    struct Result {
        var workspace: Workspace
        var marks: [String: AgentMark]
    }

    static func scan(prefs: Prefs, marks oldMarks: [String: AgentMark], withStats: Bool) -> Result {
        let table = ProcessTable()
        var marks = oldMarks.filter { key, mark in
            guard let pid = Int32(key), let p = table[pid] else { return false }
            return abs(p.start - mark.start) < 1
        }

        // 1. Live agents.
        var agentFolder: [Int32: (folder: String, agent: Agent)] = [:]
        for (pid, p) in table.procs {
            guard let agent = agent(of: p, table: table), let cwd = table.cwd(pid),
                  cwd != home, cwd != "/", cwd.hasPrefix(home) else { continue }
            agentFolder[pid] = (sessionRoot(cwd), agent)
        }
        func agentAncestor(_ pid: Int32) -> Int32? { table.ancestors(of: pid).first { agentFolder[$0] != nil } }

        // 2. Process resources: servers, watchers, browsers, tunnels.
        var resources: [Resource] = []
        var claimed = Set<Int32>()
        let listeners = ProcessTable.listeners()
        var portsByRoot: [Int32: [Int]] = [:]
        let daemons: Set<String> = ["adb", "watchman", "launchd_sim", "Code Helper", "git", "ssh", "gpg-agent"]
        for l in listeners {
            guard let p = table[l.pid], isUserProject(p, table), !daemons.contains(p.name) else { continue }
            if agentFolder[l.pid] != nil { continue }
            let root = climb(l.pid, table, agents: agentFolder)
            portsByRoot[root, default: []].append(l.port)
        }
        for (root, ports) in portsByRoot {
            guard let p = table[root] else { continue }
            let tree = [root] + table.descendants(of: root)
            tree.forEach { claimed.insert($0) }
            let commands = tree.compactMap { table[$0]?.command }.joined(separator: " ")
            let name = framework(commands, fallback: p.name)
            let uniquePorts = Array(Set(ports)).sorted()
            var r = Resource(id: "proc:\(root)", kind: .server,
                             title: "\(name) :\(uniquePorts.first ?? 0)",
                             detail: (tree.count > 1 ? "Server + child processes" : p.name) + " · " + Fmt.duration(p.elapsed),
                             ports: uniquePorts, memoryBytes: table.memory(tree),
                             startedAt: Date(timeIntervalSince1970: p.start), cwd: table.cwd(root),
                             processes: table.refs(tree), command: p.command)
            if tunnelTools.contains(p.name) { r.title = p.name }
            resources.append(r)
        }

        for (pid, p) in table.procs where !claimed.contains(pid) && agentFolder[pid] == nil {
            let kind: ResourceKind
            let title: String
            if tunnelTools.contains(p.name) || p.command.contains("localtunnel") {
                kind = .tunnel; title = p.name
            } else if !shells.contains(p.name), let w = watcherName(p.command), isUserProject(p, table) {
                kind = .watcher; title = w
            } else if isHeadlessBrowser(p) {
                kind = .browser; title = p.command.contains("ms-playwright") ? "Playwright browser" : "Headless Chrome"
            } else { continue }
            // Skip helper children of a browser or watcher we already counted.
            if table.ancestors(of: pid).contains(where: { claimed.contains($0) }) { continue }
            let root = kind == .watcher ? climb(pid, table, agents: agentFolder) : pid
            if claimed.contains(root) { continue }
            let tree = [root] + table.descendants(of: root)
            tree.forEach { claimed.insert($0) }
            var r = Resource(id: "proc:\(root)", kind: kind, title: title,
                             detail: shortCommand(table[root]?.command ?? p.command) + " · " + Fmt.duration(p.elapsed),
                             memoryBytes: table.memory(tree), startedAt: Date(timeIntervalSince1970: p.start),
                             cwd: table.cwd(root), processes: table.refs(tree), command: table[root]?.command)
            if kind == .tunnel { r.tunnelTarget = tunnelPort(p.command); r.detail = "→ localhost:\(r.tunnelTarget.map(String.init) ?? "?") · " + Fmt.duration(p.elapsed) }
            if kind == .browser {
                let pages = tree.filter { (table[$0]?.command.contains("--type=renderer")) == true }.count
                r.detail = "Headless Chromium" + (pages > 0 ? " · \(pages) page\(pages == 1 ? "" : "s")" : "") + " · " + Fmt.duration(p.elapsed)
            }
            resources.append(r)
        }

        // 3. Which agent made each resource?
        var owner: [String: (folder: String, agent: Agent, strength: LinkStrength)] = [:]
        for r in resources {
            guard let root = r.rootPid, let start = r.processes.first?.start else { continue }
            if let a = agentAncestor(root), let info = agentFolder[a] {
                owner[r.id] = (info.folder, info.agent, .strong)
                marks[String(root)] = AgentMark(folder: info.folder, agent: info.agent, start: start)
            } else if let m = marks[String(root)] {
                owner[r.id] = (m.folder, m.agent, .strong)
            } else if let cwd = r.cwd, let (folder, agent) = worktreeFolder(cwd) {
                // Only the folder ties it to an agent (one we may not see running, like the Codex app), so link it
                // weakly: it's shown with the session but never stopped by a sweep, a rule or the end-of-session hook.
                owner[r.id] = (folder, agent, .weak)
            }
        }

        // 4. Devices.
        var devices = simulators(table)
        devices += androidEmulators(table)
        for d in devices where d.booted {
            resources.append(Resource(id: "sim:\(d.udid)", kind: d.android ? .emulator : .simulator,
                                      title: d.name + (d.runtime.isEmpty ? "" : " · \(d.runtime)"),
                                      detail: "Booted " + Fmt.ago(d.bootedAt), memoryBytes: d.memoryBytes,
                                      startedAt: d.bootedAt, udid: d.android ? nil : d.udid))
        }

        // 5. Docker stacks.
        let stacks = dockerStacks(withStats: withStats)
        for s in stacks {
            let supabase = s.names.contains { $0.contains("supabase") }
            resources.append(Resource(id: "stack:\(s.project)", kind: .stack,
                                      title: supabase ? "Supabase local stack" : "\(s.project) stack",
                                      detail: "\(s.containers.count) container\(s.containers.count == 1 ? "" : "s") grouped as one stack",
                                      ports: s.ports, memoryBytes: s.memoryBytes, startedAt: s.startedAt,
                                      cwd: s.workingDir, containerIDs: s.containers, stackProject: s.project))
        }

        // 6. Sessions: one per folder with a live agent or agent-made leftovers.
        var folders: [String: (agent: Agent, pids: [Int32])] = [:]
        for (pid, info) in agentFolder { folders[info.folder, default: (info.agent, [])].pids.append(pid) }
        for (_, o) in owner where folders[o.folder] == nil { folders[o.folder] = (o.agent, []) }

        var sessionResources: [String: [Resource]] = [:]
        var unattached: [Resource] = []
        for var r in resources {
            r.protected = r.ports.contains(where: prefs.protectedPorts.contains)
            if let o = owner[r.id] {
                r.link = o.strength
                sessionResources[o.folder, default: []].append(r)
                continue
            }
            // Stacks and devices: link by folder or project name, but weakly, so sweeps leave them unticked.
            if r.kind == .stack, let folder = folders.keys.first(where: { f in
                (r.cwd.map { inside($0, f) } ?? false) || projectName(f) == r.stackProject }) {
                r.link = (r.cwd.map { inside($0, folder) } ?? false) ? .strong : .weak
                sessionResources[folder, default: []].append(r)
                continue
            }
            if (r.kind == .simulator || r.kind == .emulator), let booted = r.startedAt,
               let match = sessionResources.first(where: { _, rs in
                   rs.contains { $0.kind == .server && abs(($0.startedAt ?? .distantPast).timeIntervalSince(booted)) < 120 } }) {
                r.link = .weak
                sessionResources[match.key, default: []].append(r)
                continue
            }
            unattached.append(r)
        }

        var sessions: [Session] = []
        for (folder, info) in folders {
            let rs = (sessionResources[folder] ?? []).sorted { $0.kind.rawValue < $1.kind.rawValue }
            let alive = info.pids.filter { table[$0] != nil }
            let last = lastActivity(folder)
            let state: SessionState
            if alive.isEmpty {
                state = .ended(since: last)
            } else {
                let busy = alive.contains { pid in
                    (table[pid]?.cpu ?? 0) >= 1.0 ||
                    table.descendants(of: pid).contains { d in (table[d]?.cpu ?? 0) >= 2.0 && !rs.contains { $0.processes.contains { $0.pid == d } } }
                }
                let recent = last.map { Date().timeIntervalSince($0) < 15 * 60 } ?? false
                state = (busy || recent) ? .active : .idle(since: last ?? Date())
            }
            if rs.isEmpty { continue }   // a session only matters here while it has something running
            let starts = alive.compactMap { table[$0]?.start }
            sessions.append(Session(folder: folder, project: projectName(folder), branch: branch(folder),
                                    agent: info.agent, state: state, resources: rs, agentPids: alive,
                                    startedAt: starts.min().map { Date(timeIntervalSince1970: $0) },
                                    lastActivity: last,
                                    pinned: prefs.pinnedFolders.contains { folder.hasPrefix($0) },
                                    isWorktree: worktreeFolder(folder) != nil))
        }
        sessions.sort { a, b in
            func rank(_ s: Session) -> Int { s.pinned ? 3 : s.state.isEnded ? 0 : s.state.isActive ? 2 : 1 }
            return rank(a) != rank(b) ? rank(a) < rank(b) : a.memoryBytes > b.memoryBytes
        }

        let tunnels = (sessions.flatMap(\.resources) + unattached).filter { $0.kind == .tunnel }
            .compactMap { r in r.rootPid.map { Tunnel(pid: $0, tool: r.title, targetPort: r.tunnelTarget, resource: r) } }

        let ws = Workspace(sessions: sessions, unattached: unattached, devices: devices, stacks: stacks,
                           tunnels: tunnels, scannedAt: Date())
        return Result(workspace: ws, marks: marks)
    }

    // MARK: - Classification helpers

    /// `path` is `folder` or below it ("/app-db" is not inside "/app").
    static func inside(_ path: String, _ folder: String) -> Bool { path == folder || path.hasPrefix(folder + "/") }

    static func agent(of p: Proc, table: ProcessTable) -> Agent? {
        let tokens = p.command.split(separator: " ").prefix(3).map { ($0 as NSString).lastPathComponent }
        let script = ["node", "bun", "python", "python3", "deno"].contains(p.name) ? tokens.dropFirst().first : nil
        var name = script ?? p.name
        // Native installs run from ~/.local/share/claude/versions/<version>, so the binary is named like "2.1.173".
        if name != "claude", p.exe.contains("/claude/versions/") || tokens.first == "claude" { name = "claude" }
        switch name {
        case "claude":
            let fromApp = p.command.contains("stream-json") ||
                table.ancestors(of: p.pid).contains { table[$0]?.exe.contains("/Applications/Claude.app/") == true }
            return fromApp ? .claudeApp : .claudeCode
        case "codex": return p.command.contains("app-server") ? nil : .codex
        case "cursor-agent": return .cursor
        case "gemini": return .gemini
        case "aider": return .aider
        default: return nil
        }
    }

    /// The process we treat as "the server": climb up through runtimes and package managers,
    /// stopping at a shell, an agent, an app or launchd.
    static func climb(_ pid: Int32, _ table: ProcessTable, agents: [Int32: (folder: String, agent: Agent)]) -> Int32 {
        var cur = pid
        for _ in 0..<12 {
            guard let p = table[cur], let parent = table[p.ppid], p.ppid > 1 else { break }
            if shells.contains(parent.name) || agents[parent.pid] != nil || parent.exe.hasPrefix("/Applications/")
                || parent.exe.hasPrefix("/System/") || parent.exe.contains(".app/Contents/MacOS/") { break }
            cur = parent.pid
        }
        return cur
    }

    static func isUserProject(_ p: Proc, _ table: ProcessTable) -> Bool {
        if p.exe.hasPrefix("/Applications/") || p.exe.hasPrefix("/System/") || p.exe.hasPrefix("/usr/libexec/")
            || p.exe.contains(".app/Contents/") { return false }
        guard let cwd = table.cwd(p.pid) else { return false }
        return cwd.hasPrefix(home + "/") && !cwd.hasPrefix(home + "/Library/")
    }

    static func framework(_ cmd: String, fallback: String) -> String {
        let c = cmd.lowercased()
        let table: [(String, String)] = [
            ("next", "Next.js"), ("vite", "Vite"), ("metro", "Metro"), ("expo start", "Expo"),
            ("react-native start", "Metro"), ("uvicorn", "FastAPI"), ("fastapi", "FastAPI"), ("rails", "Rails"),
            ("manage.py runserver", "Django"), ("flask", "Flask"), ("artisan serve", "Laravel"), ("astro", "Astro"),
            ("nuxt", "Nuxt"), ("remix", "Remix"), ("storybook", "Storybook"), ("webpack", "webpack"),
            ("nest start", "NestJS"), ("supabase", "Supabase"), ("wrangler", "Wrangler"), ("jupyter", "Jupyter"),
            ("http.server", "Python server"), ("http-server", "Static server"), ("serve.", "Static server"),
            (" serve ", "Static server")
        ]
        for (needle, name) in table where c.contains(needle) { return name }
        switch fallback {
        case "node": return "Node server"
        case "python", "python3", "Python": return "Python server"
        case "bun": return "Bun server"
        case "deno": return "Deno server"
        default: return fallback
        }
    }

    static func watcherName(_ cmd: String) -> String? {
        let c = cmd.lowercased()
        let tools = ["tsc", "jest", "vitest", "nodemon", "webpack", "tailwind", "esbuild", "chokidar", "rollup", "babel", "sass", "tsup", "swc"]
        guard tools.contains(where: { c.contains($0) }) else { return nil }
        guard c.contains("--watch") || c.contains(" -w ") || c.hasSuffix(" -w") || c.contains("nodemon")
                || (c.contains("vitest") && !c.contains(" run")) || c.contains("chokidar") else { return nil }
        if c.contains("tsc") { return "TypeScript watcher" }
        if c.contains("jest") { return "Jest watcher" }
        if c.contains("vitest") { return "Vitest watcher" }
        if c.contains("nodemon") { return "nodemon" }
        if c.contains("webpack") { return "webpack watcher" }
        if c.contains("tailwind") { return "Tailwind watcher" }
        if c.contains("esbuild") { return "esbuild watcher" }
        return "Watcher"
    }

    static func isHeadlessBrowser(_ p: Proc) -> Bool {
        let c = p.command
        if c.contains("--type=") { return false }
        return c.contains("chrome-headless-shell") || c.contains("Google Chrome for Testing")
            || (c.contains("--headless") && (c.lowercased().contains("chrom") || c.contains("firefox") || c.contains("webkit")))
            || (c.contains("ms-playwright") && !c.contains("node"))
    }

    static func tunnelPort(_ cmd: String) -> Int? {
        let patterns = [#"localhost:(\d{2,5})"#, #"127\.0\.0\.1:(\d{2,5})"#, #"http\s+(\d{2,5})"#, #"--port[ =](\d{2,5})"#]
        for pat in patterns {
            if let re = try? NSRegularExpression(pattern: pat),
               let m = re.firstMatch(in: cmd, range: NSRange(cmd.startIndex..., in: cmd)),
               let r = Range(m.range(at: 1), in: cmd) { return Int(cmd[r]) }
        }
        return nil
    }

    static func shortCommand(_ cmd: String) -> String {
        let parts = cmd.split(separator: " ").map { s -> String in
            s.contains("/") && !s.hasPrefix("-") ? (String(s) as NSString).lastPathComponent : String(s)
        }
        let joined = parts.prefix(4).joined(separator: " ")
        return joined.count > 48 ? String(joined.prefix(47)) + "…" : joined
    }

    // MARK: - Folders and git

    /// For a path inside an agent worktree folder, the worktree root and the agent that made it.
    static func worktreeFolder(_ path: String) -> (String, Agent)? {
        for (marker, agent) in worktreeMarkers {
            guard let r = path.range(of: marker) else { continue }
            let rest = path[r.upperBound...]
            let name = rest.split(separator: "/").first.map(String.init) ?? ""
            guard !name.isEmpty else { return nil }
            return (String(path[..<r.upperBound]) + name, agent)
        }
        return nil
    }

    static var rootCache: [String: String] = [:]
    static func sessionRoot(_ cwd: String) -> String {
        if let (folder, _) = worktreeFolder(cwd) { return folder }
        if let c = rootCache[cwd] { return c }
        let top = Shell.run("git", ["-C", cwd, "rev-parse", "--show-toplevel"], timeout: 5).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let root = top.isEmpty ? cwd : top
        rootCache[cwd] = root
        return root
    }

    static func projectName(_ folder: String) -> String {
        for (marker, _) in worktreeMarkers {
            if let r = folder.range(of: marker) {
                return (String(folder[..<r.lowerBound]) as NSString).lastPathComponent
            }
        }
        return (folder as NSString).lastPathComponent
    }

    static func branch(_ folder: String) -> String? {
        let b = Shell.run("git", ["-C", folder, "rev-parse", "--abbrev-ref", "HEAD"], timeout: 5).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty || b == "HEAD" ? nil : b
    }

    /// Last time anything happened in a folder: its git index, or the folder itself.
    static func lastActivity(_ folder: String) -> Date? {
        let fm = FileManager.default
        var dates: [Date] = []
        let gitDir = Shell.run("git", ["-C", folder, "rev-parse", "--absolute-git-dir"], timeout: 5).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for path in [gitDir + "/index", gitDir + "/HEAD", gitDir + "/logs/HEAD", folder] where !path.hasPrefix("/index") {
            if let d = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date { dates.append(d) }
        }
        return dates.max()
    }

    // MARK: - Simulators

    static func simulators(_ table: ProcessTable) -> [Device] {
        let r = Shell.run("/usr/bin/xcrun", ["simctl", "list", "-j", "devices"], timeout: 20)
        guard let data = r.out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = json["devices"] as? [String: [[String: Any]]] else { return [] }
        let iso = ISO8601DateFormatter()
        var out: [Device] = []
        for (runtimeID, list) in byRuntime {
            let runtime = runtimeName(runtimeID)
            for d in list {
                guard let udid = d["udid"] as? String, let name = d["name"] as? String else { continue }
                let booted = (d["state"] as? String) == "Booted"
                var dev = Device(udid: udid, name: name, runtime: runtime, booted: booted,
                                 dataBytes: (d["dataPathSize"] as? NSNumber)?.int64Value ?? 0,
                                 lastUsed: (d["lastUsedAt"] as? String).flatMap { iso.date(from: $0) })
                if booted, let launchd = table.procs.values.first(where: { $0.name == "launchd_sim" && $0.command.contains(udid) }) {
                    let tree = [launchd.pid] + table.descendants(of: launchd.pid)
                    dev.memoryBytes = table.memory(tree)
                    dev.bootedAt = Date(timeIntervalSince1970: launchd.start)
                }
                out.append(dev)
            }
        }
        return out.sorted { ($0.booted ? 0 : 1, $0.name) < ($1.booted ? 0 : 1, $1.name) }
    }

    static func runtimeName(_ id: String) -> String {
        // com.apple.CoreSimulator.SimRuntime.iOS-26-0 -> iOS 26.0
        guard let last = id.split(separator: ".").last else { return "" }
        let parts = last.split(separator: "-")
        guard let os = parts.first else { return "" }
        return "\(os) " + parts.dropFirst().joined(separator: ".")
    }

    static func androidEmulators(_ table: ProcessTable) -> [Device] {
        table.procs.values.filter { $0.name.hasPrefix("qemu-system") }.map { p in
            let avd = p.command.components(separatedBy: "-avd ").dropFirst().first?.split(separator: " ").first.map(String.init) ?? "Android emulator"
            let tree = [p.pid] + table.descendants(of: p.pid)
            var d = Device(udid: "android:\(p.pid)", name: avd.replacingOccurrences(of: "_", with: " "), runtime: "Android",
                           booted: true, dataBytes: 0, lastUsed: Date())
            d.memoryBytes = table.memory(tree)
            d.bootedAt = Date(timeIntervalSince1970: p.start)
            d.android = true
            return d
        }
    }

    // MARK: - Docker

    static var statsCache: [String: Int64] = [:]

    static func dockerStacks(withStats: Bool) -> [Stack] {
        guard Shell.which("docker") != nil else { return [] }
        let fmt = "{{.ID}}\t{{.Label \"com.docker.compose.project\"}}\t{{.Label \"com.docker.compose.project.working_dir\"}}\t{{.Names}}\t{{.Ports}}\t{{.CreatedAt}}"
        let r = Shell.run("docker", ["ps", "--format", fmt], timeout: 10)
        guard r.ok else { return [] }
        if withStats {
            let s = Shell.run("docker", ["stats", "--no-stream", "--format", "{{.ID}}\t{{.MemUsage}}"], timeout: 15)
            var fresh: [String: Int64] = [:]
            for line in s.out.split(separator: "\n") {
                let f = line.split(separator: "\t")
                if f.count == 2 { fresh[String(f[0])] = parseDockerMemory(String(f[1])) }
            }
            if !fresh.isEmpty { statsCache = fresh }
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        var stacks: [String: Stack] = [:]
        for line in r.out.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 6 else { continue }
            let id = f[0], project = f[1].isEmpty ? f[3] : f[1]
            let created = df.date(from: f[5].split(separator: " ").prefix(3).joined(separator: " "))
            let ports = f[4].components(separatedBy: ", ").compactMap { p -> Int? in
                guard let arrow = p.range(of: "->"), let colon = p[..<arrow.lowerBound].lastIndex(of: ":") else { return nil }
                return Int(p[p.index(after: colon)..<arrow.lowerBound])
            }
            var s = stacks[project] ?? Stack(project: project, containers: [], names: [],
                                             workingDir: f[2].isEmpty ? nil : f[2], memoryBytes: 0, startedAt: created, ports: [])
            s.containers.append(id)
            s.names.append(f[3])
            s.memoryBytes += statsCache.first { id.hasPrefix($0.key) || $0.key.hasPrefix(id) }?.value ?? 0
            s.ports = Array(Set(s.ports + ports)).sorted()
            if let c = created, c < (s.startedAt ?? .distantFuture) { s.startedAt = c }
            stacks[project] = s
        }
        return stacks.values.sorted { $0.project < $1.project }
    }

    static func parseDockerMemory(_ s: String) -> Int64 {
        // "123.4MiB / 7.6GiB"
        let used = s.split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let units: [(String, Double)] = [("GiB", 1_073_741_824), ("MiB", 1_048_576), ("KiB", 1024), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("B", 1)]
        for (u, m) in units where used.hasSuffix(u) {
            return Int64((Double(used.dropLast(u.count)) ?? 0) * m)
        }
        return 0
    }
}
