import Foundation

/// Command-line modes of the same binary:
/// `--session-end` is the Claude Code SessionEnd hook, `--mcp` is a stdio MCP server, `--scan` prints a summary.
enum CLI {
    static func scanNow() -> Workspace {
        let state = Store.loadState()
        let r = Scanner.scan(prefs: state.prefs, marks: state.marks, withStats: false)
        var s = Store.loadState()
        s.marks = r.marks
        Store.saveState(s)
        return r.workspace
    }

    // MARK: - Hook

    /// Claude Code calls this when a session ends, with JSON on stdin ({ "cwd": …, "session_id": … }).
    /// Stops what that session started in its folder. Pinned sessions and protected ports are kept.
    static func sessionEnd() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        // /clear also ends a session, but the person is still working: leave everything running.
        if (json["reason"] as? String) == "clear" { return }
        guard let cwd = json["cwd"] as? String ?? ProcessInfo.processInfo.environment["PWD"] else { return }
        let folder = Scanner.sessionRoot(cwd)
        let state = Store.loadState()
        let ws = scanNow()
        guard let session = ws.sessions.first(where: { $0.folder == folder }), !session.pinned else { return }
        // Another agent still working in this folder may be using these servers.
        let mine = Set(ProcessTable().ancestors(of: getpid()))
        if session.agentPids.contains(where: { !mine.contains($0) && kill($0, 0) == 0 }) { return }
        let targets = session.resources.filter { r in
            r.link == .strong && [.server, .watcher, .browser, .tunnel].contains(r.kind)
                && !r.ports.contains(where: state.prefs.protectedPorts.contains)
        }
        guard !targets.isEmpty else { return }
        let o = Actions.stopAll(targets)
        Store.log(ActivityEntry(kind: .cleanup, title: "Closed a finished \(session.agent.rawValue) session",
                                detail: "\(session.project): " + targets.map(\.title).joined(separator: ", ") + ". " + o.summary,
                                recovery: o.recovery), historyDays: state.prefs.historyDays)
    }

    // MARK: - MCP server

    /// Minimal MCP server over stdio (newline-delimited JSON-RPC). Read-only: it reports, never stops anything.
    static func mcp() {
        setvbuf(stdout, nil, _IOLBF, 0)
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let method = msg["method"] as? String else { continue }
            let id = msg["id"]
            let params = msg["params"] as? [String: Any] ?? [:]
            switch method {
            case "initialize":
                reply(id, ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                           "capabilities": ["tools": [String: Any]()],
                           "serverInfo": ["name": "spawnsweep", "version": "1.0.0"]])
            case "ping":
                reply(id, [String: Any]())
            case "tools/list":
                reply(id, ["tools": [
                    ["name": "running_for_repo",
                     "description": "Lists dev servers, watchers, simulators and Docker stacks already running for a project folder, with their ports. Call this before starting a dev server, and reuse a running one instead of starting another.",
                     "inputSchema": ["type": "object", "properties": ["path": ["type": "string", "description": "Absolute path of the project or worktree"]], "required": ["path"]]],
                    ["name": "list_sessions",
                     "description": "Lists AI agent sessions on this Mac and what each one still has running.",
                     "inputSchema": ["type": "object", "properties": [String: Any]()]]
                ]])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                let text: String
                switch name {
                case "running_for_repo": text = runningFor(path: args["path"] as? String ?? "")
                case "list_sessions": text = listSessions()
                default: text = "Unknown tool \(name)."
                }
                reply(id, ["content": [["type": "text", "text": text]]])
            default:
                if id != nil { error(id, code: -32601, message: "Method not found") }
            }
        }
    }

    static func runningFor(path: String) -> String {
        let root = path.isEmpty ? "" : Scanner.sessionRoot(path)
        let ws = scanNow()
        let matches = ws.allResources.filter { r in
            guard let cwd = r.cwd else { return false }
            return !root.isEmpty && (cwd.hasPrefix(root) || root.hasPrefix(cwd))
        }
        guard !matches.isEmpty else { return "Nothing is running for \(root.isEmpty ? "that path" : root). It's fine to start a dev server." }
        return matches.map { r in
            let url = r.ports.first.map { " http://localhost:\($0)" } ?? ""
            return "- \(r.title)\(url) · \(r.detail)"
        }.joined(separator: "\n") + "\nReuse a running server instead of starting a new one."
    }

    static func listSessions() -> String {
        let ws = scanNow()
        guard !ws.sessions.isEmpty else { return "No agent sessions with running resources." }
        return ws.sessions.map { s in
            let state: String
            switch s.state {
            case .active: state = "active"
            case .idle(let since): state = "idle \(Fmt.duration(Date().timeIntervalSince(since)))"
            case .ended: state = "ended"
            }
            let rs = s.resources.map(\.title).joined(separator: ", ")
            return "- \(s.project) (\(s.agent.rawValue), \(state)\(s.pinned ? ", pinned" : "")): \(rs.isEmpty ? "nothing running" : rs)"
        }.joined(separator: "\n")
    }

    private static func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) else { return }
        print(s)
    }
    private static func reply(_ id: Any?, _ result: Any) { send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]) }
    private static func error(_ id: Any?, code: Int, message: String) {
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }

    // MARK: - Debug

    static func printScan() {
        let ws = scanNow()
        for s in ws.sessions {
            print("SESSION \(s.project) [\(s.agent.rawValue)] \(s.state) pinned=\(s.pinned) folder=\(s.folder)")
            for r in s.resources { print("   \(r.kind.rawValue) \(r.title) · \(r.detail) · \(Fmt.bytes(r.memoryBytes)) · link=\(r.link)") }
        }
        print("UNATTACHED")
        for r in ws.unattached { print("   \(r.kind.rawValue) \(r.title) · \(r.detail) · cwd=\(r.cwd ?? "-")") }
        print("DEVICES booted=\(ws.devices.filter(\.booted).map(\.name))  STACKS=\(ws.stacks.map { "\($0.project)(\($0.containers.count))" })  TUNNELS=\(ws.tunnels.count)")
        // The two numbers every screen shows, so they can be checked against the app.
        print("RUNNING \(ws.allResources.count)  DEV PORTS \(ws.openPorts.count) \(ws.openPorts.sorted())")
    }

    /// `--lens`: Space Lens's whole-disk map, top level only, so its numbers can be checked against the disk.
    static func printLens() {
        guard let pro = Edition.pro else { print("Space Lens is part of SpawnSweep Pro."); return }
        let started = Date(), scan = LensScan()
        let map = pro.lensMap(scan: scan) { _ in }
        for n in pro.lensLevel("/", map: map, scan: scan) {
            print(String(format: "%10@  %@%@", Fmt.bytes(n.bytes), n.name, n.locked ? "  (not measured)" : ""))
        }
        print("DISK \(Fmt.bytes(map.diskUsed)) used of \(Fmt.bytes(map.diskTotal))  FULL DISK ACCESS \(LensAccess.full ? "yes" : "no")  LOCKED \(map.locked.count)  FOLDERS \(map.sizes.count)  \(Int(Date().timeIntervalSince(started)))s")
    }
}

extension CLI {
    /// `--selftest`: checks that rules saved before modes existed still load with the same behaviour.
    static func selfTest() {
        func rule(_ json: String) -> Rule { try! JSONDecoder().decode(Rule.self, from: Data(json.utf8)) }
        let kind = #""kind":{"simulatorIdle":{"hours":2}}"#
        assert(rule(#"{"name":"a",\#(kind),"dryRun":true}"#).mode == .dryRun)
        assert(rule(#"{"name":"a",\#(kind),"dryRun":false}"#).mode == .auto)
        assert(rule(#"{"name":"a",\#(kind),"mode":"ask","enabled":false}"#).mode == .ask)
        let r = Rule(name: "b", kind: .onBattery, mode: .ask)
        assert(try! JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(r)) == r)
        // A mode only acts when this build has Pro and the license is valid.
        assert(RuleMode.auto.effective(hasPro: false, licensed: true) == .dryRun, "a free build would act")
        assert(RuleMode.ask.effective(hasPro: true, licensed: false) == .dryRun, "acted without a license")
        assert(RuleMode.auto.effective(hasPro: true, licensed: true) == .auto)
        assert(RuleMode.dryRun.effective(hasPro: true, licensed: true) == .dryRun)
        assert(Fmt.hour(19) == "7 PM" && Fmt.hour(0) == "12 AM" && Fmt.hour(12) == "12 PM")

        // Prefs: every field survives a round trip (catches a field missing from the tolerant decoder) ...
        var full = Prefs()
        full.devFolders = ["/a"]; full.pinnedFolders = ["/b"]; full.protectedPorts = [3000]; full.retentionDays = 3
        full.historyDays = 9; full.appearance = "dark"; full.actionableAlerts = false; full.budgetWarnings = false
        full.budgetSimulators = 5; full.budgetWorktreeGB = 77; full.rules = [r]; full.onboarded = true
        full.snoozedUntil = ["x": Date(timeIntervalSince1970: 1000)]
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        let once = try! enc.encode(full)
        assert(try! enc.encode(JSONDecoder().decode(Prefs.self, from: once)) == once, "a Prefs field isn't decoded")
        // ... an old file missing keys keeps what it has, and a rule kind this build doesn't know is skipped.
        let old = try! JSONDecoder().decode(Store.State.self, from: Data(#"""
            {"prefs":{"devFolders":["/keep"],"rules":[{"name":"ok",\#(kind)},{"name":"future","kind":{"teleport":{}}}]}}
            """#.utf8))
        assert(old.prefs.devFolders == ["/keep"] && old.prefs.historyDays == 30)
        assert(old.prefs.rules.map(\.name) == ["ok"])

        // A natively installed Claude Code (binary named by version) is still recognised as a live agent.
        let table = ProcessTable()
        func proc(_ exe: String, _ cmd: String) -> Proc {
            Proc(pid: 999_999, ppid: 1, rssBytes: 0, cpu: 0, elapsed: 0, command: cmd, exe: exe, start: 0)
        }
        assert(Scanner.agent(of: proc(Shell.home + "/.local/share/claude/versions/2.1.173", "claude --resume"), table: table) == .claudeCode,
               "native Claude Code wasn't recognised")
        assert(Scanner.agent(of: proc("/usr/bin/python3", "/usr/bin/python3 app.py"), table: table) == nil)
        // Servers the Claude app's preview or the Codex app start have no agent process above them; the app itself is the link.
        func p(_ pid: Int32, _ ppid: Int32, _ exe: String, _ cmd: String = "") -> Proc {
            Proc(pid: pid, ppid: ppid, rssBytes: 0, cpu: 0, elapsed: 0, command: cmd.isEmpty ? exe : cmd, exe: exe, start: 0)
        }
        let codex = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        let fake = ProcessTable([
            p(10, 1, "/Applications/Claude.app/Contents/MacOS/Claude"),
            p(11, 10, "/Applications/Claude.app/Contents/Helpers/disclaimer"), p(12, 11, "/bin/bash"), p(13, 12, "/usr/local/bin/node"),
            p(20, 1, "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"), p(21, 20, codex, codex + " -c x=1 app-server"),
            p(22, 21, "/usr/local/bin/npm"), p(23, 22, "/usr/local/bin/node"),
            p(30, 1, "/bin/zsh"), p(31, 30, "/usr/local/bin/codex"), p(32, 31, "/usr/local/bin/node"),
            p(40, 1, "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"), p(41, 40, "/bin/zsh"), p(42, 41, "/usr/local/bin/node")
        ])
        let claudeHost = Scanner.hostApp(13, fake), codexHost = Scanner.hostApp(23, fake)
        assert(claudeHost?.agent == .claudeApp && claudeHost?.pid == 10, "Claude app preview server not linked")
        assert(codexHost?.agent == .codex && codexHost?.pid == 21, "Codex app server not linked")
        assert(Scanner.hostApp(32, fake) == nil, "a terminal Codex CLI is a live agent, not a host app")
        assert(Scanner.hostApp(42, fake) == nil, "a server started in Terminal belongs to no app")
        // Space Lens scanning: each gathering moon starts hidden, arrives, and fades; the time tile reads sensibly.
        let s0 = GatherMoons.stage(0), sMid = GatherMoons.stage(0.55), sEnd = GatherMoons.stage(0.999)
        assert(s0.opacity == 0 && s0.travel == 0 && sMid.travel == 1 && sMid.opacity == 1 && sEnd.opacity < 0.01)
        assert(SpaceLensPage.clock(48) == "48s" && SpaceLensPage.clock(125) == "2m 05s")
        assert(SpaceLensPage.timeLeft(elapsed: 3, done: 0.5) == "Working out time left")
        assert(SpaceLensPage.timeLeft(elapsed: 60, done: 0.5) == "About 1 minute left")
        assert(SpaceLensPage.timeLeft(elapsed: 120, done: 0.9) == "Less than a minute left")
        // Folder boundaries: a Docker stack in /app-db doesn't belong to a session in /app.
        assert(Scanner.inside("/s/app", "/s/app") && Scanner.inside("/s/app/api", "/s/app") && !Scanner.inside("/s/app-db", "/s/app"))
        // Space Lens Remove works like a cleaner app: only macOS, other accounts, your home and its standard folders,
        // keys, a project's .git on its own, the Trash, and busy folders are locked. The rest goes with a preview warning.
        let fakeHome = NSTemporaryDirectory() + "lens-\(UUID().uuidString)", fm0 = FileManager.default
        for d in ["Documents", "Library/Caches/x", "Library/Application Support/x", "Library/Mobile Documents/x", "Library/Keychains/x",
                  ".ssh/keys", ".npm/_cacache", ".gradle/caches", ".Trash/old", "code/repo/.git/objects", "code/repo/src",
                  "code/repo/node_modules/x", "code/plain"] {
            try? fm0.createDirectory(atPath: fakeHome + "/" + d, withIntermediateDirectories: true)
        }
        func refused(_ rel: String, busy: [String] = []) -> Bool { Actions.trashRefusal(fakeHome + "/" + rel, home: fakeHome, busy: busy) != nil }
        func warning(_ rel: String) -> String { Actions.trashWarning(fakeHome + "/" + rel, home: fakeHome) ?? "" }
        assert(Actions.trashRefusal("/System/Library", home: fakeHome, busy: []) != nil, "part of macOS was allowed")
        assert(Actions.trashRefusal("/Applications/Utilities", home: fakeHome, busy: []) != nil, "a folder in Applications was allowed")
        assert(Actions.trashRefusal("/Applications/NoSuchApp.app", home: fakeHome, busy: []) == nil, "an app that isn't open was refused")
        assert(Actions.trashRefusal(fakeHome, home: fakeHome, busy: []) != nil, "the home folder itself was allowed")
        assert(refused("Documents") && refused(".ssh") && refused(".ssh/keys") && refused("Library/Keychains/x") && refused(".Trash"),
               "a standard folder, keys or the Trash was allowed")
        assert(refused("code/repo/.git") && refused("code/repo/.git/objects"), "a project's history on its own was allowed")
        assert(refused("code/plain", busy: [fakeHome + "/code/plain/app"]), "a folder something runs in was allowed")
        for rel in ["Library/Caches/x", "Library/Application Support/x", "code", "code/repo", "code/repo/src", "code/repo/node_modules",
                    ".gradle", ".npm", "code/plain", "Documents/notes.txt"] {
            assert(!refused(rel), "\(rel) was refused")
        }
        assert(warning("Library/Caches/x").isEmpty && warning("code/repo/node_modules").isEmpty && warning(".npm").isEmpty
               && warning("Documents/notes.txt").isEmpty, "something safe to clear got a warning")
        assert(warning("Library/Application Support/x").hasPrefix("App data") && warning("Library/Mobile Documents/x").contains("iCloud"))
        assert(warning(".gradle").hasPrefix("Settings") && warning("code/repo/src").hasPrefix("Part of repo"), "a tool folder or project file wasn't flagged")
        assert(warning("code").contains("isn't committed or pushed in repo"), "a folder of projects with unsaved work wasn't flagged")
        assert(Actions.gitRepos(under: fakeHome + "/code").map { ($0 as NSString).lastPathComponent } == ["repo"]
               && Actions.gitRepos(under: fakeHome + "/Documents").isEmpty, "projects under a folder weren't found")
        // Unsaved work: a real clone is clean only once its commit is pushed, and an untracked file makes it unsaved again.
        let git = { (args: [String]) in _ = Shell.run("git", ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "init.defaultBranch=main"] + args, timeout: 20) }
        git(["init", "-q", "--bare", fakeHome + "/remote.git"]); git(["clone", "-q", fakeHome + "/remote.git", fakeHome + "/clean"])
        fm0.createFile(atPath: fakeHome + "/clean/a.txt", contents: Data("a".utf8))
        git(["-C", fakeHome + "/clean", "add", "."]); git(["-C", fakeHome + "/clean", "commit", "-qm", "a"])
        assert(Actions.hasUnsavedWork(fakeHome + "/clean"), "a commit that isn't pushed counted as saved")
        git(["-C", fakeHome + "/clean", "push", "-q", "origin", "HEAD"])
        assert(!Actions.hasUnsavedWork(fakeHome + "/clean"), "a clean, pushed clone counted as unsaved")
        fm0.createFile(atPath: fakeHome + "/clean/b.txt", contents: Data("b".utf8))
        assert(Actions.hasUnsavedWork(fakeHome + "/clean"), "an untracked file counted as saved")
        // Simulator folders show the device, not the UUID.
        let sim = Device(udid: "ABC-123", name: "iPhone 16 Pro", runtime: "iOS 18.2", booted: false, dataBytes: 0, lastUsed: nil)
        let named = LensStore.named([LensNode(path: "/d/ABC-123", name: "ABC-123", isDir: true, bytes: 1, kind: .appData),
                                     LensNode(path: "/d/other", name: "other", isDir: true, bytes: 1, kind: .appData)], devices: [sim])
        assert(named.map(\.name) == ["iPhone 16 Pro · iOS 18.2", "other"], "a simulator folder kept its UUID name")
        try? fm0.removeItem(atPath: fakeHome)
        // Moons never overlap, and the same sizes always pack the same way.
        let radii: [CGFloat] = (0..<30).map { (i: Int) -> CGFloat in CGFloat((i * 37) % 41 + 4) }.sorted(by: >)
        let pts = Pack.positions(radii, gap: 4)
        for i in 0..<30 { for j in (i + 1)..<30 {
            let apart: CGFloat = hypot(pts[i].x - pts[j].x, pts[i].y - pts[j].y)
            let needed: CGFloat = radii[i] + radii[j] + 3.99
            assert(apart >= needed, "moons overlap")
        } }
        assert(Pack.positions(radii, gap: 4) == pts, "packing isn't deterministic")
        // A results dialog folds repeated skips into one line per category and reason, in first-seen order.
        let skips = (1...3).map { "Skipped DerivedData · Runner-\($0): Xcode is open. Quit it first." }
        assert(DialogView.grouped(skips + ["Skipped Caches · Foo: it changed since the scan.", "Docker didn't stop.",
                                           "Couldn't remove a.dmg: denied", "Couldn't remove b.dmg: denied"])
               == ["Skipped 3 DerivedData items: Xcode is open. Quit it first.", "Skipped Caches · Foo: it changed since the scan.",
                   "Docker didn't stop.", "Couldn't remove 2 items: denied"], "repeated skips weren't grouped")
        assert(DialogView.grouped(["Skipped A · x: changed", "Skipped B · y: changed"]).count == 2, "different categories were merged")
        assert(SessionsPage.runningLine(total: 5, loose: 4) == "5 things running: 1 in active or pinned sessions, 4 not tied to an agent session.")
        assert(SessionsPage.runningLine(total: 1, loose: 1) == "1 thing running: 1 not tied to an agent session.")
        // Every screen counts ports from one list: Docker stacks' ports included, each port once, sorted by first port.
        var ws = Workspace()
        ws.unattached = [Resource(id: "stack:db", kind: .stack, title: "db stack", detail: "", ports: [5431, 8080]),
                         Resource(id: "srv", kind: .server, title: "Vite :3101", detail: "", ports: [3101]),
                         Resource(id: "dup", kind: .server, title: "Node :3101", detail: "", ports: [3101]),
                         Resource(id: "sim:1", kind: .simulator, title: "iPhone", detail: "")]
        assert(ws.openPorts == [3101, 5431, 8080], "a Docker port or a shared port was miscounted")
        assert(ws.portResources.map(\.id) == ["srv", "dup", "stack:db"], "port list isn't every resource with a port, by port")
        // Removing the hook takes only SpawnSweep's entry; another tool's hook in the same group stays.
        let other: [String: Any] = ["type": "command", "command": "/usr/local/bin/notify --done"]
        let groups: [[String: Any]] = [["hooks": [["type": "command", "command": Integrations.hookCommand], other]],
                                       ["hooks": [["type": "command", "command": Integrations.hookCommand]]]]
        let left = Integrations.withoutOurHook(groups)
        assert(left.count == 1 && ((left[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String) == "/usr/local/bin/notify --done",
               "another tool's hook was removed")
        // Licensing: weekly re-check, two weeks of offline grace, and how Dodo's answers are read.
        let day: TimeInterval = 86400, now = Date()
        func rec(validated: Double, checked: Double) -> License.Record {
            License.Record(key: "k-1234", instanceID: "lki_1", environment: License.environment, email: nil,
                           activatedAt: now.addingTimeInterval(-60 * day),
                           lastValidated: now.addingTimeInterval(-validated * day), lastChecked: now.addingTimeInterval(-checked * day))
        }
        assert(!License.isPro(nil, now: now))
        assert(License.isPro(rec(validated: 1, checked: 1), now: now))
        assert(License.isPro(rec(validated: 20, checked: 0.5), now: now), "offline grace ended too early")
        assert(!License.isPro(rec(validated: 22, checked: 0.5), now: now), "Pro outlived the offline grace")
        var elsewhere = rec(validated: 1, checked: 1)
        elsewhere.environment = License.environment == License.Environment.test ? .live : .test
        assert(!License.isPro(elsewhere, now: now), "a key from the other Dodo environment unlocked Pro")
        assert(!License.needsCheck(rec(validated: 3, checked: 3), now: now))
        assert(License.needsCheck(rec(validated: 8, checked: 2), now: now))
        assert(!License.needsCheck(rec(validated: 8, checked: 0.1), now: now), "retried more than once a day while offline")
        assert(License.verdict(status: 200, body: Data(#"{"valid":true}"#.utf8)) == .valid)
        assert(License.verdict(status: 200, body: Data(#"{"valid":false}"#.utf8)) == .invalid)
        assert(License.verdict(status: 404, body: nil) == .invalid)
        assert(License.verdict(status: 503, body: nil) == .unreachable, "a Dodo outage would have removed Pro")
        assert(License.verdict(status: nil, body: nil) == .unreachable, "being offline would have removed Pro")
        assert(License.verdict(status: 200, body: Data("<html>".utf8)) == .unreachable)
        let act = try! JSONDecoder().decode(License.Activation.self, from: Data(#"""
            {"id":"lki_9","business_id":"b","name":"Mac","license_key_id":"lk","created_at":"2026-10-29T10:00:00Z",
             "product":{"product_id":"p"},"customer":{"customer_id":"c","name":"Sam","email":"sam@example.com"}}
            """#.utf8))
        assert(act.id == "lki_9" && act.customer?.email == "sam@example.com")
        assert(License.activationError(status: 422).contains("maximum"))
        // A key copied from an email or web page often ends in line breaks; a one-line field would show only the empty last line.
        assert(License.cleanKey("ABCD-1234-EF\n\n") == "ABCD-1234-EF", "line breaks kept in a pasted key")
        assert(License.cleanKey(" ab cd\t\r\n") == "abcd")

        Edition.pro?.selfTest()
        DiskScanner.selfTestWorktrees()
        print("selftest OK")
    }
}
