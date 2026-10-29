import SwiftUI
import AppKit

/// One session: what it started, where its code lives, and how to put it away.
struct SessionDetailPage: View {
    @Environment(AppModel.self) private var model
    let folder: String
    @State private var uncommitted = 0
    @State private var prMessage: String?

    private static let hasGH = Shell.which("gh") != nil

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 18) {
                Text("WORKSPACE OVERVIEW").font(.system(size: 11)).tracking(2.2).foregroundStyle(Theme.secondary)
                Button { model.sessionDetail = nil } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("All sessions")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
            }
            if let s = model.session(folder) {
                content(s)
            } else {
                EmptyState(symbol: "moon", title: "This session is put away.", message: "Nothing it started is running anymore.")
            }
        }
        .task(id: folder) {
            let folder = folder
            uncommitted = await Task.detached {
                let r = Shell.run("git", ["-C", folder, "status", "--porcelain"], timeout: 10)
                return r.ok ? r.out.split(separator: "\n").count : 0
            }.value
        }
    }

    @ViewBuilder private func content(_ s: Session) -> some View {
        let kept = s.pinned || s.state.isActive

        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                if !kept { IconTile(symbol: s.agent.symbol, size: 56) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.project).heading(30)
                    Text(s.agentAndBranch).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                }
            }
            HStack {
                stateBadge(s)
                Spacer()
                Button(s.pinned ? "Unpin session" : "Pin session") { model.togglePin(s.folder) }.buttonStyle(.quiet)
            }
        }

        if !kept {
            HStack(alignment: .top, spacing: 16) {
                SessionStatTile(symbol: "memorychip", tone: .lilac) {
                    StatBlock(value: Fmt.bytes(s.memoryBytes), label: "Memory in use")
                }
                SessionStatTile(symbol: "square.stack.3d.up", tone: .sky) {
                    StatBlock(value: String(s.resources.count), label: s.resources.count == 1 ? "Resource running" : "Resources running")
                }
                if let start = s.resources.compactMap(\.startedAt).min() {
                    SessionStatTile(symbol: "clock", tone: .mint) {
                        StatBlock(value: Fmt.duration(Date().timeIntervalSince(start)), label: "Running for")
                    }
                }
            }
        }

        Panel(title: kept ? "Running resources" : "Started by this session") {
            if s.resources.isEmpty {
                EmptyState(symbol: "checkmark", title: "Nothing running.", message: "This session has no servers, stacks, or devices left.")
            } else {
                RowList(items: s.resources) { r in
                    ResourceRow(symbol: r.kind.symbol, title: r.title,
                                subtitle: r.link == .weak ? r.detail + " · linked by name or timing" : r.detail,
                                value: Fmt.bytes(r.memoryBytes)) {
                        if kept || r.ports.contains(where: model.isProtected(port:)) {
                            Badge(text: "Protected", style: .success)
                        } else {
                            Button(Self.stopLabel(r)) { model.reviewStop(r) }.buttonStyle(.quiet)
                        }
                    }
                }
            }
        }

        if s.pinned {
            InfoBanner(text: "This session is pinned. Sweeps and autopilot will leave it running.")
        } else if s.state.isActive {
            InfoBanner(text: "This agent is actively working. End-of-day sweeps will leave it running.")
        }

        Panel(title: s.isWorktree ? "Worktree" : "Jump to source", boxed: true) {
            if s.isWorktree {
                Text((s.folder as NSString).abbreviatingWithTildeInPath)
                    .font(.mono(13)).foregroundStyle(Theme.secondary).textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Button("Editor") { Self.openInEditor(s.folder, agent: s.agent) }
                Button("Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: s.folder)) }
                Button("Terminal") { _ = Self.open(s.folder, with: "com.apple.Terminal") }
                if s.isWorktree, Self.hasGH {
                    Button("Pull request") { openPullRequest(s.folder) }
                }
            }
            .buttonStyle(.quiet)
            .padding(.top, 4)
            if let prMessage {
                Text(prMessage).font(.meta).foregroundStyle(Theme.secondary)
            }
        }

        if !kept {
            if uncommitted > 0 {
                InfoBanner(text: "Uncommitted changes in \(uncommitted) file\(uncommitted == 1 ? "" : "s"). They stay in place when you close the session.")
            }
            HStack(spacing: 12) {
                if !s.resources.isEmpty {
                    Button("Review close session") { model.reviewClose(s) }.buttonStyle(.primaryLarge)
                }
                if let w = worktree(for: s), w.slimBytes != 0 {
                    Button { model.reviewSlim(w) } label: {
                        Text("Slim worktree").font(.system(size: 15)).padding(.horizontal, 6).padding(.vertical, 5)
                    }
                    .buttonStyle(.quiet)
                }
            }
        }
    }

    private func stateBadge(_ s: Session) -> Badge {
        if s.pinned { return Badge(text: "Pinned · always kept", style: .success) }
        let tone: Badge.Style = s.resources.isEmpty ? .neutral : .ended
        switch s.state {
        case .active: return Badge(text: "Active · working now", style: .success)
        case .idle(let since): return Badge(text: "Idle for " + Fmt.duration(Date().timeIntervalSince(since)), style: tone)
        case .ended(let since): return Badge(text: since.map { "Session ended " + Fmt.ago($0) } ?? "Session ended", style: tone)
        }
    }

    private func worktree(for s: Session) -> Worktree? {
        let path = (s.folder as NSString).standardizingPath
        return model.disk.worktrees.first { ($0.path as NSString).standardizingPath == path }
    }

    private func openPullRequest(_ folder: String) {
        prMessage = nil
        Task {
            let r = await Task.detached { Shell.run("gh", ["pr", "view", "--web"], cwd: folder, timeout: 20) }.value
            if !r.ok {
                let why = r.err.split(separator: "\n").first.map(String.init) ?? ""
                prMessage = why.isEmpty ? "No pull request found for this branch." : "Couldn’t open a pull request: " + why
            }
        }
    }

    static func stopLabel(_ r: Resource) -> String {
        switch r.kind {
        case .server where !r.ports.isEmpty: return "Free port"
        case .stack: return "Stop stack"
        case .simulator, .emulator: return "Shut down"
        default: return "Stop"
        }
    }

    @discardableResult
    private static func open(_ folder: String, with bundleID: String) -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    /// VS Code (Cursor first for Cursor sessions), falling back to Finder.
    private static func openInEditor(_ folder: String, agent: Agent) {
        let cursor = "com.todesktop.230313mxl4ozz", vscode = "com.microsoft.VSCode"
        let ids = agent == .cursor ? [cursor, vscode] : [vscode, cursor]
        if !ids.contains(where: { open(folder, with: $0) }) { NSWorkspace.shared.open(URL(fileURLWithPath: folder)) }
    }
}
