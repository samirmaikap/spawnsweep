import Foundation

// MARK: - Agents

enum Agent: String, Codable, CaseIterable, Hashable {
    case claudeCode = "Claude Code"
    case claudeApp = "Claude app"
    case claude = "Claude"          // worktree made by Claude, app or CLI unknown
    case codex = "Codex"
    case cursor = "Cursor"
    case gemini = "Gemini"
    case aider = "Aider"
    case terminal = "Terminal"

    /// SF Symbol used in rows and session tiles.
    var symbol: String {
        switch self {
        case .claudeCode, .claude: return "asterisk"
        case .claudeApp: return "bubble.left"
        case .cursor: return "cursorarrow"
        default: return "terminal"
        }
    }
}

// MARK: - Sessions

enum SessionState: Hashable {
    case active
    case idle(since: Date)
    case ended(since: Date?)

    var isActive: Bool { if case .active = self { return true }; return false }
    var isEnded: Bool { if case .ended = self { return true }; return false }
}

enum LinkStrength: Hashable { case strong, weak }

enum ResourceKind: String, Codable, Hashable {
    case server, watcher, browser, tunnel, simulator, emulator, stack

    var symbol: String {
        switch self {
        case .server: return "apple.terminal"
        case .watcher: return "eye"
        case .browser: return "globe"
        case .tunnel: return "antenna.radiowaves.left.and.right"
        case .simulator, .emulator: return "iphone"
        case .stack: return "shippingbox"
        }
    }
}

/// Something a session started that is still running.
struct Resource: Identifiable, Hashable {
    let id: String
    let kind: ResourceKind
    var title: String
    var detail: String
    var ports: [Int] = []
    var memoryBytes: Int64 = 0
    var startedAt: Date?
    var cwd: String?
    /// Root process plus its descendants, with each pid's start time for identity checks.
    var processes: [ProcRef] = []
    var command: String?
    var udid: String?
    var containerIDs: [String] = []
    var stackProject: String?
    var tunnelTarget: Int?
    var link: LinkStrength = .strong
    /// On a protected port: never stopped by sweeps, Autopilot or the hook.
    var protected = false
    /// Set when this port was stopped from SpawnSweep and something started it again.
    var restartNote: String?

    var rootPid: Int32? { processes.first?.pid }
}

struct ProcRef: Hashable, Codable {
    let pid: Int32
    let start: Double   // seconds since 1970, used to make sure the pid wasn't reused
}

struct Session: Identifiable, Hashable {
    var id: String { folder }
    var folder: String
    var project: String
    var branch: String?
    var agent: Agent
    var state: SessionState
    var resources: [Resource]
    var agentPids: [Int32]
    var startedAt: Date?
    var lastActivity: Date?
    var pinned: Bool
    var isWorktree: Bool

    var memoryBytes: Int64 { resources.reduce(0) { $0 + $1.memoryBytes } }
    var needsAttention: Bool { !pinned && !state.isActive && !resources.isEmpty }
    /// Resources a sweep may stop without asking item by item.
    var sweepable: [Resource] { (pinned || state.isActive) ? [] : resources.filter { $0.link == .strong && !$0.protected } }
}

// MARK: - Workspace snapshot (fast scan)

struct Device: Identifiable, Hashable, Codable {
    var id: String { udid }
    let udid: String
    let name: String
    let runtime: String
    let booted: Bool
    let dataBytes: Int64
    let lastUsed: Date?
    var memoryBytes: Int64 = 0
    var bootedAt: Date?
    var sessionFolder: String?
    var android = false
}

struct Stack: Identifiable, Hashable {
    var id: String { project }
    let project: String
    var containers: [String]      // container ids
    var names: [String]
    var workingDir: String?
    var memoryBytes: Int64
    var startedAt: Date?
    var ports: [Int]
}

struct Tunnel: Identifiable, Hashable {
    var id: Int32 { pid }
    let pid: Int32
    let tool: String
    let targetPort: Int?
    let resource: Resource
}

struct Workspace {
    var sessions: [Session] = []
    /// Running things with no agent session behind them. Never swept in bulk.
    var unattached: [Resource] = []
    var devices: [Device] = []
    var stacks: [Stack] = []
    var tunnels: [Tunnel] = []
    var scannedAt: Date = .distantPast

    var allResources: [Resource] { sessions.flatMap(\.resources) + unattached }
    var servers: [Resource] { allResources.filter { $0.kind == .server } }

    func session(for resource: Resource) -> Session? {
        sessions.first { $0.resources.contains { $0.id == resource.id } }
    }
}

// MARK: - Disk snapshot (slow scan)

enum WorktreeStatus: Hashable, Codable {
    case inUse
    case uncommitted(Int)
    case unpushed(Int)
    case pushedNotMerged
    case merged
    case unknown

    var label: String {
        switch self {
        case .inUse: return "In use"
        case .uncommitted(let n): return "\(n) uncommitted file\(n == 1 ? "" : "s")"
        case .unpushed(let n): return "Unmerged · \(n) commit\(n == 1 ? "" : "s") ahead of origin"
        case .pushedNotMerged: return "Pushed, not merged"
        case .merged: return "Merged"
        case .unknown: return "Checking…"
        }
    }
}

/// Status filter shared by Storage and the repo page, so a filter survives opening a repo.
enum WorktreeFilter: Hashable, CaseIterable {
    case all, merged, pushed, unpushed, changes, inUse

    var title: String {
        switch self {
        case .all: return "All"
        case .merged: return "Merged"
        case .pushed: return "Pushed"
        case .unpushed: return "Unpushed"
        case .changes: return "Changes"
        case .inUse: return "In use"
        }
    }

    func matches(_ s: WorktreeStatus) -> Bool {
        switch (self, s) {
        case (.all, _), (.merged, .merged), (.pushed, .pushedNotMerged), (.unpushed, .unpushed),
             (.changes, .uncommitted), (.inUse, .inUse): return true
        default: return false
        }
    }

    /// "41 merged worktrees"
    func describe(_ n: Int) -> String {
        let wt = "worktree\(n == 1 ? "" : "s")"
        switch self {
        case .all: return "\(n) \(wt)"
        case .merged: return "\(n) merged \(wt)"
        case .pushed: return "\(n) pushed, unmerged \(wt)"
        case .unpushed: return "\(n) \(wt) with unpushed commits"
        case .changes: return "\(n) \(wt) with uncommitted changes"
        case .inUse: return "\(n) \(wt) in use"
        }
    }
}

struct Worktree: Identifiable, Hashable, Codable {
    var id: String { path }
    let path: String
    let repoPath: String
    let repoName: String
    var branch: String?
    var head: String
    var status: WorktreeStatus = .unknown
    var sizeBytes: Int64?
    var slimBytes: Int64?
    var slimDirs: [String] = []
    var lastUsed: Date?
    var agent: Agent?
    var envFiles: [String] = []
    var defaultBranch: String?

    /// Worktrees made by the Claude app may belong to a saved session; we slim them but never remove them.
    var mayBeClaudeManaged: Bool { path.contains("/.claude/worktrees/") }
}

struct RepoGroup: Identifiable, Hashable, Codable {
    var id: String { path }
    let name: String
    let path: String
    var worktrees: [Worktree]
    var totalBytes: Int64 { worktrees.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }
    var slimBytes: Int64 { worktrees.reduce(0) { $0 + ($1.slimBytes ?? 0) } }
}

struct AgentBranches: Identifiable, Hashable, Codable {
    var id: String { repoPath }
    let repoPath: String
    let repoName: String
    let branches: [String]
}

struct DerivedDataEntry: Identifiable, Hashable, Codable {
    var id: String { path }
    let path: String
    let workspace: String?
    let bytes: Int64
    var orphan: Bool
}

struct AppStorage: Identifiable, Hashable, Codable {
    var id: String { path }
    let name: String
    let path: String
    let bytes: Int64
    let note: String
}

struct DiskSnapshot: Codable {
    var repos: [RepoGroup] = []
    var agentBranches: [AgentBranches] = []
    var derivedData: [DerivedDataEntry] = []
    var simulatorDevices: [Device] = []
    var aiApps: [AppStorage] = []
    var scannedAt: Date?
    var inProgress = false

    var worktrees: [Worktree] { repos.flatMap(\.worktrees) }
    var worktreeBytes: Int64 { repos.reduce(0) { $0 + $1.totalBytes } }
    var slimBytes: Int64 { repos.reduce(0) { $0 + $1.slimBytes } }
    var orphanDerivedBytes: Int64 { derivedData.filter(\.orphan).reduce(0) { $0 + $1.bytes } }
    var unusedDevices: [Device] {
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        return simulatorDevices.filter { !$0.booted && ($0.lastUsed ?? .distantPast) < cutoff }
    }
    var unusedDeviceBytes: Int64 { unusedDevices.reduce(0) { $0 + $1.dataBytes } }
    var buildBytes: Int64 { orphanDerivedBytes + unusedDeviceBytes }
    var totalDevBytes: Int64 {
        worktreeBytes + derivedData.reduce(0) { $0 + $1.bytes } + simulatorDevices.reduce(0) { $0 + $1.dataBytes }
    }
    var envCopies: [(repo: String, files: [String], worktrees: Int)] {
        repos.compactMap { r in
            let wts = r.worktrees.filter { !$0.envFiles.isEmpty }
            let files = wts.flatMap(\.envFiles)
            return files.isEmpty ? nil : (r.name, files, wts.count)
        }
    }
}

// MARK: - Persisted state

enum RuleKind: Codable, Hashable {
    case simulatorIdle(hours: Int)
    case endedLeftovers(minutes: Int)
    case slimIdleWorktrees(days: Int)
    case recycleMerged(days: Int)
    case endOfDay(hour: Int)
    case onBattery
    case lowDisk(gb: Int)

    var summary: String {
        switch self {
        case .simulatorIdle(let h): return "Shut down simulators idle for \(h) hour\(h == 1 ? "" : "s")"
        case .endedLeftovers(let m): return "Stop leftovers \(m) minutes after an agent session ends"
        case .slimIdleWorktrees(let d): return "Slim worktrees nobody touched for \(d) days"
        case .recycleMerged(let d): return "Move merged worktrees untouched for \(d) days to the recycle bin"
        case .endOfDay(let h): return "From \(Fmt.hour(h)), put away what finished sessions left and shut down idle simulators"
        case .onBattery: return "On battery, shut down idle simulators and stop what finished sessions left"
        case .lowDisk(let gb): return "Below \(gb) GB free, slim the largest idle worktrees"
        }
    }

    var symbol: String {
        switch self {
        case .simulatorIdle: return "iphone"
        case .endedLeftovers: return "moon"
        case .slimIdleWorktrees: return "leaf"
        case .recycleMerged: return "archivebox"
        case .endOfDay: return "moon.stars"
        case .onBattery: return "battery.50percent"
        case .lowDisk: return "internaldrive"
        }
    }

    /// The condition that has to hold before the rule acts on its own; nil for rules that only wait on time.
    var trigger: String? {
        switch self {
        case .endOfDay(let h): return "from \(Fmt.hour(h))"
        case .onBattery: return "on battery"
        case .lowDisk(let gb): return "below \(gb) GB free"
        default: return nil
        }
    }

    /// What stays safe, shown under every preview of this rule.
    var note: String {
        switch self {
        case .simulatorIdle: return "Simulators keep their apps and data. Boot one again from Activity."
        case .endedLeftovers, .endOfDay, .onBattery:
            return "Active and pinned sessions are skipped. Each process is checked before it stops, and Activity can relaunch it."
        case .slimIdleWorktrees, .lowDisk: return "Only folders git ignores are deleted. Source, local edits and .env files stay."
        case .recycleMerged: return "Each worktree is checked again first. Its branch stays in git, its .env files are saved, and Restore brings it back."
        }
    }
}

/// How far a rule is trusted: record only, ask with a notification, or act and log.
enum RuleMode: String, Codable, CaseIterable {
    case dryRun, ask, auto
    var label: String {
        switch self {
        case .dryRun: return "Dry run"
        case .ask: return "Ask first"
        case .auto: return "Automatic"
        }
    }

    /// Ask first and Automatic act only in a build that has Pro and holds a valid license. Otherwise the rule previews only.
    func effective(hasPro: Bool, licensed: Bool) -> RuleMode { hasPro && licensed ? self : .dryRun }
}

struct Rule: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kind: RuleKind
    var mode: RuleMode = .dryRun
    var enabled = true

    init(name: String, kind: RuleKind, mode: RuleMode = .dryRun) {
        self.name = name; self.kind = kind; self.mode = mode
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, mode, enabled, dryRun }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(RuleKind.self, forKey: .kind)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        // Rules saved before modes existed carried a dry-run flag instead.
        mode = try c.decodeIfPresent(RuleMode.self, forKey: .mode)
            ?? (try c.decodeIfPresent(Bool.self, forKey: .dryRun) == false ? .auto : .dryRun)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(mode, forKey: .mode)
        try c.encode(enabled, forKey: .enabled)
    }
}

enum Recovery: Codable, Hashable {
    case relaunch(command: String, cwd: String)
    case restoreWorktree(binID: String)
    case reinstallDependencies(path: String)
    case bootSimulator(udid: String)
    case startContainers(ids: [String])
    case reviewRule(id: UUID)

    var label: String {
        switch self {
        case .relaunch: return "Relaunch"
        case .restoreWorktree: return "Restore worktree"
        case .reinstallDependencies: return "Reinstall dependencies"
        case .bootSimulator: return "Boot simulator"
        case .startContainers: return "Start stack"
        case .reviewRule: return "Review rule"
        }
    }
}

enum ActivityKind: String, Codable { case cleanup, dryRun, info }

struct ActivityEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var kind: ActivityKind
    var title: String
    var detail: String
    var recovery: [Recovery] = []
    var dedupeKey: String?
}

struct BinEntry: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    let repoPath: String
    let repoName: String
    let worktreePath: String
    let branch: String?
    let commit: String
    let removedAt: Date
    let sizeBytes: Int64
    var savedFiles: [String]
}

struct Prefs: Codable {
    var devFolders: [String] = []
    var pinnedFolders: [String] = []
    var protectedPorts: [Int] = []
    var retentionDays = 7
    var historyDays = 30
    var appearance = "system"
    var actionableAlerts = true
    var budgetWarnings = true
    var budgetSimulators = 2
    var budgetWorktreeGB = 30
    var rules: [Rule] = [
        Rule(name: "Simulator bedtime", kind: .simulatorIdle(hours: 2)),
        Rule(name: "Finished means finished", kind: .endedLeftovers(minutes: 30)),
        Rule(name: "End of day", kind: .endOfDay(hour: 19))
    ]
    var onboarded = false
    var snoozedUntil: [String: Date] = [:]
}

extension Prefs {
    /// Every key falls back to its default, so a setting added later (or one an older file never had)
    /// can't throw away the rest of someone's preferences. Rules that no longer decode are skipped one by one.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        devFolders = c.value(.devFolders, or: devFolders)
        pinnedFolders = c.value(.pinnedFolders, or: pinnedFolders)
        protectedPorts = c.value(.protectedPorts, or: protectedPorts)
        retentionDays = c.value(.retentionDays, or: retentionDays)
        historyDays = c.value(.historyDays, or: historyDays)
        appearance = c.value(.appearance, or: appearance)
        actionableAlerts = c.value(.actionableAlerts, or: actionableAlerts)
        budgetWarnings = c.value(.budgetWarnings, or: budgetWarnings)
        budgetSimulators = c.value(.budgetSimulators, or: budgetSimulators)
        budgetWorktreeGB = c.value(.budgetWorktreeGB, or: budgetWorktreeGB)
        if let saved = try? c.decodeIfPresent([Lossy<Rule>].self, forKey: .rules) { rules = saved.compactMap(\.value) }
        onboarded = c.value(.onboarded, or: onboarded)
        snoozedUntil = c.value(.snoozedUntil, or: snoozedUntil)
    }
}

extension KeyedDecodingContainer {
    /// The saved value, or `fallback` when the key is missing or no longer decodes.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T { (try? decodeIfPresent(T.self, forKey: key)) ?? fallback }
}

/// Decodes to nil instead of failing, so one bad element doesn't sink the whole array.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

// MARK: - Formatting

enum Fmt {
    /// RAM in binary units, as Activity Monitor shows it (24 GB, not 25.8 GB). Disk sizes stay decimal, like Finder.
    static func memory(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .memory) }

    /// 19 → "7 PM".
    static func hour(_ h: Int) -> String { "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "AM" : "PM")" }

    static func bytes(_ b: Int64) -> String {
        if b <= 0 { return "0 MB" }
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB")]
        let v = Double(b)
        for (size, name) in units where v >= size {
            let n = v / size
            return n >= 10 ? "\(Int(n.rounded())) \(name)" : String(format: "%.1f \(name)", n)
        }
        return String(format: "%.1f MB", v / 1e6)
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1))m"
    }

    static func ago(_ date: Date?) -> String {
        guard let date else { return "unknown" }
        let t = Date().timeIntervalSince(date)
        if t < 60 { return "just now" }
        let days = Int(t / 86400)
        if days == 1 { return "yesterday" }
        if days > 1 { return "\(days) days ago" }
        return "\(duration(t)) ago"
    }

    /// "Nov 12".
    static func date(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day()) }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
