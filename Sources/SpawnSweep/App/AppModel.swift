import SwiftUI
import AppKit

enum Page: String, CaseIterable, Identifiable {
    case sessions, ports, resources, mac, junk, largeFiles, spaceLens, storage, recycle, autopilot, connections, safety, activity, settings, welcome, pro
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: return "Sessions"
        case .ports: return "Ports board"
        case .resources: return "Resources"
        case .mac: return "This Mac"
        case .junk: return "Junk"
        case .largeFiles: return "Large & old files"
        case .spaceLens: return "Space Lens"
        case .storage: return "Storage"
        case .recycle: return "Recycle bin"
        case .autopilot: return "Autopilot"
        case .connections: return "Connections"
        case .safety: return "Safety"
        case .activity: return "Activity"
        case .settings: return "Settings"
        case .welcome: return "Welcome & setup"
        case .pro: return "SpawnSweep Pro"
        }
    }

    /// Junk, Large & old files and Space Lens open from This Mac, so the sidebar keeps This Mac selected there.
    var sidebarPage: Page {
        switch self {
        case .junk, .largeFiles, .spaceLens: return .mac
        default: return self
        }
    }

    var symbol: String {
        switch self {
        case .sessions: return "square.stack.3d.up"
        case .ports: return "point.3.connected.trianglepath.dotted"
        case .resources: return "cube.transparent"
        case .mac: return "laptopcomputer"
        case .junk: return "bubbles.and.sparkles"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .spaceLens: return "circle.hexagongrid"
        case .storage: return "internaldrive"
        case .recycle: return "archivebox"
        case .autopilot: return "sparkles"
        case .connections: return "powerplug"
        case .safety: return "checkmark.shield"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        case .welcome: return "moon"
        case .pro: return "crown.fill"
        }
    }

    static let sidebar: [Page] = [.sessions, .ports, .resources, .mac, .storage, .recycle, .autopilot, .connections, .safety, .activity, .settings]
}

/// One checkable line in a preview dialog.
struct DialogItem: Identifiable, Hashable {
    let id: String
    var label: String
    var detail: String = ""
    var checked = true
    var required = false
}

/// A resource-changing action, shown as a preview first. Phases: preview → running → result.
struct DialogSpec: Identifiable {
    enum Phase { case preview, running, done(summary: String, failures: [String]) }

    let id = UUID()
    var icon = "moon"
    var title: String
    var subtitle: String
    var items: [DialogItem] = []
    var notes: [String] = []
    var warning: String?
    var confirmTitle: String
    /// Title for the Activity log ("Freed :3000 · decize-webapp"). Falls back to the dialog title.
    var activityTitle: String?
    var destructive = false
    var phase: Phase = .preview
    /// Receives the ids of the checked items. Runs off the main thread.
    var action: (@Sendable (Set<String>) -> Actions.Outcome)?
    /// Shown while the action runs.
    var runningNote = "Checking each item again before it changes."
    /// Custom body for dialogs that aren't a checklist (setup steps, lists, forms).
    var custom: AnyView?
}

@MainActor
@Observable
final class AppModel {
    var page: Page = .sessions
    var sessionDetail: String?          // session folder
    var repoDetail: String?             // repo path
    var worktreeFilter: WorktreeFilter = .all
    var workspace = Workspace()
    var disk = DiskSnapshot()
    var bin: [BinEntry] = []
    var activity: [ActivityEntry] = []
    var state = Store.loadState()
    var dialog: DialogSpec?
    var paletteOpen = false
    var scanning = false
    var diskScanning = false
    /// Fresh measurements in the running disk scan, for "Measured 34 of 81".
    var diskMeasured = 0
    var diskTotal = 0
    /// When the numbers on screen were last fully measured.
    var diskUpdatedAt: Date?
    private var lastCompleteDisk: DiskSnapshot?

    private var timer: Timer?
    private var rescanQueued = false
    /// Stopped resources hidden until a scan that started after the stop confirms they're gone.
    private var hiddenSince: [String: Date] = [:]
    /// Ports stopped from SpawnSweep, to explain when an agent starts them again.
    private var stoppedPorts: [Int: Date] = [:]
    private var tick = 0
    var notified = Set<String>()
    /// Whole-Mac figures: disk, memory, junk, and large or old files.
    let system = SystemMonitor()
    let junk = JunkStore()
    let largeFiles = LargeFileStore()
    let lens = LensStore()
    /// SpawnSweep Pro (Dodo Payments license, kept in the Keychain).
    let license = LicenseStore()
    var autopilotBusy = false
    /// When each session was first seen ended. Rules count "after the session ends" from here, not from the
    /// folder's last change, so quitting an agent after a quiet hour doesn't stop its leftovers right away.
    var endedSeen: [String: Date] = [:]

    var prefs: Prefs {
        get { state.prefs }
        set { state.prefs = newValue; Store.saveState(state) }
    }

    // MARK: - Derived numbers used across pages

    var attentionSessions: [Session] { workspace.sessions.filter(\.needsAttention) }
    var sweepResources: [Resource] { workspace.sessions.flatMap(\.sweepable) }
    var memoryToFree: Int64 { sweepResources.reduce(0) { $0 + $1.memoryBytes } }
    var reclaimableDisk: Int64 { disk.slimBytes + disk.buildBytes }
    var protectedCount: Int { workspace.sessions.filter { $0.pinned || $0.state.isActive }.count }

    func session(_ folder: String) -> Session? { workspace.sessions.first { $0.folder == folder } }
    func isProtected(port: Int) -> Bool { prefs.protectedPorts.contains(port) }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        if Edition.hasPro {   // the free edition never touches the license
            license.load()
            license.recheckIfDue()
        }
        Actions.purgeBin(retentionDays: prefs.retentionDays)
        if let cached = Store.loadDisk() {
            disk = cached
            lastCompleteDisk = cached
            diskUpdatedAt = cached.scannedAt
        }
        reloadFiles()
        refresh(withStats: true)
        refreshDisk()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tick += 1
                self.system.refresh()
                if Edition.hasPro { self.license.recheckIfDue() }   // only reaches the network once a week
                self.refresh(withStats: self.tick % 8 == 0)
                if self.tick % 225 == 0 { self.refreshDisk() }   // every 30 minutes
            }
        }
        Notifier.shared.setUp(model: self)
    }

    func reloadFiles() {
        bin = Store.loadBin()
        activity = Store.loadActivity()
    }

    func refresh(withStats: Bool = false) {
        guard !scanning else { rescanQueued = true; return }
        scanning = true
        let startedAt = Date()
        let prefs = prefs, marks = state.marks
        Task.detached {
            let result = Scanner.scan(prefs: prefs, marks: marks, withStats: withStats)
            await MainActor.run {
                self.workspace = self.annotate(result.workspace, scanStartedAt: startedAt)
                self.state.marks = result.marks
                Store.saveState(self.state)
                self.scanning = false
                self.reloadFiles()
                self.runAutopilot()
                self.checkBudgetsAndAlerts()
                if self.rescanQueued { self.rescanQueued = false; self.refresh() }
            }
        }
    }

    /// Drops resources stopped after this scan began, and notes servers something restarted.
    private func annotate(_ ws: Workspace, scanStartedAt: Date) -> Workspace {
        hiddenSince = hiddenSince.filter { $0.value > scanStartedAt }   // a later scan already confirmed these
        stoppedPorts = stoppedPorts.filter { Date().timeIntervalSince($0.value) < 3600 }
        func fix(_ r: Resource, owner: Session?) -> Resource? {
            if hiddenSince[r.id] != nil { return nil }
            var r = r
            if let start = r.startedAt, let stoppedAt = r.ports.compactMap({ stoppedPorts[$0] }).max(), start > stoppedAt {
                let who = owner.map { $0.agentPids.isEmpty ? "something" : "its \($0.agent.rawValue) session" } ?? "something"
                r.restartNote = "Started again by \(who) \(Fmt.duration(start.timeIntervalSince(stoppedAt))) after you stopped it."
            }
            return r
        }
        var out = ws
        out.sessions = ws.sessions.compactMap { s in
            var s = s
            s.resources = s.resources.compactMap { fix($0, owner: s) }
            return s.resources.isEmpty ? nil : s
        }
        out.unattached = ws.unattached.compactMap { fix($0, owner: nil) }
        out.tunnels = ws.tunnels.filter { hiddenSince[$0.resource.id] == nil }
        return out
    }

    /// Removes stopped resources from what's on screen right away.
    func hide(_ ids: [String], ports: [Int]) {
        guard !ids.isEmpty else { return }
        let now = Date()
        for id in ids { hiddenSince[id] = now }
        for p in ports { stoppedPorts[p] = now }
        workspace = annotate(workspace, scanStartedAt: .distantPast)
    }

    func refreshDisk() {
        guard !diskScanning else { return }
        diskScanning = true
        let prefs = prefs
        Task.detached {
            let busy = Actions.busyFolders()
            DiskScanner.scan(prefs: prefs, busyFolders: busy) { snap in
                Task { @MainActor in self.applyDisk(snap) }
            }
            await MainActor.run { self.diskScanning = false }
        }
    }

    /// Shows a partial scan on top of the last complete one, so numbers never start from zero.
    private func applyDisk(_ fresh: DiskSnapshot) {
        let all = fresh.worktrees
        diskTotal = all.count
        diskMeasured = all.filter { $0.sizeBytes != nil }.count
        if !fresh.inProgress {
            disk = fresh
            lastCompleteDisk = fresh
            diskUpdatedAt = fresh.scannedAt
            Store.saveDisk(fresh)
            return
        }
        guard let old = lastCompleteDisk else { disk = fresh; return }
        let previous = Dictionary(old.worktrees.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        var merged = fresh
        for ri in merged.repos.indices {
            for wi in merged.repos[ri].worktrees.indices {
                guard let p = previous[merged.repos[ri].worktrees[wi].path] else { continue }
                if merged.repos[ri].worktrees[wi].sizeBytes == nil {
                    merged.repos[ri].worktrees[wi].sizeBytes = p.sizeBytes
                    merged.repos[ri].worktrees[wi].slimBytes = p.slimBytes
                }
                if merged.repos[ri].worktrees[wi].status == .unknown { merged.repos[ri].worktrees[wi].status = p.status }
                if merged.repos[ri].worktrees[wi].slimDirs.isEmpty { merged.repos[ri].worktrees[wi].slimDirs = p.slimDirs }
                if merged.repos[ri].worktrees[wi].lastUsed == nil { merged.repos[ri].worktrees[wi].lastUsed = p.lastUsed }
            }
        }
        if merged.derivedData.isEmpty { merged.derivedData = old.derivedData }
        if merged.simulatorDevices.isEmpty { merged.simulatorDevices = old.simulatorDevices }
        if merged.aiApps.isEmpty { merged.aiApps = old.aiApps }
        disk = merged
    }

    // MARK: - Navigation

    func go(_ p: Page) {
        // The free edition has no Junk, Large & old files, Space Lens or Pro page: those links land on This Mac.
        if !Edition.hasPro, [.junk, .largeFiles, .spaceLens, .pro].contains(p) { return go(.mac) }
        page = p
        sessionDetail = nil
        repoDetail = nil
        // Whole-Mac scans are slower and touch protected folders, so they run when someone looks, then every 30 minutes.
        let stale = { (d: Date?) in d.map { Date().timeIntervalSince($0) > 1800 } ?? true }
        if Edition.hasPro, [.mac, .junk, .pro].contains(p), stale(junk.scannedAt), !junk.scanning { junk.scan() }
        if Edition.hasPro, [.mac, .largeFiles, .pro].contains(p), stale(largeFiles.scannedAt), !largeFiles.scanning { largeFiles.scan() }
    }

    func openSession(_ folder: String) { page = .sessions; sessionDetail = folder }
    func openRepo(_ path: String) { page = .storage; repoDetail = path }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.identifier?.rawValue.contains("main") == true || w.title == "SpawnSweep" {
            w.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Pins and protection

    func togglePin(_ folder: String) {
        if prefs.pinnedFolders.contains(folder) { prefs.pinnedFolders.removeAll { $0 == folder } }
        else { prefs.pinnedFolders.append(folder) }
        refresh()
    }

    func toggleProtected(port: Int) {
        if prefs.protectedPorts.contains(port) { prefs.protectedPorts.removeAll { $0 == port } }
        else { prefs.protectedPorts.append(port) }
        refresh()
    }

    // MARK: - Running a dialog

    func present(_ spec: DialogSpec) { dialog = spec }
    func dismissDialog() { dialog = nil }

    func confirmDialog() {
        guard var spec = dialog, let action = spec.action else { dialog = nil; return }
        let chosen = Set(spec.items.filter(\.checked).map(\.id))
        spec.phase = .running
        dialog = spec
        let title = spec.activityTitle ?? spec.title.replacingOccurrences(of: "?", with: "")
        Task.detached {
            let outcome = action(chosen)
            await MainActor.run {
                self.hide(outcome.stoppedIDs, ports: outcome.stoppedPorts)
                if outcome.stopped > 0 || outcome.freedDisk > 0 || outcome.trashedBytes > 0 || outcome.freedMemory > 0 || !outcome.recovery.isEmpty {
                    Store.log(ActivityEntry(kind: .cleanup, title: title,
                                            detail: outcome.summary, recovery: outcome.recovery),
                              historyDays: self.prefs.historyDays)
                }
                if var s = self.dialog, s.id == spec.id {
                    s.phase = .done(summary: outcome.summary, failures: outcome.failures)
                    self.dialog = s
                }
                self.refresh()
                if outcome.freedDisk > 0 { self.refreshDisk() }
            }
        }
    }

    func toggleItem(_ id: String) {
        guard var spec = dialog, let i = spec.items.firstIndex(where: { $0.id == id }), !spec.items[i].required else { return }
        spec.items[i].checked.toggle()
        dialog = spec
    }

    func runRecovery(_ r: Recovery, from entry: ActivityEntry) {
        Task.detached {
            let ok = Actions.recover(r)
            await MainActor.run {
                Store.log(ActivityEntry(kind: .info, title: ok ? "\(r.label) started" : "\(r.label) didn't work",
                                        detail: entry.title), historyDays: self.prefs.historyDays)
                self.reloadFiles()
                self.refresh()
                if case .restoreWorktree = r { self.refreshDisk() }
            }
        }
    }

    // MARK: - Previews for every resource-changing action

    func reviewSweep() {
        let sessions = workspace.sessions.filter { !$0.sweepable.isEmpty }
        let rs = sessions.flatMap(\.sweepable)
        let weak = workspace.sessions.filter { !$0.pinned && !$0.state.isActive }.flatMap { $0.resources.filter { $0.link == .weak } }
        func count(_ kinds: Set<ResourceKind>) -> [Resource] { rs.filter { kinds.contains($0.kind) } }
        var items: [DialogItem] = []
        let servers = count([.server]), watchers = count([.watcher, .browser]), stacks = count([.stack])
        let sims = count([.simulator, .emulator]), tunnels = count([.tunnel])
        if !servers.isEmpty { items.append(DialogItem(id: "server", label: "Dev servers & process groups", detail: "\(servers.count) server\(servers.count == 1 ? "" : "s")")) }
        if !watchers.isEmpty { items.append(DialogItem(id: "watcher", label: "Watchers and headless browsers", detail: "\(watchers.count) process\(watchers.count == 1 ? "" : "es")")) }
        for s in stacks { items.append(DialogItem(id: s.id, label: s.title, detail: "\(s.containerIDs.count) containers")) }
        for d in sims { items.append(DialogItem(id: d.id, label: d.title, detail: "1 device")) }
        if !tunnels.isEmpty { items.append(DialogItem(id: "tunnel", label: "Public tunnels", detail: "\(tunnels.count)")) }
        for w in weak { items.append(DialogItem(id: w.id, label: w.title, detail: "linked by name or timing", checked: false)) }
        let n = sessions.count
        var spec = DialogSpec(title: n == 0 ? "Nothing to put away" : "Put away \(n) session\(n == 1 ? "" : "s")?",
                              subtitle: n == 0 ? "Every session is active, pinned, or already tidy." : "Stop the resources they started. Keep every line of work.",
                              items: items,
                              notes: ["Active and pinned sessions are excluded. Worktrees, source files, and uncommitted changes remain."],
                              confirmTitle: "Close sessions")
        spec.activityTitle = "End-of-day sweep · \(n) session\(n == 1 ? "" : "s")"
        let all = rs + weak
        spec.action = { chosen in
            let pick = all.filter { r in
                chosen.contains(r.id) ||
                (r.kind == .server && chosen.contains("server")) ||
                ([.watcher, .browser].contains(r.kind) && chosen.contains("watcher")) ||
                (r.kind == .tunnel && chosen.contains("tunnel"))
            }
            return Actions.stopAll(pick)
        }
        if n == 0 { spec.action = nil; spec.confirmTitle = "Done" }
        present(spec)
    }

    func reviewClose(_ s: Session) {
        let items = s.resources.map { DialogItem(id: $0.id, label: $0.title, detail: Fmt.bytes($0.memoryBytes), checked: $0.link == .strong) }
        var spec = DialogSpec(title: "Close \(s.project)?",
                              subtitle: "Stop what this session started. Your code and local changes stay in place.",
                              items: items,
                              notes: ["The worktree, source files and uncommitted changes remain. Stopped processes can be relaunched, but their live state can't be restored."],
                              confirmTitle: "Close session")
        if s.state.isActive { spec.warning = "This session is active. Close it in \(s.agent.rawValue) first." ; spec.action = nil; spec.confirmTitle = "OK"; present(spec); return }
        spec.activityTitle = "Closed \(s.project) · \(s.agent.rawValue)"
        let rs = s.resources
        spec.action = { chosen in Actions.stopAll(rs.filter { chosen.contains($0.id) }) }
        present(spec)
    }

    func reviewStop(_ r: Resource) {
        let isPort = r.kind == .server && !r.ports.isEmpty
        let owner = workspace.session(for: r)
        var spec = DialogSpec(icon: isPort ? "point.3.connected.trianglepath.dotted" : "moon",
                              title: isPort ? "Free port :\(r.ports.first!)?" : "Stop \(r.title)?",
                              subtitle: [owner.map { "\($0.project) · \($0.agent.rawValue)" }, r.cwd.map { ($0 as NSString).abbreviatingWithTildeInPath }]
                                .compactMap { $0 }.first ?? r.detail,
                              items: [DialogItem(id: r.id, label: r.title, detail: Fmt.bytes(r.memoryBytes), required: true)],
                              notes: [r.kind == .stack ? "Containers stop; volumes and data stay. Start the stack again any time."
                                      : r.kind == .simulator ? "The simulator shuts down. Its apps and data stay."
                                      : "The process and its child processes stop. Relaunch runs the same command again, but live state is lost."],
                              confirmTitle: isPort ? "Free port" : r.kind == .stack ? "Stop stack" : r.kind == .simulator ? "Shut down" : "Stop")
        spec.activityTitle = (isPort ? "Freed :\(r.ports.first!)" : "Stopped \(r.title)") + " · "
            + (owner?.project ?? r.cwd.map { ($0 as NSString).lastPathComponent } ?? "not tied to a session")
        if let o = owner, !o.agentPids.isEmpty {
            spec.warning = "The \(o.agent.rawValue) session that started this is still open" + (o.state.isActive ? " and working" : "")
                + ", so it may start it again. To keep it stopped, finish that session in \(o.agent.rawValue) first."
        }
        if r.ports.contains(where: isProtected(port:)) || (owner?.pinned ?? false) {
            spec.warning = (owner?.pinned ?? false)
                ? "\(owner!.project) is pinned, so it stays running. Unpin the session first if you want to stop it."
                : "Port :\(r.ports.first { isProtected(port: $0) } ?? 0) is protected. Remove it from the protected list on the Safety page first."
            spec.action = nil
            spec.confirmTitle = "OK"
        } else {
            spec.action = { _ in Actions.stop(r) }
        }
        present(spec)
    }

    func reviewSlim(_ w: Worktree) {
        let names = Set(w.slimDirs.map { ($0 as NSString).lastPathComponent }).sorted().joined(separator: ", ")
        var spec = DialogSpec(icon: "leaf", title: "Slim \(w.branch ?? (w.path as NSString).lastPathComponent)?",
                              subtitle: "Remove rebuildable folders: \(names.isEmpty ? "none found" : names).",
                              items: [DialogItem(id: "slim", label: "Delete dependencies and build output", detail: w.slimBytes.map(Fmt.bytes) ?? "measuring", required: true)],
                              notes: ["Source files, local edits, and .env files stay in place. Reinstall dependencies when you need them."],
                              confirmTitle: "Slim worktree")
        spec.activityTitle = "Slimmed \(w.repoName) / \(w.branch ?? "worktree")"
        if w.status == .inUse { spec.warning = "Something is running in this worktree. Stop it first."; spec.action = nil; spec.confirmTitle = "OK" }
        else if w.slimDirs.isEmpty { spec.action = nil; spec.confirmTitle = "OK" }
        else { spec.action = { _ in Actions.slim(w) } }
        present(spec)
    }

    func reviewRecycle(_ w: Worktree) {
        var spec = DialogSpec(icon: "archivebox", title: "Move \(w.branch ?? "worktree") to the recycle bin?",
                              subtitle: "\(w.repoName) · \(w.status.label)",
                              items: [DialogItem(id: "env", label: "Save ignored files that can't be rebuilt", detail: ".env, keys, local databases", required: true),
                                      DialogItem(id: "remove", label: "Remove the worktree with git", detail: w.sizeBytes.map(Fmt.bytes) ?? "", required: true),
                                      DialogItem(id: "keep", label: "Keep the branch and commit", detail: String(w.head.prefix(7)), required: true)],
                              notes: ["Restore returns it to commit \(w.head.prefix(7)) and puts its saved files back for \(prefs.retentionDays) days. Dependencies like node_modules aren't saved; reinstall them."],
                              confirmTitle: "Move to recycle bin")
        spec.activityTitle = "Moved \(w.repoName) / \(w.branch ?? "worktree") to the recycle bin"
        if let why = Actions.canRecycle(w) { spec.warning = why; spec.action = nil; spec.confirmTitle = "OK" }
        else {
            if w.mayBeClaudeManaged {
                spec.warning = "Claude made this worktree. If a saved Claude app session still points here, it won't find these files until you restore them. No Claude session is running in it right now."
            }
            spec.action = { _ in Self.outcome(Actions.recycle(w), freed: w.sizeBytes) }
        }
        present(spec)
    }

    func reviewPushRemove(_ w: Worktree) {
        let ahead: Int = { if case .unpushed(let n) = w.status { return n }; return 0 }()
        var spec = DialogSpec(title: "Push first. Then put it away.",
                              subtitle: "\(w.branch ?? "This worktree") has \(ahead) commit\(ahead == 1 ? "" : "s") that \(ahead == 1 ? "is" : "are") not on origin.",
                              items: [DialogItem(id: "push", label: "Push branch to origin", detail: "\(ahead) commit\(ahead == 1 ? "" : "s")", required: true),
                                      DialogItem(id: "verify", label: "Verify remote commit matches", detail: "Required", required: true),
                                      DialogItem(id: "bin", label: "Move worktree to recycle bin", detail: "\(prefs.retentionDays) days", required: true)],
                              notes: ["If the push or verification fails, the worktree stays exactly where it is."],
                              confirmTitle: "Push & remove")
        spec.activityTitle = "Pushed and removed \(w.repoName) / \(w.branch ?? "worktree")"
        if w.mayBeClaudeManaged { spec.warning = Actions.canRecycle(w); spec.action = nil; spec.confirmTitle = "OK" }
        else { spec.action = { _ in Self.outcome(Actions.pushAndRecycle(w), freed: w.sizeBytes) } }
        present(spec)
    }

    func reviewRestore(_ e: BinEntry) {
        var spec = DialogSpec(icon: "arrow.uturn.backward", title: "Restore \(e.branch ?? "worktree")?",
                              subtitle: "\(e.repoName) · commit \(e.commit.prefix(7))",
                              items: [DialogItem(id: "wt", label: "Recreate the worktree", detail: (e.worktreePath as NSString).abbreviatingWithTildeInPath, required: true),
                                      DialogItem(id: "env", label: "Put saved files back", detail: "\(e.savedFiles.count) file\(e.savedFiles.count == 1 ? "" : "s")", required: true)],
                              notes: ["Dependencies aren't restored. Reinstall them when you need them."],
                              confirmTitle: "Restore worktree")
        spec.activityTitle = "Restored \(e.repoName) / \(e.branch ?? "worktree")"
        spec.action = { _ in
            switch Actions.restore(e) {
            case .success: var o = Actions.Outcome(); o.stopped = 0; o.recovery = [.reinstallDependencies(path: e.worktreePath)]; o.freedDisk = 0; return o
            case .failure(let err): var o = Actions.Outcome(); o.failures = [err.description]; return o
            }
        }
        present(spec)
    }

    func reviewDeleteDevice(_ d: Device) {
        var spec = DialogSpec(icon: "iphone", title: "Delete \(d.name)?",
                              subtitle: "\(d.runtime) · last used \(Fmt.ago(d.lastUsed))",
                              items: [DialogItem(id: d.udid, label: "Delete simulator device and its data", detail: Fmt.bytes(d.dataBytes), required: true)],
                              notes: ["Apps installed on this simulator and their data are deleted. This can't be undone; Xcode can create a fresh device any time."],
                              confirmTitle: "Delete device", destructive: true)
        spec.activityTitle = "Deleted simulator \(d.name)"
        spec.action = { _ in Actions.deleteDevice(d) }
        present(spec)
    }

    func reviewDeleteBranches(_ g: AgentBranches) {
        var spec = DialogSpec(icon: "arrow.triangle.branch", title: "Delete \(g.branches.count) merged branch\(g.branches.count == 1 ? "" : "es")?",
                              subtitle: "\(g.repoName) · their work is already in the main branch",
                              items: g.branches.map { DialogItem(id: $0, label: $0) },
                              notes: ["Git refuses to delete any branch that isn't fully merged."],
                              confirmTitle: "Delete branches")
        spec.activityTitle = "Deleted merged branches · \(g.repoName)"
        let repo = g.repoPath
        spec.action = { chosen in Actions.deleteMergedBranches(repo: repo, names: Array(chosen)) }
        present(spec)
    }

    // MARK: - Bulk previews: one preview, every item re-checked when it runs

    func reviewBulkRecycle(_ ws: [Worktree]) {
        let list = ws.filter { Actions.canRecycle($0) == nil }
        let total = list.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        let allMerged = list.allSatisfy { $0.status == .merged }
        let noun = (allMerged ? "merged " : "") + "worktree\(list.count == 1 ? "" : "s")"
        var spec = DialogSpec(icon: "archivebox",
                              title: "Move \(list.count) \(noun) to the recycle bin?",
                              subtitle: "\(Fmt.bytes(total)) · " + (allMerged ? "their work is already on the main branch."
                                                                   : "every commit is merged or pushed, so nothing exists only here."),
                              items: list.map { DialogItem(id: $0.path, label: "\($0.repoName) / \($0.branch ?? "detached")", detail: $0.sizeBytes.map(Fmt.bytes) ?? "") },
                              notes: ["Each worktree's ignored files that can't be rebuilt (.env, keys, local databases) are saved first, and its branch and commit stay in git. Restore any of them for \(prefs.retentionDays) days."],
                              confirmTitle: "Move to recycle bin")
        if list.contains(where: \.mayBeClaudeManaged) {
            spec.warning = "Some of these were made by Claude. A saved Claude app session that points to one won't find its files until you restore it. Any worktree with something running in it is skipped."
        }
        spec.activityTitle = "Moved \(list.count) \(noun) to the recycle bin"
        spec.runningNote = "Saving ignored files and removing each worktree with git."
        let byPath = Dictionary(list.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        spec.action = { chosen in
            var o = Actions.Outcome()
            for path in chosen.sorted() { if let w = byPath[path] { o.merge(Self.outcome(Actions.recycle(w), freed: w.sizeBytes)) } }
            return o
        }
        if list.isEmpty {
            spec.title = "Nothing to move"; spec.subtitle = "None of these worktrees are merged and free to remove."
            spec.action = nil; spec.confirmTitle = "OK"; spec.warning = nil
        }
        present(spec)
    }

    func reviewBulkSlim(_ ws: [Worktree]) {
        let list = ws.filter { $0.status != .inUse && ($0.slimBytes ?? 0) > 0 }
        let total = list.reduce(Int64(0)) { $0 + ($1.slimBytes ?? 0) }
        var spec = DialogSpec(icon: "leaf", title: "Slim \(list.count) worktree\(list.count == 1 ? "" : "s")?",
                              subtitle: "Frees about \(Fmt.bytes(total)) of dependencies and build output.",
                              items: list.map { DialogItem(id: $0.path, label: "\($0.repoName) / \($0.branch ?? "detached")", detail: Fmt.bytes($0.slimBytes ?? 0)) },
                              notes: ["Source files, local edits, and .env files stay in place. Reinstall dependencies when you need them."],
                              confirmTitle: "Slim worktrees")
        spec.activityTitle = "Slimmed \(list.count) worktree\(list.count == 1 ? "" : "s")"
        spec.runningNote = "Deleting dependency folders. Large ones can take a minute."
        let byPath = Dictionary(list.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        spec.action = { chosen in
            var o = Actions.Outcome()
            for path in chosen.sorted() { if let w = byPath[path] { o.merge(Actions.slim(w)) } }
            return o
        }
        if list.isEmpty {
            spec.title = "Nothing to slim"; spec.subtitle = "These worktrees have no dependencies or build output to remove."
            spec.action = nil; spec.confirmTitle = "OK"
        }
        present(spec)
    }

    // MARK: - Space Lens

    /// Idle agent worktrees inside `node` that Slim can shrink. Slim's own checks run again when it acts.
    func lensSlimmable(_ node: LensNode) -> [Worktree] {
        guard node.isDir, node.kind != .appData else { return [] }
        return disk.worktrees.filter { ($0.path == node.path || $0.path.hasPrefix(node.path + "/")) && $0.status != .inUse && ($0.slimBytes ?? 0) > 0 }
    }

    /// What Space Lens calls safe to clear: a rebuildable folder itself, or what Slim would free inside a folder.
    func lensSafeBytes(_ node: LensNode) -> Int64 {
        if node.kind == .rebuildable { return node.bytes }
        return lensSlimmable(node).reduce(0) { $0 + ($1.slimBytes ?? 0) }
    }

    func reviewLensTrash(_ n: LensNode) {
        var spec = DialogSpec(icon: "trash", title: "Move \(n.name) to the Trash?",
                              subtitle: "About \(Fmt.bytes(n.bytes)) comes back once you empty the Trash.",
                              items: [DialogItem(id: n.path, label: n.name, detail: Fmt.bytes(n.bytes), required: true)],
                              notes: [n.kind == .rebuildable ? "Tools make it again when you need it, for example with npm install."
                                      : "It stays in the Trash until you empty it, so you can still put it back."],
                              confirmTitle: "Move to Trash")
        spec.activityTitle = "Moved \(n.name) to the Trash"
        spec.runningNote = "Checking it again, then moving it."
        if let why = Actions.trashRefusal(n.path) {
            spec.warning = why; spec.action = nil; spec.confirmTitle = "OK"
        } else {
            let lens = self.lens
            spec.action = { _ in
                let o = Actions.trash([(n.path, n.bytes)])
                Task { @MainActor in if !FileManager.default.fileExists(atPath: n.path) { lens.drop(n.path) } }
                return o
            }
            spec.lockForPro(self)
        }
        present(spec)
    }

    func reviewDeleteDevices(_ ds: [Device]) {
        let list = ds.filter { !$0.booted && !$0.android }.sorted { $0.dataBytes > $1.dataBytes }
        let total = list.reduce(Int64(0)) { $0 + $1.dataBytes }
        var spec = DialogSpec(icon: "iphone", title: "Delete \(list.count) unused simulator device\(list.count == 1 ? "" : "s")?",
                              subtitle: "\(Fmt.bytes(total)) · none used in the last 30 days.",
                              items: list.map { DialogItem(id: $0.udid, label: "\($0.name) · \($0.runtime)", detail: Fmt.bytes($0.dataBytes)) },
                              notes: ["Apps and data on these simulators are deleted. This can't be undone; Xcode can create a fresh device any time."],
                              confirmTitle: "Delete devices", destructive: true)
        spec.activityTitle = "Deleted \(list.count) unused simulator device\(list.count == 1 ? "" : "s")"
        let byID = Dictionary(list.map { ($0.udid, $0) }, uniquingKeysWith: { a, _ in a })
        spec.action = { chosen in
            var o = Actions.Outcome()
            for id in chosen.sorted() { if let d = byID[id] { o.merge(Actions.deleteDevice(d)) } }
            return o
        }
        present(spec)
    }

    nonisolated static func outcome(_ r: Result<BinEntry, Actions.WorktreeError>, freed: Int64?) -> Actions.Outcome {
        var o = Actions.Outcome()
        switch r {
        case .success(let e): o.freedDisk = freed ?? 0; o.recovery = [.restoreWorktree(binID: e.id)]
        case .failure(let err): o.failures = [err.description]
        }
        return o
    }

    // MARK: - Autopilot, budgets, alerts

    private func checkBudgetsAndAlerts() {
        let now = Date()
        func snoozed(_ k: String) -> Bool { (prefs.snoozedUntil[k] ?? .distantPast) > now }
        if prefs.actionableAlerts {
            let stale = workspace.sessions.filter { s in
                s.state.isEnded && !s.sweepable.isEmpty && now.timeIntervalSince(s.lastActivity ?? now) > 30 * 60
            }
            let key = "ended:" + stale.map(\.folder).sorted().joined(separator: "|")
            if !stale.isEmpty, !notified.contains(key), !snoozed("ended") {
                notified.insert(key)
                Notifier.shared.post(id: "ended", title: "\(stale.count) finished session\(stale.count == 1 ? "" : "s") still \(stale.count == 1 ? "has" : "have") resources running.",
                                     body: stale.map(\.project).joined(separator: ", "), actionable: true)
            }
        }
        if prefs.budgetWarnings {
            let booted = workspace.devices.filter(\.booted).count
            if booted > prefs.budgetSimulators, !notified.contains("sims:\(booted)"), !snoozed("budget") {
                notified.insert("sims:\(booted)")
                Notifier.shared.post(id: "sims", title: "\(booted) simulators are running.", body: "Your budget is \(prefs.budgetSimulators).", actionable: false)
            }
            let gb = Int(disk.worktreeBytes / 1_000_000_000)
            if disk.scannedAt != nil, gb > prefs.budgetWorktreeGB, !notified.contains("wt"), !snoozed("budget") {
                notified.insert("wt")
                Notifier.shared.post(id: "wt", title: "Worktrees use \(gb) GB.", body: "Your budget is \(prefs.budgetWorktreeGB) GB. \(Fmt.bytes(disk.slimBytes)) can be slimmed.", actionable: false)
            }
        }
    }
}
