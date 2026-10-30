import SwiftUI

/// Public tunnels, environment-file locations (never contents), and what's protected.
struct SafetyPage: View {
    @Environment(AppModel.self) private var model
    private let grid = [GridItem(.adaptive(minimum: 236, maximum: 420), spacing: 16, alignment: .top)]

    var body: some View {
        let tunnels = model.workspace.tunnels
        let env = model.disk.envCopies
        let copies = env.reduce(0) { $0 + $1.files.count }
        let worktrees = env.reduce(0) { $0 + $1.worktrees }
        let folders = model.prefs.pinnedFolders
        let ports = model.prefs.protectedPorts.sorted()

        PageScroll {
            PageHeader(title: "Nothing left exposed.", subtitle: "A clear view of public tunnels and environment-file copies.")

            if !tunnels.isEmpty {
                WarningBanner(text: "\(tunnels.count) public tunnel\(tunnels.count == 1 ? " is" : "s are") still exposing a development server.")
            }

            Panel(title: "Public tunnels") {
                if tunnels.isEmpty {
                    EmptyState(symbol: "antenna.radiowaves.left.and.right", title: "No public tunnels.",
                               message: "Nothing on this Mac is shared through ngrok, cloudflared or a similar tool right now.")
                } else {
                    RowList(items: tunnels) { t in
                        ResourceRow(symbol: "antenna.radiowaves.left.and.right",
                                    title: "\(t.tool) → " + (t.targetPort.map { "localhost:\($0)" } ?? "unknown port"),
                                    subtitle: context(t)) {
                            Badge(text: "Public", style: .warning)
                            Button("Review") { model.reviewStop(t.resource) }.buttonStyle(.quiet)
                                .accessibilityLabel("Review \(t.tool) tunnel")
                        }
                    }
                }
            }

            Panel(title: "Environment copies") {
                if env.isEmpty {
                    if model.disk.scannedAt == nil {
                        EmptyState(symbol: "magnifyingglass", title: "Looking through worktrees…",
                                   message: "Environment-file copies appear here when the storage scan finishes.")
                    } else {
                        EmptyState(symbol: "lock.doc", title: "No environment copies.",
                                   message: "No worktree in your development folders has its own .env file.")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(copies) cop\(copies == 1 ? "y" : "ies")")
                                    .font(.system(size: 30)).tracking(-0.6).monospacedDigit().foregroundStyle(Theme.text)
                                Text("Across \(worktrees) worktree\(worktrees == 1 ? "" : "s") in \(env.count) project\(env.count == 1 ? "" : "s").")
                                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Button("Review copies") {
                                showFiles(env.flatMap(\.files), worktrees: worktrees, project: nil)
                            }
                            .buttonStyle(.quiet)
                        }
                        LazyVGrid(columns: grid, alignment: .leading, spacing: 16) {
                            ForEach(Array(env.enumerated()), id: \.offset) { _, g in
                                ResourceRow(symbol: "lock.doc", title: g.repo,
                                            subtitle: "\(g.files.count) cop\(g.files.count == 1 ? "y" : "ies") · \(g.worktrees) worktree\(g.worktrees == 1 ? "" : "s")") {
                                    Button("View") { showFiles(g.files, worktrees: g.worktrees, project: g.repo) }
                                        .buttonStyle(.quiet)
                                        .accessibilityLabel("View \(g.repo) environment copies")
                                }
                            }
                        }
                        .environment(\.rowLayout, .tile)
                    }
                }
            }

            InfoBanner(text: "Only file locations and counts appear here. Secret values are never shown.")

            Panel(title: "Protected resources") {
                if folders.isEmpty && ports.isEmpty {
                    EmptyState(symbol: "pin", title: "Nothing is protected.",
                               message: "Pin a session from its detail view, or protect a port from the Ports board.")
                } else {
                    LazyVGrid(columns: grid, alignment: .leading, spacing: 16) {
                        ForEach(folders, id: \.self) { f in
                            ResourceRow(symbol: "pin", title: folderTitle(f),
                                        subtitle: "Pinned session · " + (f as NSString).abbreviatingWithTildeInPath) { kept }
                        }
                        ForEach(ports, id: \.self) { p in
                            ResourceRow(symbol: "lock", title: "localhost:\(p)", subtitle: portContext(p)) { kept }
                        }
                    }
                    .environment(\.rowLayout, .tile)
                }
            }
        }
    }

    private var kept: some View {
        HStack(spacing: 14) {
            Badge(text: "Always kept", style: .success)
            Button("Manage") { manage() }.buttonStyle(.quiet).accessibilityLabel("Manage protected resources")
        }
    }

    // MARK: - Row text

    private func context(_ t: Tunnel) -> String {
        guard let s = model.workspace.session(for: t.resource) else {
            return "Not linked to an agent session" + (t.resource.startedAt.map { " · running \(Fmt.duration(Date().timeIntervalSince($0)))" } ?? "")
        }
        switch s.state {
        case .active: return "\(s.project) · session active"
        case .idle(let since): return "\(s.project) · session idle \(Fmt.duration(Date().timeIntervalSince(since)))"
        case .ended(let since): return "\(s.project) · session ended" + (since.map { " \(Fmt.ago($0))" } ?? "")
        }
    }

    private func folderTitle(_ folder: String) -> String {
        if let s = model.workspace.sessions.first(where: { $0.folder.hasPrefix(folder) }) {
            return s.project + (s.branch.map { " / \($0)" } ?? "")
        }
        return (folder as NSString).lastPathComponent
    }

    private func portContext(_ port: Int) -> String {
        guard let r = model.workspace.portResources.first(where: { $0.ports.contains(port) }) else {
            return "Protected port · nothing is listening right now"
        }
        return "Protected port · \(r.title)" + (model.workspace.session(for: r).map { " · \($0.project)" } ?? "")
    }

    // MARK: - Dialogs

    /// Lists file paths only. Contents are never read; the date comes from file attributes.
    private func showFiles(_ files: [String], worktrees: Int, project: String?) {
        let n = files.count
        let counts = "\(n) cop\(n == 1 ? "y" : "ies") across \(worktrees) worktree\(worktrees == 1 ? "" : "s")"
        model.present(DialogSpec(icon: "lock.doc", title: "Environment copies, in view.",
                                 subtitle: (project.map { "\($0) · " } ?? "") + counts + ". Values stay private.",
                                 notes: ["Environment files stay in place when a worktree is slimmed, and are saved with it when it moves to the recycle bin."],
                                 confirmTitle: "Done",
                                 custom: AnyView(EnvFileList(paths: files.sorted()))))
    }

    private func manage() {
        let model = model
        let draft = ProtectDraft(folders: Set(model.prefs.pinnedFolders), ports: Set(model.prefs.protectedPorts))
        var spec = DialogSpec(icon: "pin", title: "Always keep these running.",
                              subtitle: "Pinned sessions stay out of sweeps and Autopilot cleanup. Protected ports are kept when a Claude Code session ends.",
                              confirmTitle: "Save protected list",
                              custom: AnyView(ProtectList(draft: draft, folders: model.prefs.pinnedFolders,
                                                          ports: model.prefs.protectedPorts.sorted(), title: folderTitle)))
        spec.action = DialogSpec.followUp {
            var p = model.prefs
            p.pinnedFolders.removeAll { !draft.folders.contains($0) }
            p.protectedPorts.removeAll { !draft.ports.contains($0) }
            model.prefs = p
            model.refresh()
            model.dismissDialog()
        }
        model.present(spec)
    }
}

// MARK: - Dialog bodies

private struct EnvFileList: View {
    let paths: [String]

    var body: some View {
        if paths.count > 4 {
            ScrollView { list }.frame(height: 280)
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(paths.enumerated()), id: \.offset) { i, p in
                if i > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                HStack(spacing: 12) {
                    IconTile(symbol: "lock.doc", size: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text((p as NSString).lastPathComponent).font(.mono(13)).foregroundStyle(Theme.text)
                        Text(((p as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                            .font(.mono(11)).foregroundStyle(Theme.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 12)
                    if let d = (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date {
                        Text(Fmt.ago(d)).font(.meta).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.vertical, 10)
                .textSelection(.enabled)
            }
        }
    }
}

@MainActor @Observable
private final class ProtectDraft {
    var folders: Set<String>
    var ports: Set<Int>
    init(folders: Set<String>, ports: Set<Int>) { self.folders = folders; self.ports = ports }
}

private struct ProtectList: View {
    @Bindable var draft: ProtectDraft
    let folders: [String]
    let ports: [Int]
    let title: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(folders, id: \.self) { f in
                check(title(f), "Session", on: draft.folders.contains(f)) {
                    if draft.folders.contains(f) { draft.folders.remove(f) } else { draft.folders.insert(f) }
                }
            }
            ForEach(ports, id: \.self) { p in
                check("localhost:\(p)", "Port", on: draft.ports.contains(p)) {
                    if draft.ports.contains(p) { draft.ports.remove(p) } else { draft.ports.insert(p) }
                }
            }
            Text("Pin more from a session's detail view, or protect a port from the Ports board.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                .padding(.top, 16)
        }
    }

    private func check(_ label: String, _ detail: String, on: Bool, toggle: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18)).foregroundStyle(on ? Theme.accent : Theme.secondary)
                    Text(label).font(.system(size: 14)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(detail).font(.meta).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(on ? "Kept" : "Not kept")
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}
