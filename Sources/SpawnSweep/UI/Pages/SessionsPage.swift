import SwiftUI

/// Workspace overview: the cleanup opportunity first, then every agent session on this Mac.
struct SessionsPage: View {
    @Environment(AppModel.self) private var model
    @State private var filter = Filter.all

    private enum Filter: Hashable { case all, attention }

    var body: some View {
        PageScroll {
            PageHeader(title: "A little room to breathe.", subtitle: "Everything your agents left running. Beautifully in order.")
            if model.workspace.scannedAt == .distantPast {
                skeleton
            } else {
                hero
                stats
                sessionList
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        let attention = model.attentionSessions
        let running = attention.reduce(0) { $0 + $1.resources.count }
        let ws = model.workspace
        // Same count as the menu bar: everything running, whether a session owns it or not.
        let elsewhere = ws.allResources.count - running, loose = ws.unattached.count
        let storage = attention.isEmpty && model.reclaimableDisk >= 1_000_000_000
        let title = !attention.isEmpty ? "A clean finish.\nA fresh start."
            : elsewhere > 0 ? "Nothing to put away." : storage ? "Nothing left running." : "All quiet."
        return HeroCard {
            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).heading(26)
                    VStack(alignment: .leading, spacing: 6) {
                        if !attention.isEmpty {
                            Text(Self.counted(attention.count, "finished session") + ". " + Self.counted(running, "running resource") + ".")
                            Text("Put them to rest. Keep every line of work.")
                        } else if elsewhere > 0 {
                            Text(Self.runningLine(total: elsewhere, loose: loose))
                            if storage { Text(Self.diskLine(model.reclaimableDisk)) }
                        } else if storage {
                            Text(Self.diskLine(model.reclaimableDisk))
                        } else {
                            Text("Every session is active, pinned, or already put away.")
                        }
                    }
                    .font(.system(size: 14))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 18)
                    if !attention.isEmpty {
                        heroButton("Review cleanup") { model.reviewSweep() }
                    } else if loose > 0 {
                        heroButton("Review what's running") { model.go(ws.unattached.contains { !$0.ports.isEmpty } ? .ports : .resources) }
                    } else if storage {
                        heroButton("Review storage") { model.go(.storage) }
                    }
                }
                Spacer(minLength: 0)
                Moon(size: 130).frame(width: 190, height: 150)
            }
        }
    }

    /// "5 things running: 1 in active or pinned sessions, 4 not tied to an agent session." Split into typed steps:
    /// as one expression it took CI's compiler too long to type-check.
    static func runningLine(total: Int, loose: Int) -> String {
        var parts: [String] = []
        let inSessions: Int = total - loose
        if inSessions > 0 { parts.append("\(inSessions) in active or pinned sessions") }
        if loose > 0 { parts.append("\(loose) not tied to an agent session") }
        let head: String = counted(total, "thing")
        return head + " running: " + parts.joined(separator: ", ") + "."
    }

    /// What `reclaimableDisk` adds up: rebuildable worktree folders, orphaned Xcode build data and month-old simulators.
    static func diskLine(_ bytes: Int64) -> String {
        "\(Fmt.bytes(bytes)) of dependency folders, old build data and unused simulators can go without touching code."
    }

    private func heroButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
            }
        }
        .buttonStyle(.primaryLarge)
        .padding(.top, 26)
    }

    // MARK: Stat strip

    private var stats: some View {
        // The first two are exactly what "Review cleanup" stops: finished sessions' leftovers, not everything running.
        statStrip(StatBlock(value: Fmt.bytes(model.memoryToFree), label: "Memory a cleanup frees"),
                  StatBlock(value: String(model.sweepResources.count), label: "Left by finished sessions"),
                  // A rescan keeps the last measured number on screen; "…" only before anything was ever measured.
                  StatBlock(value: model.diskUpdatedAt == nil ? "…" : Fmt.bytes(model.reclaimableDisk), label: "Recoverable on disk"))
    }

    private func statStrip<A: View, B: View, C: View>(_ a: A, _ b: B, _ c: C) -> some View {
        HStack(spacing: 16) {
            SessionStatTile(symbol: "memorychip", tone: .lilac) { a }
            SessionStatTile(symbol: "stop.circle", tone: .peach) { b }
            SessionStatTile(symbol: "internaldrive", tone: .sand) { c }
        }
    }

    // MARK: First scan

    /// The page's real layout in placeholder form, so nothing jumps when the first scan lands. No looping animation (§9).
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 28) {
            HeroCard {
                HStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 10) {
                        heroBar(250, 26)
                        heroBar(190, 26)
                        heroBar(320, 13).padding(.top, 14)
                    }
                    Spacer(minLength: 0)
                    Moon(size: 130).frame(width: 190, height: 150)
                }
            }
            statStrip(statPlaceholder, statPlaceholder, statPlaceholder)
            Panel(title: "Sessions") { SkeletonRows(count: 3) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checking what your agents left running")
    }

    // ponytail: SkeletonBlock's tint fill vanishes on the hero gradient; a faint text tint reads in light and dark.
    private func heroBar(_ width: CGFloat, _ height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.text.opacity(0.08)).frame(width: width, height: height)
    }

    private var statPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(width: 96, height: 28)
            SkeletonBlock(width: 120, height: 11)
        }
        .padding(.vertical, 4)
    }

    // MARK: Session list

    private var sessionList: some View {
        // ponytail: attention first, otherwise scanner order.
        let all = model.workspace.sessions.sorted { $0.needsAttention && !$1.needsAttention }
        let shown = filter == .all ? all : all.filter(\.needsAttention)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 0) {
                    Text("Sessions").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                    Text(" · " + String(all.count) + " with something running").font(.system(size: 15)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                ChipTabs(selection: $filter, options: [(.all, "All"), (.attention, "Needs attention")])
            }
            if all.isEmpty {
                EmptyState(symbol: "moon", title: "No agent session has anything running.",
                           message: "When an agent starts a server, watcher, simulator or Docker stack, it shows up here with its session.")
            } else if shown.isEmpty {
                EmptyState(symbol: "checkmark", title: "Nothing needs attention.", message: "Every session is active, pinned, or already put away.")
            } else {
                VStack(spacing: 14) {
                    ForEach(shown) { SessionCard(session: $0) }
                }
            }
        }
    }

    private static func counted(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
}

extension Session {
    /// "Claude Code · feature/email-flow"
    var agentAndBranch: String { [agent.rawValue, branch].compactMap { $0 }.joined(separator: " · ") }
}

/// One number in its own clay tile, a clay icon above it. Shared by the sessions overview and session detail.
struct SessionStatTile<Content: View>: View {
    let symbol: String
    let tone: ClayTone
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IconTile(symbol: symbol, size: 44, tone: tone)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clay(radius: 22, glass: false)
    }
}

/// One session on a clay card. Sessions that need attention are raised; active and pinned ones sit flat.
private struct SessionCard: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        let raised = session.needsAttention
        let amber = raised && session.state.isEnded
        HStack(spacing: 18) {
            IconTile(symbol: session.agent.symbol, size: 52,
                     tint: amber ? Theme.amberFill : Theme.tint, fg: amber ? Theme.amberText : Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(session.project).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                    session.badge
                }
                Text(session.agentAndBranch).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                if !summary.isEmpty {
                    Text(summary).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
                NavLink(title: "View session") { model.openSession(session.folder) }
                    .padding(.top, 8)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 4) {
                if !session.resources.isEmpty {
                    Text(Fmt.bytes(session.memoryBytes)).font(.system(size: 15)).monospacedDigit().foregroundStyle(Theme.text)
                }
                if !caption.isEmpty {
                    Text(caption).font(.meta).monospacedDigit().foregroundStyle(Theme.secondary)
                }
            }
            trailing
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .clay(radius: 22, glass: false, raised: raised)
    }

    @ViewBuilder private var trailing: some View {
        if session.pinned {
            Button { model.togglePin(session.folder) } label: {
                Image(systemName: "pin").font(.system(size: 15)).foregroundStyle(Theme.secondary)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Unpin session")
            .accessibilityLabel("Unpin \(session.project)")
        } else if session.state.isActive {
            Image(systemName: "lock").font(.system(size: 15)).foregroundStyle(Theme.secondary)
                .frame(width: 28, height: 28)
                .help("Active sessions stay out of sweeps")
                .accessibilityLabel("Protected while active")
        } else if !session.resources.isEmpty {
            Button("Review") { model.reviewClose(session) }.buttonStyle(.quiet)
        }
    }

    /// "Next.js :3000 · Supabase local stack · 1 watcher"
    private var summary: String {
        var parts: [String] = []
        var watchers = 0, browsers = 0
        for r in session.resources {
            switch r.kind {
            case .watcher: watchers += 1
            case .browser: browsers += 1
            default: parts.append(r.title)
            }
        }
        if watchers > 0 { parts.append("\(watchers) watcher\(watchers == 1 ? "" : "s")") }
        if browsers > 0 { parts.append("\(browsers) browser\(browsers == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private var caption: String {
        if session.pinned { return "Keep alive" }
        if session.state.isActive { return session.startedAt.map { "Started " + Fmt.ago($0) } ?? "Working now" }
        if let start = session.resources.compactMap(\.startedAt).min() {
            return "Running for " + Fmt.duration(Date().timeIntervalSince(start))
        }
        if case .ended(let since?) = session.state { return "Ended " + Fmt.ago(since) }
        return ""
    }
}
