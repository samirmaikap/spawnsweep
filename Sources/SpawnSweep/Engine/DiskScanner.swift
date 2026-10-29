import Foundation

/// The slow scan: worktrees, their status and size, leftover branches, build data, AI app storage.
enum DiskScanner {
    /// Folder names Slim may delete, and only when git ignores them in that worktree.
    static let slimNames: Set<String> = ["node_modules", ".next", ".turbo", ".expo", ".svelte-kit", ".nuxt",
                                         ".parcel-cache", ".angular", ".output", "dist", "build", ".cache",
                                         "target", "DerivedData", ".gradle", "Pods", ".venv", "__pycache__"]
    static let home = Shell.home

    /// Shared, locked accumulator for the concurrent parts of the scan.
    final class Box: @unchecked Sendable {
        var snap: DiskSnapshot
        var done = 0
        let lock = NSLock()
        init(_ s: DiskSnapshot) { snap = s }
        func copy() -> DiskSnapshot { lock.lock(); defer { lock.unlock() }; return snap }
    }

    static func defaultDevFolders() -> [String] {
        ["Sites", "Apps", "Developer", "Projects", "code", "src", "repos", "dev", "work", "GitHub"]
            .map { home + "/" + $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Calls `update` with partial results as they come in, then once more when done.
    static func scan(prefs: Prefs, busyFolders: [String], update: @escaping (DiskSnapshot) -> Void) {
        var snap = DiskSnapshot()
        snap.inProgress = true

        // 1. Find repos and their worktrees (fast).
        let devFolders = prefs.devFolders.isEmpty ? defaultDevFolders() : prefs.devFolders
        var repoPaths = Set<String>()
        for folder in devFolders {
            if isRepo(folder) { repoPaths.insert(folder) }
            // Repos directly inside, or one level deeper (e.g. ~/Sites/client/repo).
            for child in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] where !child.hasPrefix(".") {
                let p = folder + "/" + child
                if isRepo(p) { repoPaths.insert(p); continue }
                for grand in (try? FileManager.default.contentsOfDirectory(atPath: p)) ?? [] where !grand.hasPrefix(".") && grand != "node_modules" {
                    if isRepo(p + "/" + grand) { repoPaths.insert(p + "/" + grand) }
                }
            }
        }
        for agentDir in [home + "/.codex/worktrees", home + "/.cursor/worktrees"] {
            for wt in subfolders(agentDir, depth: 2) {
                let common = Shell.run("git", ["-C", wt, "rev-parse", "--path-format=absolute", "--git-common-dir"], timeout: 5).out
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if common.hasSuffix("/.git") { repoPaths.insert(String(common.dropLast(5))) }
            }
        }

        var repos: [RepoGroup] = []
        var branches: [AgentBranches] = []
        for repo in repoPaths.sorted() {
            let wts = worktrees(of: repo)
            let defaultBranch = defaultBranch(repo)
            if !wts.isEmpty {
                repos.append(RepoGroup(name: (repo as NSString).lastPathComponent, path: repo,
                                       worktrees: wts.map { var w = $0; w.defaultBranch = defaultBranch; return w }))
            }
            if let d = defaultBranch {
                let checkedOut = Set(wts.compactMap(\.branch))
                let merged = Shell.run("git", ["-C", repo, "branch", "--format=%(refname:short)", "--merged", d,
                                               "--list", "claude/*", "codex/*", "cursor/*"], timeout: 10).out
                    .split(separator: "\n").map(String.init).filter { !checkedOut.contains($0) }
                if !merged.isEmpty {
                    branches.append(AgentBranches(repoPath: repo, repoName: (repo as NSString).lastPathComponent, branches: merged))
                }
            }
        }
        snap.repos = repos.sorted { $0.worktrees.count > $1.worktrees.count }
        snap.agentBranches = branches
        update(snap)

        // 2. Status, env files and slim candidates per worktree (medium).
        let box = Box(snap)
        for (ri, repo) in snap.repos.enumerated() {
            DispatchQueue.concurrentPerform(iterations: repo.worktrees.count) { wi in
                var w = repo.worktrees[wi]
                w.status = status(w, busy: busyFolders)
                w.lastUsed = Scanner.lastActivity(w.path)
                w.envFiles = envFiles(w.path)
                w.slimDirs = slimCandidates(w.path)
                box.lock.lock(); box.snap.repos[ri].worktrees[wi] = w; box.lock.unlock()
            }
            update(box.copy())
        }

        // 3. Sizes (slow). Four worktrees at a time.
        let all = box.snap.repos.enumerated().flatMap { ri, r in r.worktrees.indices.map { (ri, $0) } }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        for (ri, wi) in all {
            queue.addOperation {
                let w = box.copy().repos[ri].worktrees[wi]
                let size = Shell.du(w.path)
                let slim = w.slimDirs.reduce(Int64(0)) { $0 + (Shell.du($1) ?? 0) }
                box.lock.lock()
                box.snap.repos[ri].worktrees[wi].sizeBytes = size
                box.snap.repos[ri].worktrees[wi].slimBytes = slim
                box.done += 1
                let emit = box.done % 4 == 0
                let copy = box.snap
                box.lock.unlock()
                if emit { update(copy) }
            }
        }
        queue.waitUntilAllOperationsAreFinished()
        snap = box.copy()
        update(snap)

        // 4. Build data, simulators, AI app storage.
        snap.derivedData = derivedData()
        snap.simulatorDevices = Scanner.simulators(ProcessTable())
        update(snap)
        snap.aiApps = aiApps()
        snap.inProgress = false
        snap.scannedAt = Date()
        update(snap)
    }

    // MARK: - Git

    static func isRepo(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path + "/.git", isDirectory: &dir) && dir.boolValue
    }

    static func subfolders(_ path: String, depth: Int) -> [String] {
        guard depth > 0, let kids = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        var out: [String] = []
        for k in kids where !k.hasPrefix(".") {
            let p = path + "/" + k
            if FileManager.default.fileExists(atPath: p + "/.git") { out.append(p) }
            else { out += subfolders(p, depth: depth - 1) }
        }
        return out
    }

    static func worktrees(of repo: String) -> [Worktree] {
        let r = Shell.run("git", ["-C", repo, "worktree", "list", "--porcelain"], timeout: 10)
        var out: [Worktree] = []
        var path: String?, head = "", branch: String?, seenMain = false
        func flush() {
            defer { path = nil; head = ""; branch = nil }
            guard let p = path else { return }
            // The first record is always the main working tree. The path check also catches a symlinked or re-cased repo path.
            if !seenMain { seenMain = true; return }
            if !samePath(p, repo), FileManager.default.fileExists(atPath: p) {
                out.append(Worktree(path: p, repoPath: repo, repoName: (repo as NSString).lastPathComponent,
                                    branch: branch, head: head, agent: Scanner.worktreeFolder(p + "/")?.1))
            }
        }
        for line in r.out.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("worktree ") { path = String(line.dropFirst(9)) }
            else if line.hasPrefix("HEAD ") { head = String(line.dropFirst(5)) }
            else if line.hasPrefix("branch ") { branch = String(line.dropFirst(7)).replacingOccurrences(of: "refs/heads/", with: "") }
        }
        flush()
        return out
    }

    /// True for the repo's main checkout (git always lists it first), and when git can't say.
    static func isMainWorktree(_ path: String, repo: String) -> Bool {
        let r = Shell.run("git", ["-C", repo, "worktree", "list", "--porcelain"], timeout: 10)
        guard r.ok, let first = r.out.split(separator: "\n").first, first.hasPrefix("worktree ") else { return true }
        return samePath(path, String(first.dropFirst(9))) || samePath(path, repo)
    }

    /// Same folder through symlinks (/var is /private/var) and case. Lowercasing errs toward "same", the safe side for both callers.
    static func samePath(_ a: String, _ b: String) -> Bool {
        func norm(_ p: String) -> String { URL(fileURLWithPath: p).resolvingSymlinksInPath().path.lowercased() }
        return norm(a) == norm(b)
    }

    static func defaultBranch(_ repo: String) -> String? {
        let r = Shell.run("git", ["-C", repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], timeout: 5).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.isEmpty { return r }
        for b in ["main", "master", "develop"] where Shell.run("git", ["-C", repo, "rev-parse", "--verify", "-q", b], timeout: 5).ok {
            return b
        }
        return nil
    }

    static func status(_ w: Worktree, busy: [String]) -> WorktreeStatus {
        if busy.contains(where: { $0 == w.path || $0.hasPrefix(w.path + "/") }) { return .inUse }
        // Every untracked file whatever status.showUntrackedFiles says. A failed or timed-out git is never "clean".
        let st = Shell.run("git", ["-C", w.path, "status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none"], timeout: 20)
        guard st.ok else { return .unknown }
        let changes = st.out.split(separator: "\n").count
        if changes > 0 { return .uncommitted(changes) }
        let rl = Shell.run("git", ["-C", w.path, "rev-list", "--count", "HEAD", "--not", "--remotes"], timeout: 10)
        guard rl.ok, let ahead = Int(rl.out.trimmingCharacters(in: .whitespacesAndNewlines)) else { return .unknown }
        if let d = w.defaultBranch {
            if Shell.run("git", ["-C", w.path, "merge-base", "--is-ancestor", "HEAD", d], timeout: 10).ok { return .merged }
            // Rebased or cherry-picked onto main: every commit's patch already exists there.
            // ponytail: squash merges with a rewritten combined patch aren't detected; patch-id over the whole range would catch them.
            let cherry = Shell.run("git", ["-C", w.path, "cherry", d, "HEAD"], timeout: 10).out.split(separator: "\n")
            if !cherry.isEmpty && cherry.allSatisfy({ $0.hasPrefix("-") }) { return .merged }
        }
        return ahead > 0 ? .unpushed(ahead) : .pushedNotMerged
    }

    // MARK: - Files

    static func envFiles(_ root: String) -> [String] {
        var out: [String] = []
        walk(root, maxDepth: 3) { path, name, isDir in
            if isDir { return !slimNames.contains(name) && name != ".git" }
            if name.hasPrefix(".env") && !name.hasSuffix(".example") && !name.hasSuffix(".sample") && !name.hasSuffix(".template") {
                out.append(path)
            }
            return false
        }
        return out
    }

    /// Ignored files and folders in a worktree that a rebuild won't bring back (databases, keys, local config, nested clones),
    /// as relative paths. Nil when git can't list them, so a failure never reads as "nothing to save".
    static func keepers(_ root: String) -> [String]? {
        let r = Shell.run("git", ["-C", root, "ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory"], timeout: 60)
        guard r.ok else { return nil }
        let all = r.out.split(separator: "\0").map(String.init)
        // git also lists untracked folders that merely hold ignored files ("apps/" next to "apps/api/.env"): keep only the leaves.
        return all.filter { e in !(e.hasSuffix("/") && all.contains { $0 != e && $0.hasPrefix(e) }) }
            .filter { !$0.split(separator: "/").contains { slimNames.contains(String($0)) || $0 == ".DS_Store" } }
            .map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
    }

    /// Rebuildable folders in a worktree that git ignores by their own name. Never returns tracked folders,
    /// or a folder that is only ignored because it sits inside an ignored one (data/ ignored ⇒ data/target).
    static func slimCandidates(_ root: String) -> [String] {
        var found: [String] = []
        walk(root, maxDepth: 4) { path, name, isDir in
            guard isDir, name != ".git" else { return false }
            if slimNames.contains(name) { found.append(path); return false }
            return true
        }
        guard !found.isEmpty else { return [] }
        let rel = found.map { String($0.dropFirst(root.count + 1)) }
        // -v -z records: source NUL linenum NUL pattern NUL path NUL. -v also reports negations ("!dist/"), which un-ignore.
        let f = Shell.run("git", ["-C", root, "check-ignore", "-v", "-z", "--stdin"], timeout: 10,
                          input: rel.joined(separator: "\0") + "\0").out
            .split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var ignored = Set<String>()
        for i in stride(from: 0, to: f.count - 3, by: 4) {
            let pattern = f[i + 2], path = f[i + 3]
            let own = (pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern).split(separator: "/").last.map(String.init)
            if !pattern.hasPrefix("!"), own == (path as NSString).lastPathComponent { ignored.insert(path) }
        }
        return found.filter { ignored.contains(String($0.dropFirst(root.count + 1))) }
    }

    /// Depth-limited directory walk. `visit` returns true to descend into a directory.
    static func walk(_ root: String, maxDepth: Int, visit: (String, String, Bool) -> Bool) {
        func go(_ dir: String, _ depth: Int) {
            guard depth <= maxDepth, let kids = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for k in kids {
                let p = dir + "/" + k
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: p, isDirectory: &isDir) else { continue }
                if visit(p, k, isDir.boolValue) && isDir.boolValue { go(p, depth + 1) }
            }
        }
        go(root, 1)
    }

    // MARK: - Build data and apps

    static func derivedData() -> [DerivedDataEntry] {
        let base = home + "/Library/Developer/Xcode/DerivedData"
        let kids = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
        return kids.filter { !$0.hasPrefix(".") && $0 != "ModuleCache.noindex" }.map { k in
            let p = base + "/" + k
            let plist = NSDictionary(contentsOfFile: p + "/info.plist")
            let ws = plist?["WorkspacePath"] as? String
            return DerivedDataEntry(path: p, workspace: ws, bytes: Shell.du(p) ?? 0,
                                    orphan: ws.map { !FileManager.default.fileExists(atPath: $0) } ?? false)
        }.sorted { $0.bytes > $1.bytes }
    }

    static func aiApps() -> [AppStorage] {
        let candidates: [(String, String, String)] = [
            ("Claude app", home + "/Library/Application Support/Claude", "Clean up worktrees and caches from Claude › Settings › Storage."),
            ("Claude Code", home + "/.claude", "Conversation history, settings and project memory."),
            ("Codex", home + "/.codex", "Sessions, worktrees and logs."),
            ("Cursor", home + "/Library/Application Support/Cursor", "Editor state and caches."),
            ("Cursor agent", home + "/.cursor", "Agent worktrees and extensions.")
        ]
        return candidates.compactMap { name, path, note in
            guard FileManager.default.fileExists(atPath: path), let b = Shell.du(path, timeout: 300) else { return nil }
            return AppStorage(name: name, path: path, bytes: b, note: note)
        }.sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Self-test

    /// `--selftest`: a scratch repo with one worktree checks what Slim may delete, what Recycle saves, how status reads,
    /// and that the main checkout is never listed. Never calls recycle/restore, so the real recycle bin is untouched.
    static func selfTestWorktrees() {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("lo-wt-selftest-\(UUID().uuidString)").path
        defer { try? fm.removeItem(atPath: base) }
        let repo = base + "/repo", wt = base + "/wt"
        func git(_ dir: String, _ args: String...) {
            let r = Shell.run("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false",
                                      "-c", "core.hooksPath=/dev/null"] + args, timeout: 30)
            assert(r.ok, "git \(args.joined(separator: " ")) failed: \(r.err)")
        }
        func write(_ rel: String, in dir: String, _ text: String = "x\n") {
            let p = dir + "/" + rel
            try! fm.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try! text.write(toFile: p, atomically: true, encoding: .utf8)
        }
        try! fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
        git(repo, "init", "-q")
        write(".gitignore", in: repo, "node_modules/\ndata/\n*.sqlite3\nconfig/master.key\n.env\n")
        write("README.md", in: repo)
        git(repo, "add", ".")
        git(repo, "commit", "-qm", "init")
        git(repo, "worktree", "add", "-q", "-b", "feature", "--", wt)
        for f in ["node_modules/x", "data/target/y", "db/dev.sqlite3", "config/master.key", "apps/api/config/.env"] { write(f, in: wt) }

        // Slim: node_modules is ignored by its own pattern; data/target only because data/ is.
        let slim = slimCandidates(wt).map { String($0.dropFirst(wt.count + 1)) }
        assert(slim == ["node_modules"], "slim candidates: \(slim)")

        // Recycle saves what a rebuild won't bring back, and nothing from node_modules.
        let keep = keepers(wt) ?? []
        for k in ["db/dev.sqlite3", "config/master.key", "data", "apps/api/config/.env"] {
            assert(keep.contains(k), "keepers miss \(k): \(keep)")
        }
        assert(!keep.contains { $0.hasPrefix("node_modules") }, "keepers include node_modules: \(keep)")
        assert(!keep.contains("apps") && !keep.contains("db"), "keepers list folders that only hold ignored files: \(keep)")

        // Status sees untracked files whatever the user's config says, and a failed git is never "clean".
        let w = Worktree(path: wt, repoPath: repo, repoName: "repo", branch: "feature", head: "")
        git(wt, "config", "status.showUntrackedFiles", "no")
        write("new.txt", in: wt)
        assert(status(w, busy: []) == .uncommitted(1), "status with an untracked file: \(status(w, busy: []))")
        try! fm.createDirectory(atPath: base + "/plain", withIntermediateDirectories: true)
        let plain = Worktree(path: base + "/plain", repoPath: repo, repoName: "repo", branch: nil, head: "")
        assert(status(plain, busy: []) == .unknown, "status of a non-repo: \(status(plain, busy: []))")

        // The main checkout is never listed, even via a symlink (the temp folder is /var, git reports /private/var).
        try! fm.createSymbolicLink(atPath: base + "/link", withDestinationPath: repo)
        for r in [repo, base + "/link"] {
            let wts = worktrees(of: r)
            assert(wts.count == 1 && samePath(wts[0].path, wt), "worktrees(of: \(r)): \(wts.map(\.path))")
        }
        assert(isMainWorktree(base + "/link", repo: repo) && !isMainWorktree(wt, repo: repo), "isMainWorktree")
    }
}
