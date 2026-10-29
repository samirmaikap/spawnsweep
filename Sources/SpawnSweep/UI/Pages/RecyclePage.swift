import SwiftUI

struct RecyclePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = model.prefs.retentionDays
        PageScroll {
            PageHeader(title: "A second chance for your work.",
                       subtitle: "Worktrees wait here for \(days) day\(days == 1 ? "" : "s") before they leave for good.")
            VStack(alignment: .leading, spacing: 16) {
                InfoBanner(text: "Restore returns a worktree to its recorded commit and puts its saved .env files back.")
                Panel(title: "Recently removed") {
                    if model.bin.isEmpty {
                        EmptyState(symbol: "archivebox", title: "Nothing in the recycle bin",
                                   message: "Worktrees you remove wait here for \(days) day\(days == 1 ? "" : "s"), ready to restore.")
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            RowList(items: model.bin) { e in
                                BinRow(entry: e, retentionDays: days) { model.reviewRestore(e) }
                            }
                            InfoBanner(text: "Saved with each worktree: branch, commit, .env files and other ignored files that can't be rebuilt.", symbol: "archivebox")
                        }
                    }
                }
                Panel(title: "Retention", boxed: true) {
                    HStack(spacing: 16) {
                        IconTile(symbol: "hourglass", size: 40, tone: .peach)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Keep removed worktrees for").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                            Text("After this, saved .env files are deleted. The branch stays in git.")
                                .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 16)
                        // Keep a value set elsewhere selectable, so the menu never shows blank.
                        ClayPicker(title: "Keep removed worktrees for",
                                   selection: Binding(get: { model.prefs.retentionDays }, set: { model.prefs.retentionDays = $0 }),
                                   options: Array(Set([3, 7, 14, 30, days])).sorted().map { ($0, "\($0) days") })
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

/// "repo / branch", when it was removed, time left, and the saved commit in SF Mono.
private struct BinRow: View {
    let entry: BinEntry
    let retentionDays: Int
    let restore: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "archivebox")
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.repoName) / \(entry.branch ?? "detached")")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(removed) · \(left) · commit \(Text(String(entry.commit.prefix(7))).font(.mono(12)))")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 16)
            if entry.sizeBytes > 0 {
                Text(Fmt.bytes(entry.sizeBytes)).font(.system(size: 15)).monospacedDigit().foregroundStyle(Theme.text)
            }
            Button("Restore", action: restore).buttonStyle(.quiet)
        }
        .padding(.vertical, 14)
        .help(entry.worktreePath)
    }

    private var removed: String {
        let cal = Calendar.current
        if cal.isDateInToday(entry.removedAt) { return "Removed today" }
        if cal.isDateInYesterday(entry.removedAt) { return "Removed yesterday" }
        return "Removed \(Fmt.ago(entry.removedAt))"
    }

    private var left: String {
        let secs = entry.removedAt.addingTimeInterval(Double(retentionDays) * 86400).timeIntervalSinceNow
        if secs <= 0 { return "leaving soon" }
        if secs < 86400 { return "last day" }
        return "\(Int((secs / 86400).rounded(.up))) days left"
    }
}
