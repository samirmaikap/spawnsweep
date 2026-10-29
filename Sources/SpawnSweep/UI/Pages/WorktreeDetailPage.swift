import SwiftUI
import AppKit

/// One repository's worktrees as cards: status, size, what it's made of, and the one safe next step.
struct WorktreeDetailPage: View {
    let repoPath: String
    @Environment(AppModel.self) private var model
    @State private var sort: Sort = .size

    private enum Sort: String, CaseIterable { case size = "Size", used = "Last used", name = "Name" }

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 18, alignment: .top)]

    var body: some View {
        let repo = model.disk.repos.first { $0.path == repoPath }
        PageScroll {
            header(repo)
            if let repo {
                summary(repo)
                toolbar(repo)
                grid(repo)
                InfoBanner(text: "Local changes are preserved. Unmerged branches need a verified push before removal.")
            } else {
                Panel {
                    if model.disk.inProgress || model.diskScanning { SkeletonRows() }
                    else {
                        EmptyState(symbol: "arrow.triangle.branch", title: "No worktrees here anymore",
                                   message: "This repository has no extra worktrees in the latest scan.")
                    }
                }
            }
        }
    }

    // MARK: - Header

    private func header(_ repo: RepoGroup?) -> some View {
        let name = repo?.name ?? (repoPath as NSString).lastPathComponent
        var parts: [String] = []
        if let repo {
            parts.append("\(repo.worktrees.count) worktree\(repo.worktrees.count == 1 ? "" : "s")")
            if repo.totalBytes > 0 { parts.append("\(Fmt.bytes(repo.totalBytes)) on disk") }
        }
        parts.append((repoPath as NSString).abbreviatingWithTildeInPath)
        return VStack(alignment: .leading, spacing: 0) {
            BackLink(title: "Storage") { model.repoDetail = nil }
            .padding(.bottom, 16)
            HStack(spacing: 20) {
                IconTile(symbol: "folder.fill", size: 64, tone: .sand)
                VStack(alignment: .leading, spacing: 0) {
                    Text("REPOSITORY").font(.system(size: 11, weight: .semibold)).tracking(1.8)
                        .foregroundStyle(ClayTone.sand.glyph).padding(.bottom, 6)
                    Text(name).heading(30)
                    Text(parts.joined(separator: " · ")).font(.system(size: 14)).monospacedDigit().foregroundStyle(Theme.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.top, 6)
                }
            }
        }
    }

    // MARK: - Summary: what can go, and one place to act on all of it

    private func summary(_ repo: RepoGroup) -> some View {
        let ws = repo.worktrees
        let deps = repo.slimBytes, total = repo.totalBytes
        let ready = ws.filter { Actions.canRecycle($0) == nil }
        let readyBytes = ready.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        let blocked = ws.filter { w in
            switch w.status { case .unpushed, .uncommitted: return true; default: return false }
        }
        return HeroCard(padding: 26) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 0) {
                    stat(Fmt.bytes(deps), "dependencies you can reinstall")
                    divider
                    stat("\(ready.count)", ready.isEmpty ? "ready for the recycle bin" : "ready for the recycle bin · \(Fmt.bytes(readyBytes))")
                    divider
                    stat("\(blocked.count)", "have unpushed or uncommitted work")
                }
                if total > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        StorageBar(segments: [(deps, Theme.accent)], total: total)
                        HStack {
                            let pct = Int((Double(deps) / Double(total) * 100).rounded())
                            Text("\(pct)% dependencies · \(100 - pct)% code, local changes, and other files")
                                .font(.system(size: 13)).foregroundStyle(Theme.secondary).monospacedDigit()
                            Spacer(minLength: 16)
                            BulkWorktreeActions(worktrees: ws)
                        }
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 26)).tracking(-0.5).monospacedDigit().foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 52).padding(.horizontal, 20)
    }

    // MARK: - Filter and sort

    private func toolbar(_ repo: RepoGroup) -> some View {
        let counts = Dictionary(WorktreeFilter.allCases.map { f in (f, repo.worktrees.filter { f.matches($0.status) }.count) },
                                uniquingKeysWith: { a, _ in a })
        return HStack(spacing: 12) {
            ChipTabs(selection: Binding(get: { activeFilter(repo) }, set: { model.worktreeFilter = $0 }),
                     options: WorktreeFilter.allCases.compactMap { f in
                         let n = counts[f] ?? 0
                         return f == .all || n > 0 ? (f, "\(f.title) \(n)") : nil
                     })
                .monospacedDigit()
            Spacer(minLength: 12)
            ClayPicker(title: "Sort worktrees", selection: $sort, options: Sort.allCases.map { ($0, "Sort: " + $0.rawValue) })
        }
    }

    /// The shared filter, or All when nothing in this repo matches it.
    private func activeFilter(_ repo: RepoGroup) -> WorktreeFilter {
        let f = model.worktreeFilter
        return f == .all || repo.worktrees.contains { f.matches($0.status) } ? f : .all
    }

    private func sorted(_ ws: [Worktree]) -> [Worktree] {
        switch sort {
        case .size: return ws.sorted { ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1) }
        case .used: return ws.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        case .name: return ws.sorted { ($0.branch ?? $0.head).localizedStandardCompare($1.branch ?? $1.head) == .orderedAscending }
        }
    }

    // MARK: - Cards

    private func grid(_ repo: RepoGroup) -> some View {
        let f = activeFilter(repo)
        let list = sorted(repo.worktrees.filter { f.matches($0.status) })
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(list) { WorktreeCard(worktree: $0) }
        }
        .animation(.easeOut(duration: 0.2), value: list.map(\.id))
    }
}

/// A worktree as a card: status first, then the branch, its size and makeup, and the one safe action.
struct WorktreeCard: View {
    let worktree: Worktree
    @Environment(AppModel.self) private var model
    @State private var hover = false

    var body: some View {
        let w = worktree
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                IconTile(symbol: "arrow.triangle.branch", size: 46, tone: tone(w.status))
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    status(w)
                    if let agent = w.agent {
                        Label(w.mayBeClaudeManaged ? "Claude" : agent.rawValue, systemImage: agent.symbol)
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }

            Text(w.branch ?? "Detached at \(w.head.prefix(7))")
                .font(w.branch == nil ? .mono(14) : .system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(2).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .topLeading)
                .padding(.top, 14)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(w.sizeBytes.map(Fmt.bytes) ?? "Measuring…")
                    .font(.system(size: 24)).tracking(-0.5).monospacedDigit().foregroundStyle(Theme.text)
                if w.sizeBytes != nil { Text("on disk").font(.meta).foregroundStyle(Theme.secondary) }
            }
            .padding(.top, 10)

            makeup(w).padding(.top, 10)

            Text(meta(w)).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
                .padding(.top, 12)

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                primaryAction(w)
                Spacer(minLength: 8)
                Menu {
                    menu(w)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for \(w.branch ?? "this worktree")")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clay(radius: 22, glass: false)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Theme.accent.opacity(hover ? 0.45 : 0)))
        .scaleEffect(hover ? 1.01 : 1)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(w.path)
        .contextMenu { menu(w) }
    }

    private func tone(_ s: WorktreeStatus) -> ClayTone {
        switch s {
        case .merged: return .mint
        case .inUse: return .sky
        case .uncommitted, .unpushed: return .peach
        case .pushedNotMerged: return .sand
        case .unknown: return .sage
        }
    }

    @ViewBuilder private func status(_ w: Worktree) -> some View {
        switch w.status {
        case .merged: Badge(text: "Merged", style: .success, symbol: "checkmark")
        case .pushedNotMerged: Badge(text: "Pushed · not merged", symbol: "arrow.up")
        case .unpushed(let n): Badge(text: "\(n) unpushed commit\(n == 1 ? "" : "s")", style: .warning)
        case .uncommitted(let n): Badge(text: "\(n) uncommitted file\(n == 1 ? "" : "s")", style: .warning)
        case .inUse: Badge(text: "In use", style: .active)
        case .unknown: Badge(text: "Checking…")
        }
    }

    /// Dependencies vs everything else, drawn to scale.
    @ViewBuilder private func makeup(_ w: Worktree) -> some View {
        if let total = w.sizeBytes, total > 0 {
            let deps = min(w.slimBytes ?? 0, total)
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.tint)
                        Capsule().fill(Theme.accent).frame(width: max(deps > 0 ? 4 : 0, g.size.width * CGFloat(deps) / CGFloat(total)))
                    }
                }
                .frame(height: 6)
                Text(deps > 0 ? "\(Fmt.bytes(deps)) dependencies · \(Fmt.bytes(total - deps)) code & other"
                              : "No dependencies to slim")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).monospacedDigit()
            }
        } else {
            SkeletonBlock(height: 6)
        }
    }

    private func meta(_ w: Worktree) -> String {
        var parts: [String] = []
        if let used = w.lastUsed { parts.append("Used " + (Calendar.current.isDateInToday(used) ? "today" : Fmt.ago(used))) }
        if !w.envFiles.isEmpty { parts.append("\(w.envFiles.count) .env file\(w.envFiles.count == 1 ? "" : "s")") }
        if w.mayBeClaudeManaged && w.status != .merged && w.status != .inUse { parts.append("slim until merged") }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    private func canSlim(_ w: Worktree) -> Bool { w.status != .inUse && (w.slimBytes ?? 0) > 0 }

    /// Mirrors what Actions.pushAndRecycle accepts, so the button never leads to a guaranteed refusal.
    private func canPush(_ w: Worktree) -> Bool {
        guard case .unpushed = w.status, !w.mayBeClaudeManaged, let b = w.branch else { return false }
        let defaultName = w.defaultBranch?.split(separator: "/").last.map(String.init)
        return b != defaultName && !["main", "master"].contains(b)
    }

    /// One action per card: removal when it's safe, push first when it isn't pushed, otherwise slim.
    @ViewBuilder private func primaryAction(_ w: Worktree) -> some View {
        if w.status == .inUse {
            Label("Something is running here", systemImage: "lock").font(.system(size: 12)).foregroundStyle(Theme.secondary)
        } else if Actions.canRecycle(w) == nil {
            Button("Review removal") { model.reviewRecycle(w) }.buttonStyle(.quiet)
        } else if canPush(w) {
            Button("Push & remove") { model.reviewPushRemove(w) }.buttonStyle(.quiet)
        } else if canSlim(w) {
            Button("Slim · \(Fmt.bytes(w.slimBytes ?? 0))") { model.reviewSlim(w) }.buttonStyle(.quiet)
        } else {
            Text("Nothing to clean").font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder private func menu(_ w: Worktree) -> some View {
        if canSlim(w) { Button("Slim Worktree…") { model.reviewSlim(w) } }
        if Actions.canRecycle(w) == nil { Button("Move to Recycle Bin…") { model.reviewRecycle(w) } }
        if canPush(w) { Button("Push & Remove…") { model.reviewPushRemove(w) } }
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: w.path)]) }
        Button("Open in Terminal") {
            NSWorkspace.shared.open([URL(fileURLWithPath: w.path)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                    configuration: NSWorkspace.OpenConfiguration())
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(w.path, forType: .string)
        }
    }
}

/// Bulk actions for a set of worktrees: one preview each, every item re-checked when it runs.
struct BulkWorktreeActions: View {
    let worktrees: [Worktree]
    @Environment(AppModel.self) private var model

    var body: some View {
        let slim = worktrees.filter { $0.status != .inUse && ($0.slimBytes ?? 0) > 0 }
        let slimBytes = slim.reduce(Int64(0)) { $0 + ($1.slimBytes ?? 0) }
        let recycle = worktrees.filter { Actions.canRecycle($0) == nil }
        // Pushed-but-unmerged worktrees are eligible too; only say "merged" when it's true.
        let recycleTitle = recycle.allSatisfy { $0.status == .merged } ? "Recycle \(recycle.count) merged" : "Recycle \(recycle.count)"
        HStack(spacing: 8) {
            if !recycle.isEmpty {
                Button(recycleTitle) { model.reviewBulkRecycle(worktrees) }.buttonStyle(.quiet)
            }
            if !slim.isEmpty {
                Button("Slim \(slim.count) · \(Fmt.bytes(slimBytes))") { model.reviewBulkSlim(worktrees) }.buttonStyle(.primary)
            }
        }
        .monospacedDigit()
    }
}
