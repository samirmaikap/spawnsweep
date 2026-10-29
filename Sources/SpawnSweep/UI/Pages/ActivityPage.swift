import SwiftUI

/// Chronological record of cleanups, dry runs and recoveries, each with the ways back it offers.
struct ActivityPage: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all

    private enum Filter: Hashable { case all, cleanups, dryRuns }

    var body: some View {
        let entries = model.activity.filter { e in
            switch filter {
            case .all: return true
            case .cleanups: return e.kind == .cleanup
            case .dryRuns: return e.kind == .dryRun
            }
        }

        PageScroll {
            PageHeader(title: "A record of every little thing.", subtitle: "See what changed, what was kept, and what can be restored.")

            HStack {
                ChipTabs(selection: $filter, options: [(.all, "All activity"), (.cleanups, "Cleanups"), (.dryRuns, "Dry runs")])
                Spacer()
                Chip(text: "Stored on this Mac")
            }

            if entries.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                        entry(e, last: i == entries.count - 1)
                    }
                }
            }

            InfoBanner(text: "File removals can be restored during retention. Stopped processes can be relaunched, but their live state cannot be undone.")
        }
        .onAppear { model.reloadFiles() }
    }

    @ViewBuilder private var emptyState: some View {
        switch filter {
        case .all:
            EmptyState(symbol: "clock.arrow.circlepath", title: "Nothing recorded yet.",
                       message: "Cleanups, dry runs and restores appear here. History stays on this Mac for \(model.prefs.historyDays) days.")
        case .cleanups:
            EmptyState(symbol: "moon", title: "No cleanups yet.",
                       message: "When something is put away, it's recorded here with its way back.")
        case .dryRuns:
            EmptyState(symbol: "sparkles", title: "No dry runs yet.",
                       message: "When an Autopilot rule in dry-run mode matches something, it's recorded here. Nothing changes.")
        }
    }

    private func entry(_ e: ActivityEntry, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: symbol(e), size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.time(e.date)).font(.meta).foregroundStyle(Theme.secondary)
                Text(e.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                if !e.detail.isEmpty {
                    Text(e.detail).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            if !e.recovery.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(e.recovery.enumerated()), id: \.offset) { _, r in
                        Button(r.label) { recover(r, from: e) }.buttonStyle(.quiet)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clay(radius: 20, glass: false)
        .padding(.leading, 30)
        .padding(.bottom, last ? 4 : 16)
        .background(alignment: .topLeading) {
            ZStack(alignment: .top) {
                if !last { Rectangle().fill(Theme.border).frame(width: 1).padding(.top, 8) }
                Circle().fill(Theme.accent.opacity(e.kind == .dryRun ? 0.4 : 0.7)).frame(width: 9, height: 9).padding(.top, 3)
            }
            .frame(width: 9)
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(y: 29)   // dot level with the icon; the line still reaches the next entry's dot
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    /// What the entry is about, read from its way back (or its kind when it has none).
    private func symbol(_ e: ActivityEntry) -> String {
        switch e.recovery.first {
        case .relaunch: return "terminal"
        case .restoreWorktree: return "archivebox"
        case .reinstallDependencies, .startContainers: return "shippingbox"
        case .bootSimulator: return "iphone"
        case .reviewRule: return "sparkles"
        case nil: return e.kind == .dryRun ? "sparkles" : e.kind == .cleanup ? "moon" : "clock"
        }
    }

    // MARK: - Recovery, always through a preview

    private func recover(_ r: Recovery, from e: ActivityEntry) {
        let model = model
        switch r {
        case .reviewRule:
            model.go(.autopilot)
        case .restoreWorktree(let id):
            if let b = model.bin.first(where: { $0.id == id }) {
                model.reviewRestore(b)
            } else {
                model.present(DialogSpec(icon: "archivebox", title: "No longer in the recycle bin.",
                                         subtitle: "This worktree was already restored, or its retention period ended.", confirmTitle: "OK"))
            }
        default:
            var spec = preview(r)
            spec.action = DialogSpec.followUp {
                model.runRecovery(r, from: e)
                model.dismissDialog()
            }
            model.present(spec)
        }
    }

    private func preview(_ r: Recovery) -> DialogSpec {
        func tilde(_ p: String) -> String { (p as NSString).abbreviatingWithTildeInPath }
        switch r {
        case .relaunch(let command, let cwd):
            return DialogSpec(icon: "arrow.clockwise", title: "Relaunch this command?", subtitle: tilde(cwd),
                              notes: ["It runs again in the same folder as a new process. State from the earlier run, such as in-memory data, isn't restored."],
                              confirmTitle: "Relaunch",
                              custom: AnyView(Text(command).font(.mono(12)).foregroundStyle(Theme.text).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))))
        case .reinstallDependencies(let path):
            return DialogSpec(icon: "shippingbox", title: "Reinstall dependencies?", subtitle: tilde(path),
                              notes: ["Runs the project's install command (pnpm, yarn, bun or npm, based on its lockfile) in the background. Source files aren't touched."],
                              confirmTitle: "Reinstall")
        case .bootSimulator(let udid):
            let d = (model.workspace.devices + model.disk.simulatorDevices).first { $0.udid == udid }
            return DialogSpec(icon: "iphone", title: "Boot \(d?.name ?? "this simulator")?", subtitle: d?.runtime ?? udid,
                              notes: ["The simulator starts in the background. Its apps and data are as you left them."],
                              confirmTitle: "Boot simulator")
        case .startContainers(let ids):
            return DialogSpec(icon: "shippingbox", title: "Start the stack again?",
                              subtitle: "\(ids.count) container\(ids.count == 1 ? "" : "s")",
                              notes: ["Docker starts the same containers. Volumes and data are as they were."],
                              confirmTitle: "Start stack")
        case .restoreWorktree, .reviewRule:
            return DialogSpec(title: r.label, subtitle: "", confirmTitle: r.label)   // handled in recover(_:from:)
        }
    }
}
