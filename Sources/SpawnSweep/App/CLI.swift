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
        // Folder boundaries: a Docker stack in /app-db doesn't belong to a session in /app.
        assert(Scanner.inside("/s/app", "/s/app") && Scanner.inside("/s/app/api", "/s/app") && !Scanner.inside("/s/app-db", "/s/app"))
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
