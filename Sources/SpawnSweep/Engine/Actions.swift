import Foundation
import AppKit
import Darwin

/// Everything that changes the Mac. Every function re-checks its safety conditions itself,
/// so a stale preview can never cause harm.
enum Actions {
    struct Outcome {
        var stopped = 0
        var freedMemory: Int64 = 0
        var freedDisk: Int64 = 0
        /// Moved to the Trash: recoverable, so the space only comes back when the Trash is emptied.
        var trashedBytes: Int64 = 0
        var failures: [String] = []
        var recovery: [Recovery] = []
        /// Resources that really stopped, so the UI can drop them before the next scan.
        var stoppedIDs: [String] = []
        var stoppedPorts: [Int] = []

        mutating func merge(_ o: Outcome) {
            stopped += o.stopped; freedMemory += o.freedMemory; freedDisk += o.freedDisk; trashedBytes += o.trashedBytes
            failures += o.failures; recovery += o.recovery
            stoppedIDs += o.stoppedIDs; stoppedPorts += o.stoppedPorts
        }

        var summary: String {
            var parts: [String] = []
            if stopped > 0 { parts.append("Stopped \(stopped) resource\(stopped == 1 ? "" : "s").") }
            if freedMemory > 0 { parts.append("Freed \(Fmt.bytes(freedMemory)) of memory.") }
            if freedDisk > 0 { parts.append("Reclaimed \(Fmt.bytes(freedDisk)) on disk.") }
            if trashedBytes > 0 { parts.append("Moved \(Fmt.bytes(trashedBytes)) to the Trash. Empty it to get the space back.") }
            if parts.isEmpty && failures.isEmpty { parts.append("Nothing changed.") }
            return parts.joined(separator: " ")
        }
    }

    // MARK: - Processes

    /// TERM the root (first ref) and give the tree up to 10 seconds to shut down cleanly (a database flushing to disk),
    /// then TERM what's left, then KILL survivors 2 seconds later. Every signal re-checks it's still the same process.
    static func stopProcesses(_ refs: [ProcRef]) -> (stopped: Int, failed: [Int32]) {
        let me = getpid()
        let live = refs.filter { $0.pid > 1 && $0.pid != me && ProcessTable.isSame($0) }
        func signal(_ rs: [ProcRef], _ sig: Int32) { for r in rs where ProcessTable.isSame(r) { kill(r.pid, sig) } }
        func wait(_ rs: [ProcRef], _ seconds: Double) -> [ProcRef] {
            var remaining = rs.filter { ProcessTable.isSame($0) }
            let deadline = Date().addingTimeInterval(seconds)
            while !remaining.isEmpty && Date() < deadline {
                usleep(250_000)
                remaining = remaining.filter { ProcessTable.isSame($0) }
            }
            return remaining
        }
        var remaining = live
        if let root = live.first, root == refs.first {
            signal([root], SIGTERM)
            remaining = wait(remaining, 10)
        }
        signal(remaining, SIGTERM)
        remaining = wait(remaining, 2)
        signal(remaining, SIGKILL)
        usleep(200_000)
        let failed = remaining.filter { ProcessTable.isSame($0) }.map(\.pid)
        return (live.count - failed.count, failed)
    }

    static func stop(_ r: Resource) -> Outcome {
        var o = Outcome()
        switch r.kind {
        case .server, .watcher, .browser, .tunnel:
            let res = stopProcesses(r.processes)
            if res.failed.isEmpty {
                o.stopped = 1
                o.freedMemory = r.memoryBytes
                if let cmd = r.command, let cwd = r.cwd { o.recovery.append(.relaunch(command: cmd, cwd: cwd)) }
            } else {
                o.failures.append("\(r.title) didn't stop (process \(res.failed.map(String.init).joined(separator: ", "))).")
            }
        case .simulator:
            guard let udid = r.udid else { break }
            let res = Shell.run("/usr/bin/xcrun", ["simctl", "shutdown", udid], timeout: 60)
            if res.ok { o.stopped = 1; o.freedMemory = r.memoryBytes; o.recovery.append(.bootSimulator(udid: udid)) }
            else { o.failures.append("\(r.title): \(res.err.trimmingCharacters(in: .whitespacesAndNewlines))") }
        case .emulator:
            let res = stopProcesses(r.processes)
            if res.failed.isEmpty { o.stopped = 1; o.freedMemory = r.memoryBytes } else { o.failures.append("\(r.title) didn't stop.") }
        case .stack:
            let res = Shell.run("docker", ["stop"] + r.containerIDs, timeout: 120)
            if res.ok { o.stopped = 1; o.freedMemory = r.memoryBytes; o.recovery.append(.startContainers(ids: r.containerIDs)) }
            else { o.failures.append("\(r.title): \(res.err.trimmingCharacters(in: .whitespacesAndNewlines))") }
        }
        if o.stopped > 0 { o.stoppedIDs = [r.id]; o.stoppedPorts = r.ports }
        return o
    }

    static func stopAll(_ rs: [Resource]) -> Outcome {
        var o = Outcome()
        for r in rs { o.merge(stop(r)) }
        return o
    }

    // MARK: - Recovery

    @discardableResult
    static func recover(_ r: Recovery) -> Bool {
        switch r {
        case .relaunch(let cmd, let cwd): return Shell.launchDetached(cmd, cwd: cwd)
        case .bootSimulator(let udid): return Shell.run("/usr/bin/xcrun", ["simctl", "boot", udid], timeout: 60).ok
        case .startContainers(let ids): return Shell.run("docker", ["start"] + ids, timeout: 120).ok
        case .reinstallDependencies(let path): return reinstall(path)
        case .restoreWorktree(let id):
            guard let e = Store.loadBin().first(where: { $0.id == id }) else { return false }
            if case .success = restore(e) { return true }
            return false
        case .reviewRule: return true
        }
    }

    static func reinstall(_ path: String) -> Bool {
        let fm = FileManager.default
        let cmd: String
        if fm.fileExists(atPath: path + "/pnpm-lock.yaml") { cmd = "pnpm install" }
        else if fm.fileExists(atPath: path + "/yarn.lock") { cmd = "yarn install" }
        else if fm.fileExists(atPath: path + "/bun.lockb") || fm.fileExists(atPath: path + "/bun.lock") { cmd = "bun install" }
        else if fm.fileExists(atPath: path + "/package.json") { cmd = "npm install" }
        else { return false }
        return Shell.launchDetached(cmd, cwd: path)
    }

    // MARK: - Simulator devices

    static func deleteDevice(_ d: Device) -> Outcome {
        var o = Outcome()
        guard !d.booted else { o.failures.append("\(d.name) is running. Shut it down first."); return o }
        let r = Shell.run("/usr/bin/xcrun", ["simctl", "delete", d.udid], timeout: 60)
        if r.ok { o.freedDisk = d.dataBytes } else { o.failures.append(r.err) }
        return o
    }

    // MARK: - Worktrees

    enum WorktreeError: Error, CustomStringConvertible {
        case refused(String)
        var description: String { if case .refused(let s) = self { return s }; return "" }
    }

    /// Deletes ignored, rebuildable folders. Source, local edits and .env files stay.
    static func slim(_ w: Worktree) -> Outcome {
        var o = Outcome()
        // Live check: the scan (or the cached disk.json) can be old, and an install or dev server may have started since.
        if DiskScanner.status(w, busy: busyFolders()) == .inUse { o.failures.append("Something is running in this worktree now."); return o }
        let current = Set(DiskScanner.slimCandidates(w.path))   // re-check: still ignored, still a slim folder
        for dir in w.slimDirs where current.contains(dir) && dir.hasPrefix(w.path + "/")
            && DiskScanner.slimNames.contains((dir as NSString).lastPathComponent) {
            // A folder git ignores can still hold files someone force-added; those are real work, so leave it.
            let tracked = Shell.run("git", ["-C", w.path, "ls-files", "--", String(dir.dropFirst(w.path.count + 1))], timeout: 20)
            guard tracked.ok, tracked.out.isEmpty else { o.failures.append("Kept \((dir as NSString).lastPathComponent): git tracks files inside it."); continue }
            let size = Shell.du(dir) ?? 0
            let r = Shell.run("/bin/rm", ["-rf", dir], timeout: 600)
            if r.ok { o.freedDisk += size } else { o.failures.append("Couldn't remove \(dir): \(r.err)") }
        }
        o.recovery.append(.reinstallDependencies(path: w.path))
        return o
    }

    /// Working folders of every running process of this user (agents included).
    static func busyFolders() -> [String] {
        let t = ProcessTable()
        return t.procs.keys.compactMap { t.cwd($0) }.filter { $0 != Shell.home && $0 != "/" }
    }

    static func canRecycle(_ w: Worktree) -> String? {
        if w.mayBeClaudeManaged && w.status != .merged && w.status != .inUse {
            return "This Claude worktree isn't merged yet. Slim it here, or remove it from Claude › Settings › Storage."
        }
        switch w.status {
        case .inUse: return "Something is still running in this worktree."
        case .uncommitted(let n): return "This worktree has \(n) uncommitted change\(n == 1 ? "" : "s"). Commit or stash them first."
        case .unpushed(let n): return "This worktree has \(n) commit\(n == 1 ? "" : "s") that haven't been pushed."
        case .unknown: return "Still checking this worktree."
        case .merged, .pushedNotMerged: return nil
        }
    }

    /// Saves every ignored file a rebuild won't bring back, removes the worktree with git (never --force), keeps the branch.
    /// `git worktree remove` deletes ignored files too, so anything it can't save keeps the worktree where it is.
    static func recycle(_ w: Worktree) -> Result<BinEntry, WorktreeError> {
        // Re-check against the live state, not the scan.
        var live = w
        live.status = DiskScanner.status(w, busy: busyFolders())
        if let why = canRecycle(live) { return .failure(.refused(why)) }
        if DiskScanner.isMainWorktree(w.path, repo: w.repoPath) { return .failure(.refused("This is the repo's main checkout, not a worktree.")) }

        guard let keep = DiskScanner.keepers(w.path) else { return .failure(.refused("Couldn't list this worktree's ignored files, so it stays.")) }
        let sizes = keep.map { ($0, Shell.du(w.path + "/" + $0) ?? 0) }
        let total = sizes.reduce(Int64(0)) { $0 + $1.1 }
        if total > 500_000_000 {
            let biggest = sizes.sorted { $0.1 > $1.1 }.prefix(3).map(\.0).joined(separator: ", ")
            return .failure(.refused("Holds \(Fmt.bytes(total)) of ignored files that can't be rebuilt (\(biggest)). Move them or remove the worktree yourself."))
        }

        var entry = BinEntry(repoPath: w.repoPath, repoName: w.repoName, worktreePath: w.path, branch: w.branch,
                             commit: w.head, removedAt: Date(), sizeBytes: w.sizeBytes ?? 0, savedFiles: [])
        let saveDir = Store.binDir + "/" + entry.id
        let fm = FileManager.default
        for rel in keep {
            let dest = saveDir + "/" + rel
            do {
                try fm.createDirectory(atPath: (dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try fm.copyItem(atPath: w.path + "/" + rel, toPath: dest)
            } catch {
                try? fm.removeItem(atPath: saveDir)
                return .failure(.refused("Couldn't save \(rel), so the worktree stays."))
            }
            entry.savedFiles.append(rel)
        }
        let r = Shell.run("git", ["-C", w.repoPath, "worktree", "remove", "--", w.path], timeout: 300)
        guard r.ok else {
            try? fm.removeItem(atPath: saveDir)
            return .failure(.refused("Git kept the worktree: \(r.err.trimmingCharacters(in: .whitespacesAndNewlines))"))
        }
        Shell.run("git", ["-C", w.repoPath, "worktree", "prune"], timeout: 30)
        Store.updateBin { $0.insert(entry, at: 0) }
        return .success(entry)
    }

    /// Recreates the worktree and puts the saved files back. The bin entry and its files go only when every file made it.
    static func restore(_ e: BinEntry) -> Result<Void, WorktreeError> {
        let fm = FileManager.default
        guard let saveDir = Store.binFolder(e.id) else { return .failure(.refused("This recycle bin entry is damaged.")) }
        if fm.fileExists(atPath: e.worktreePath) { return .failure(.refused("Something already exists at \(e.worktreePath).")) }
        var r = Shell.Result(code: 1, out: "", err: "")
        if let b = e.branch { r = Shell.run("git", ["-C", e.repoPath, "worktree", "add", "--", e.worktreePath, b], timeout: 300) }
        if !r.ok { r = Shell.run("git", ["-C", e.repoPath, "worktree", "add", "--detach", "--", e.worktreePath, e.commit], timeout: 300) }
        guard r.ok else { return .failure(.refused(r.err.trimmingCharacters(in: .whitespacesAndNewlines))) }
        var failed: [String] = []
        for rel in e.savedFiles {
            let dest = e.worktreePath + "/" + rel
            do {
                try fm.createDirectory(atPath: (dest as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try fm.copyItem(atPath: saveDir + "/" + rel, toPath: dest)
            } catch { failed.append(rel) }
        }
        guard failed.isEmpty else {
            return .failure(.refused("The worktree is back, but \(failed.joined(separator: ", ")) couldn't be copied. "
                                     + "They're still in \((saveDir as NSString).abbreviatingWithTildeInPath)."))
        }
        try? fm.removeItem(atPath: saveDir)
        Store.updateBin { $0.removeAll { $0.id == e.id } }
        return .success(())
    }

    /// Pushes the branch, verifies the remote has exactly this commit, then recycles. Any failure keeps the worktree.
    static func pushAndRecycle(_ w: Worktree) -> Result<BinEntry, WorktreeError> {
        guard let branch = w.branch else { return .failure(.refused("This worktree isn't on a branch, so there's nothing to push.")) }
        let defaultName = w.defaultBranch?.split(separator: "/").last.map(String.init)
        if branch == defaultName || ["main", "master"].contains(branch) {
            return .failure(.refused("SpawnSweep never pushes to \(branch)."))
        }
        let changes = Shell.run("git", ["-C", w.path, "status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none"], timeout: 20)
        guard changes.ok else { return .failure(.refused("Couldn't read this worktree's git status, so it stays.")) }
        if !changes.out.isEmpty { return .failure(.refused("Commit or stash local changes first.")) }
        let upstream = Shell.run("git", ["-C", w.path, "rev-parse", "--abbrev-ref", "@{u}"], timeout: 5).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = upstream.contains("/") ? String(upstream.split(separator: "/").first!) : "origin"
        guard Shell.run("git", ["-C", w.path, "remote", "get-url", "--", remote], timeout: 5).ok else {
            return .failure(.refused("There's no \(remote) remote to push to."))
        }
        let push = Shell.run("git", ["-C", w.path, "push", "-u", "--", remote, branch], timeout: 180)
        guard push.ok else { return .failure(.refused("Push failed, so the worktree stays: \(push.err.trimmingCharacters(in: .whitespacesAndNewlines))")) }
        let head = Shell.run("git", ["-C", w.path, "rev-parse", "HEAD"], timeout: 5).out.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteHead = Shell.run("git", ["-C", w.path, "ls-remote", "--", remote, "refs/heads/\(branch)"], timeout: 60).out
            .split(separator: "\t").first.map(String.init) ?? ""
        guard !head.isEmpty, head == remoteHead else {
            return .failure(.refused("The remote commit doesn't match, so the worktree stays."))
        }
        return recycle(w)
    }

    static func deleteMergedBranches(repo: String, names: [String]) -> Outcome {
        var o = Outcome()
        for n in names {
            let r = Shell.run("git", ["-C", repo, "branch", "-d", "--", n], timeout: 10)   // -d refuses unmerged branches
            if r.ok { o.stopped += 1 } else { o.failures.append("\(n): \(r.err.trimmingCharacters(in: .whitespacesAndNewlines))") }
        }
        return o
    }

    /// Drops recycle-bin entries past retention. The branch and commit stay in git; only saved files go.
    static func purgeBin(retentionDays: Int) {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        Store.updateBin { bin in
            for e in bin where e.removedAt < cutoff {
                if let dir = Store.binFolder(e.id) { try? FileManager.default.removeItem(atPath: dir) }
            }
            bin.removeAll { $0.removedAt < cutoff }
        }
    }
    // MARK: - Space Lens

    /// The home folder's own top-level folders. Their contents can go; the folders themselves stay.
    static let standardFolders: Set<String> = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications", "Library"]

    /// Why `path` can't go to the Trash from Space Lens, or nil if it can. Like a cleaner app, nearly everything can:
    /// the Trash is the safety net and the preview warns about projects and app data (`trashWarning`). Locked: macOS
    /// and other accounts, your home and its standard folders, keys and logins, a project's .git on its own, and
    /// anything in use. Links are resolved first, so a link that points elsewhere counts as elsewhere.
    static func trashRefusal(_ path: String, home: String = Shell.home, busy: [String]? = nil) -> String? {
        let h = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        let p = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if p == h { return "It's your home folder." }
        guard p.hasPrefix(h + "/") else {
            guard (p as NSString).deletingLastPathComponent == "/Applications", p.hasSuffix(".app") else {
                return "It's part of macOS or another account on this Mac."
            }
            return NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.resolvingSymlinksInPath().path == p }
                ? "The app is open. Quit it first." : nil
        }
        let parts = p.dropFirst(h.count + 1).split(separator: "/").map(String.init)
        if parts.count == 1, standardFolders.contains(parts[0]) { return "It's one of your Mac's standard folders. Open it to remove what's inside." }
        if parts.first == ".Trash" { return "It's already in the Trash." }
        if parts.first == ".ssh" || parts.first == ".gnupg" || parts.starts(with: ["Library", "Keychains"]) { return "It holds your passwords and keys." }
        if let i = parts.firstIndex(of: ".git") {
            return i == parts.count - 1 ? "It's a project's history on its own. Remove the whole project instead." : "It's part of a project's history."
        }
        if (busy ?? busyFolders()).contains(where: { $0 == p || $0.hasPrefix(p + "/") }) { return "Something is running in it." }
        return nil
    }

    /// What the Remove preview says about `path` before it goes, or nil when there's nothing to flag.
    /// Runs git, so call it off the main thread.
    static func trashWarning(_ path: String, home: String = Shell.home) -> String? {
        let h = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        let p = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let name = (p as NSString).lastPathComponent
        guard p.hasPrefix(h + "/") else { return p.hasSuffix(".app") ? "The app goes. Its data in your Library stays." : nil }
        let rel = String(p.dropFirst(h.count + 1))
        if rel.hasPrefix("Library/") {
            if rel.hasPrefix("Library/Caches/") || rel.hasPrefix("Library/Developer/Xcode/DerivedData/") { return nil }
            if rel.hasPrefix("Library/Developer/CoreSimulator/Devices/") { return "The simulator's apps and data go. Xcode can make a new one." }
            if rel.hasPrefix("Library/Mobile Documents/") { return "It's in iCloud Drive, so it's removed from all your devices." }
            return "App data: the app loses this data and its settings."
        }
        // Inside a project: git can bring back what's committed.
        var dir = (p as NSString).deletingLastPathComponent
        while dir.hasPrefix(h + "/") {
            if FileManager.default.fileExists(atPath: dir + "/.git") {
                // node_modules, build output and the like rebuild on demand.
                if p.dropFirst(dir.count + 1).split(separator: "/").contains(where: { DiskScanner.slimNames.contains(String($0)) }) { return nil }
                let project = (dir as NSString).lastPathComponent
                let st = Shell.run("git", ["-C", dir, "status", "--porcelain", "--untracked-files=all", "--", p], timeout: 20)
                return st.ok && st.out.isEmpty ? "Part of \(project). Git can bring it back." : "Part of \(project), with changes that aren't committed."
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        let repos = gitRepos(under: p)
        if !repos.isEmpty {
            let unsaved = repos.filter(hasUnsavedWork).map { ($0 as NSString).lastPathComponent }
            if unsaved.isEmpty { return "Holds \(repos.count) git project\(repos.count == 1 ? "" : "s"), all committed and pushed." }
            let shown = unsaved.prefix(3).joined(separator: ", ") + (unsaved.count > 3 ? " and \(unsaved.count - 3) more" : "")
            return "Work that isn't committed or pushed in \(shown)."
        }
        if name.hasPrefix("."), !toolCaches.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) {
            return "Settings and data for your tools."
        }
        return nil
    }

    /// Dot folders (relative to home) that only hold tool caches, so the preview has nothing to warn about.
    static let toolCaches: [String] = [".npm", ".cache", ".cocoapods", ".gradle/caches"]

    /// Git repositories and worktrees at or below `path`, a few levels down. Rebuildable folders aren't searched.
    static func gitRepos(under path: String, maxDepth: Int = 6, limit: Int = 200) -> [String] {
        let fm = FileManager.default
        if fm.fileExists(atPath: path + "/.git") { return [path] }
        guard let e = fm.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil,
                                    options: [.skipsPackageDescendants]) else { return [] }
        var out: [String] = []
        for case let url as URL in e {
            if fm.fileExists(atPath: url.path + "/.git") {
                out.append(url.path)
                if out.count >= limit { break }
                e.skipDescendants()
            } else if e.level >= maxDepth || DiskScanner.slimNames.contains(url.lastPathComponent) || url.lastPathComponent == ".git" {
                e.skipDescendants()
            }
        }
        return out
    }

    /// Uncommitted changes, or commits on any branch that no remote has. A git that fails counts as unsaved.
    static func hasUnsavedWork(_ repo: String) -> Bool {
        let st = Shell.run("git", ["-C", repo, "status", "--porcelain", "--untracked-files=all"], timeout: 20)
        guard st.ok, st.out.isEmpty else { return true }
        let rl = Shell.run("git", ["-C", repo, "rev-list", "--count", "--branches", "--not", "--remotes"], timeout: 10)
        return !rl.ok || (Int(rl.out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1) > 0
    }

    /// Moves Space Lens picks to the Trash, checking each one again first. Recoverable until the Trash is emptied.
    static func trash(_ items: [(path: String, bytes: Int64)]) -> Outcome {
        var o = Outcome()
        let busy = busyFolders()
        for (path, bytes) in items {
            let name = (path as NSString).lastPathComponent
            guard FileManager.default.fileExists(atPath: path) else { o.failures.append("\(name) is no longer there."); continue }
            if let why = trashRefusal(path, busy: busy) { o.failures.append("Kept \(name): \(why)"); continue }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                o.trashedBytes += bytes
            } catch {
                o.failures.append("Couldn't move \(name) to the Trash: \(error.localizedDescription)")
            }
        }
        return o
    }
}
