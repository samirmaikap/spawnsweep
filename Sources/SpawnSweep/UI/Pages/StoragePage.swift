import SwiftUI
import AppKit

struct StoragePage: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .worktrees
    @State private var showAllDevices = false

    private enum Tab: Hashable { case worktrees, builds, apps }

    private var measuring: Bool { model.disk.inProgress || model.diskScanning }

    var body: some View {
        PageScroll {
            PageHeader(title: "Keep the work. Lose the weight.",
                       subtitle: "Dependencies, build output, and forgotten copies add up.") {
                if model.reclaimableDisk > 0 {
                    Button("Review cleanup", action: reviewCleanup).buttonStyle(.primary)
                }
            }
            hero
            VStack(alignment: .leading, spacing: 20) {
                ChipTabs(selection: $tab, options: [(.worktrees, "Worktrees"), (.builds, "Build & simulators"), (.apps, "AI app storage")])
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .worktrees: worktreesTab
                    case .builds: buildsTab
                    case .apps: appsTab
                    }
                }
            }
        }
    }

    /// Opens the repo with the most to slim; otherwise the build tab, where the rest of the reclaimable space lives.
    private func reviewCleanup() {
        if let repo = model.disk.repos.max(by: { $0.slimBytes < $1.slimBytes }), repo.slimBytes > 0 {
            model.openRepo(repo.path)
        } else {
            tab = .builds
        }
    }

    // MARK: - Hero

    private var hero: some View {
        let d = model.disk
        let deps = d.slimBytes, build = d.buildBytes, total = d.totalDevBytes
        let kept = max(0, total - deps - build)
        let firstScan = model.diskUpdatedAt == nil
        return HeroCard(padding: 26) {
            // Fixed height so the list below doesn't jump while sizes come in.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        if total == 0 && measuring && firstScan {
                            // Very first scan: no saved numbers to show yet.
                            SkeletonBlock(width: 180, height: 30).padding(.vertical, 4)
                            scanStatus
                        } else if deps + build == 0 {
                            Text("Nothing to reclaim").font(.system(size: 32)).tracking(-0.8).foregroundStyle(Theme.text)
                            Text(measuring && firstScan ? "Still measuring. Dependencies show up here as they're found."
                                                        : "No dependencies, orphan build data, or unused simulators to clear.")
                        } else {
                            Text(Fmt.bytes(deps + build)).font(.system(size: 32)).tracking(-0.8).monospacedDigit()
                                .foregroundStyle(Theme.text).contentTransition(.numericText())
                            Text("can be reclaimed without deleting code")
                        }
                    }
                    .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 16)
                    if total > 0 { Chip(text: "\(Fmt.bytes(total)) total development storage").monospacedDigit() }
                }
                if total > 0 {
                    StorageBar(segments: [(deps, Theme.accent), (build, Theme.accent.opacity(0.5)), (kept, Theme.accent.opacity(0.22))],
                               total: total)
                        .padding(.top, 24)
                    Text("\(Fmt.bytes(deps)) dependencies · \(Fmt.bytes(build)) build & simulator data · \(Fmt.bytes(kept)) kept")
                        .monospacedDigit()
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        .padding(.top, 16)
                    scanStatus.font(.meta).foregroundStyle(Theme.secondary).padding(.top, 8)
                }
            }
            .frame(minHeight: 150, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Updating · measured 34 of 81" while scanning, "Measured 5 minutes ago" when idle.
    @ViewBuilder private var scanStatus: some View {
        let n = model.diskMeasured, of = model.diskTotal
        if measuring {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                if model.diskUpdatedAt == nil {
                    Text(of > 0 ? "Measured \(n) of \(of) worktree\(of == 1 ? "" : "s")" : "Looking for worktrees…")
                } else {
                    Text(of > 0 ? "Updating · measured \(n) of \(of)" : "Updating…")
                }
            }
            .monospacedDigit()
        } else if let at = model.diskUpdatedAt {
            TimelineView(.periodic(from: .now, by: 30)) { _ in Text("Measured \(Fmt.ago(at))") }
        }
    }

    // MARK: - Worktrees

    private func count(_ f: WorktreeFilter) -> Int { model.disk.worktrees.filter { f.matches($0.status) }.count }

    /// The chosen filter, or All once nothing matches it anymore (its chip is hidden then).
    private var activeFilter: WorktreeFilter {
        let f = model.worktreeFilter
        return f == .all || count(f) > 0 ? f : .all
    }
    private var filtered: Bool { activeFilter != .all }

    /// Every repo, or only repos with matching worktrees, each holding just those worktrees.
    private var visibleRepos: [RepoGroup] {
        let f = activeFilter
        guard f != .all else { return model.disk.repos }
        return model.disk.repos.compactMap { r in
            let ws = r.worktrees.filter { f.matches($0.status) }
            return ws.isEmpty ? nil : RepoGroup(name: r.name, path: r.path, worktrees: ws)
        }
    }

    @ViewBuilder private var worktreesTab: some View {
        let repos = visibleRepos
        Panel(title: "Worktrees") {
            if repos.isEmpty {
                if measuring { SkeletonRows() }
                else {
                    EmptyState(symbol: "arrow.triangle.branch", title: "No worktrees found",
                               message: "SpawnSweep looks for git worktrees in your development folders and agent worktree folders.")
                }
            } else {
                ChipTabs(selection: Binding(get: { activeFilter }, set: { model.worktreeFilter = $0 }),
                         options: WorktreeFilter.allCases.compactMap { f in
                             let n = count(f)
                             return f == .all || n > 0 ? (f, "\(f.title) \(n)") : nil
                         })
                    .monospacedDigit()
                bulkRow(repos)
                RowList(items: repos) { r in repoRow(r) }
            }
        }
        if !model.disk.agentBranches.isEmpty {
            Panel(title: "Leftover agent branches") {
                RowList(items: model.disk.agentBranches) { g in
                    ResourceRow(symbol: "arrow.triangle.branch", title: g.repoName, subtitle: branchDetail(g),
                                value: "\(g.branches.count) branch\(g.branches.count == 1 ? "" : "es")") {
                        Button("Review") { model.reviewDeleteBranches(g) }.buttonStyle(.quiet)
                    }
                    .help(g.repoPath)
                }
            }
        }
        InfoBanner(text: "Slim removes node_modules and build output. Source files, local edits, and .env files stay in place.")
    }

    /// "41 merged worktrees across 6 repos" on the left, one preview for all of them on the right.
    private func bulkRow(_ repos: [RepoGroup]) -> some View {
        let scope = repos.flatMap(\.worktrees)
        let r = repos.count
        return HStack(spacing: 12) {
            Text("\(activeFilter.describe(scope.count)) across \(r) repo\(r == 1 ? "" : "s")")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary).monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 16)
            BulkWorktreeActions(worktrees: scope)
        }
    }

    /// One repo per row; the whole row opens its worktrees as cards.
    private func repoRow(_ r: RepoGroup) -> some View {
        let unsized = r.worktrees.filter { $0.sizeBytes == nil }.count
        return Button { model.openRepo(r.path) } label: {
            ResourceRow(symbol: "arrow.triangle.branch", title: r.name, subtitle: repoDetail(r, unsized: unsized),
                        value: unsized == r.worktrees.count ? "Measuring…" : Fmt.bytes(r.totalBytes)) {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                    .padding(.leading, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(r.path)
        .accessibilityLabel("Open \(r.name), \(r.worktrees.count) worktrees")
    }

    private func repoDetail(_ r: RepoGroup, unsized: Int) -> String {
        let n = r.worktrees.count
        var parts = ["\(n) worktree\(n == 1 ? "" : "s")"]
        if r.slimBytes > 0 { parts.append("\(Fmt.bytes(r.slimBytes)) dependencies") }
        else if unsized == 0 { parts.append("no dependencies to slim") }
        let other = r.totalBytes - r.slimBytes
        if other > 0 { parts.append("\(Fmt.bytes(other)) code & other") }
        if unsized > 0 { parts.append("measuring…") }
        let unpushed = r.worktrees.filter { if case .unpushed = $0.status { return true }; return false }.count
        if unpushed > 0 { parts.append("\(unpushed) with unpushed commits") }
        return parts.joined(separator: " · ")
    }

    private func branchDetail(_ g: AgentBranches) -> String {
        let prefixes = Set(g.branches.compactMap { $0.split(separator: "/").first.map { "\($0)/*" } }).sorted().joined(separator: ", ")
        let n = g.branches.count
        return "\(n) merged \(prefixes) branch\(n == 1 ? "" : "es") · no linked worktrees"
    }

    // MARK: - Build & simulators

    private struct SummaryRow: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let subtitle: String
        let bytes: Int64
        var review: (() -> Void)?
    }

    @ViewBuilder private var buildsTab: some View {
        let dd = model.disk.derivedData
        let orphans = dd.filter(\.orphan), current = dd.filter { !$0.orphan }
        let sims = model.disk.simulatorDevices, unused = model.disk.unusedDevices
        let rows = buildRows(orphans: orphans, current: current, sims: sims, unused: unused)
        Panel(title: "Build output") {
            if rows.isEmpty {
                if measuring { SkeletonRows(count: 2) }
                else {
                    EmptyState(symbol: "hammer", title: "No build data found",
                               message: "Xcode DerivedData and simulator devices appear here.")
                }
            } else {
                RowList(items: rows) { row in
                    ResourceRow(symbol: row.symbol, title: row.title, subtitle: row.subtitle, value: Fmt.bytes(row.bytes)) {
                        if let review = row.review { Button("Review", action: review).buttonStyle(.quiet) }
                    }
                }
            }
        }
        if !unused.isEmpty { unusedDevicesPanel(unused) }
    }

    /// Largest first; the five biggest are listed, the rest fold into one row.
    private func unusedDevicesPanel(_ unused: [Device]) -> some View {
        let sorted = unused.sorted { $0.dataBytes > $1.dataBytes }
        let rest = sorted.dropFirst(5)
        let visible = showAllDevices ? sorted : Array(sorted.prefix(5))
        let total = sorted.reduce(Int64(0)) { $0 + $1.dataBytes }
        let restBytes = rest.reduce(Int64(0)) { $0 + $1.dataBytes }
        return Panel(title: "Unused simulator devices", trailing: {
            if sorted.count > 1 {
                Button("Review all · \(Fmt.bytes(total))") { model.reviewDeleteDevices(model.disk.unusedDevices) }
                    .buttonStyle(.quiet).monospacedDigit()
            }
        }) {
            VStack(spacing: 0) {
                RowList(items: visible) { d in
                    ResourceRow(symbol: "iphone", title: d.runtime.isEmpty ? d.name : "\(d.name) · \(d.runtime)",
                                subtitle: d.lastUsed.map { "Last used \(Fmt.ago($0)) · not booted" } ?? "No recorded use · not booted",
                                value: Fmt.bytes(d.dataBytes)) {
                        Button("Review removal") { model.reviewDeleteDevice(d) }.buttonStyle(.quiet)
                    }
                }
                if !rest.isEmpty {
                    ShowMoreButton(expanded: showAllDevices, hiddenCount: rest.count, detail: Fmt.bytes(restBytes)) { showAllDevices.toggle() }
                }
            }
        }
    }

    private func buildRows(orphans: [DerivedDataEntry], current: [DerivedDataEntry], sims: [Device], unused: [Device]) -> [SummaryRow] {
        func folders(_ n: Int) -> String { "\(n) folder\(n == 1 ? "" : "s")" }
        func sum(_ es: [DerivedDataEntry]) -> Int64 { es.reduce(0) { $0 + $1.bytes } }
        var rows: [SummaryRow] = []
        if !orphans.isEmpty {
            rows.append(SummaryRow(id: "orphan", symbol: "hammer", title: "Orphan Xcode DerivedData",
                                   subtitle: "\(folders(orphans.count)) whose project folder no longer exists",
                                   bytes: sum(orphans), review: { reviewOrphans(orphans) }))
        }
        if !current.isEmpty {
            rows.append(SummaryRow(id: "derived", symbol: "hammer", title: "Xcode DerivedData",
                                   subtitle: "\(folders(current.count)) for projects still on this Mac · kept for faster builds",
                                   bytes: sum(current)))
        }
        if !sims.isEmpty {
            let n = sims.count
            rows.append(SummaryRow(id: "sims", symbol: "iphone", title: "Simulator devices",
                                   subtitle: "\(n) device\(n == 1 ? "" : "s") · " + (unused.isEmpty ? "all used in the last 30 days"
                                                                                     : "\(unused.count) unused for more than 30 days"),
                                   bytes: sims.reduce(0) { $0 + $1.dataBytes }))
        }
        return rows
    }

    private func reviewOrphans(_ entries: [DerivedDataEntry]) {
        let n = entries.count
        var spec = DialogSpec(icon: "hammer",
                              title: "Remove \(n) orphan DerivedData folder\(n == 1 ? "" : "s")?",
                              subtitle: "Their Xcode projects no longer exist on this Mac.",
                              items: entries.map { e in
                                  DialogItem(id: e.path, label: e.workspace.map { ($0 as NSString).lastPathComponent } ?? (e.path as NSString).lastPathComponent,
                                             detail: Fmt.bytes(e.bytes))
                              },
                              notes: ["Only build products and indexes inside ~/Library/Developer/Xcode/DerivedData are deleted. No source code is touched, and Xcode rebuilds this data if the project comes back."],
                              confirmTitle: "Remove build data")
        spec.action = { chosen in OrphanDerivedData.remove(Array(chosen)) }
        model.present(spec)
    }

    // MARK: - AI app storage

    @ViewBuilder private var appsTab: some View {
        let apps = model.disk.aiApps
        Panel(title: "Application storage") {
            if apps.isEmpty {
                if measuring { SkeletonRows(count: 2) }
                else {
                    EmptyState(symbol: "sparkles", title: "No AI app storage found",
                               message: "Storage for Claude, Codex, and Cursor appears here when they're installed.")
                }
            } else {
                RowList(items: apps) { a in
                    ResourceRow(symbol: Agent.allCases.first { a.name.hasPrefix($0.rawValue) }?.symbol ?? "folder",
                                title: a.name, subtitle: a.note, value: Fmt.bytes(a.bytes)) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: a.path)]) }
                            .buttonStyle(.quiet)
                    }
                    .help(a.path)
                }
            }
        }
        InfoBanner(text: "App-managed worktrees go through that app's cleanup. SpawnSweep won't bypass it.")
    }
}

// MARK: - Orphan DerivedData removal

/// Deletes DerivedData folders whose Xcode project is gone. Re-checks every condition at run time,
/// so a stale preview can't delete anything else.
enum OrphanDerivedData {
    static let base = Shell.home + "/Library/Developer/Xcode/DerivedData"

    static func remove(_ paths: [String]) -> Actions.Outcome {
        var o = Actions.Outcome()
        for path in paths {
            if let why = refusal(path) { o.failures.append(why); continue }
            let size = Shell.du(path) ?? 0
            do {
                try FileManager.default.removeItem(atPath: path)
                o.freedDisk += size
            } catch {
                o.failures.append("Couldn't remove \((path as NSString).lastPathComponent): \(error.localizedDescription)")
            }
        }
        return o
    }

    /// Why a path must not be deleted, or nil when it is a real orphan folder directly inside DerivedData.
    static func refusal(_ path: String) -> String? {
        let ns = path as NSString
        let name = ns.lastPathComponent
        guard ns.deletingLastPathComponent == base, !name.isEmpty, !name.hasPrefix("."), name != "ModuleCache.noindex" else {
            return "\(path) isn't inside Xcode's DerivedData folder, so it stays."
        }
        // attributesOfItem doesn't follow symlinks, so a link pointing elsewhere is refused here.
        guard (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeDirectory else {
            return "\(name) is no longer a folder, so it stays."
        }
        guard let ws = NSDictionary(contentsOfFile: path + "/info.plist")?["WorkspacePath"] as? String else {
            return "\(name) has no project record, so it stays."
        }
        if FileManager.default.fileExists(atPath: ws) { return "\((ws as NSString).lastPathComponent) exists again, so its build data stays." }
        return nil
    }
}

// MARK: - Shared storage pieces (also used by WorktreeDetailPage and ResourcesPage)

/// Horizontal bar whose segments are drawn to scale against `total`.
struct StorageBar: View {
    let segments: [(Int64, Color)]
    let total: Int64
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let visible = segments.filter { $0.0 > 0 }
            let gap: CGFloat = 4
            let usable = max(0, geo.size.width - gap * CGFloat(max(visible.count - 1, 0)))
            ZStack(alignment: .leading) {
                // A pressed-in track, so free space is visible as an empty slot rather than nothing.
                Capsule().fill(Theme.barTrack.shadow(.inner(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)))
                    .overlay(Capsule().strokeBorder(Theme.border.opacity(0.6), lineWidth: 1))
                HStack(spacing: gap) {
                    ForEach(visible.indices, id: \.self) { i in
                        Capsule().fill(visible[i].1)
                            .frame(width: max(height, usable * CGFloat(visible[i].0) / CGFloat(max(total, 1))))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)   // the caption under each bar carries the numbers
    }
}

/// Inline loading state for a panel.
struct ProgressLine: View {
    var text = "Measuring…"
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }
}
