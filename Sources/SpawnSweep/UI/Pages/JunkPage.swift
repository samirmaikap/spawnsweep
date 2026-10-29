import SwiftUI
import AppKit

struct JunkPage: View {
    @Environment(AppModel.self) private var model
    private var junk: JunkStore { model.junk }
    private var firstScan: Bool { junk.scanning && junk.scannedAt == nil }

    /// Opens a cleaning preview. Without Pro it still lists everything, and its button leads to Pro.
    private func open(_ ids: [String]) {
        var spec = model.junk.review(ids)
        spec.lockForPro(model)
        model.present(spec)
    }

    var body: some View {
        PageScroll {
            BackLink(title: "This Mac") { model.go(.mac) }.padding(.bottom, -14)
            PageHeader(title: "Clear the clutter.", subtitle: "Caches, logs, and leftovers your Mac can rebuild.") {
                Button { open(JunkStore.safeIDs) } label: {
                    Label("Clean safe junk", systemImage: model.license.isPro ? "sparkles" : "lock.fill")
                }
                    .buttonStyle(.primary)
                    .disabled(junk.scanning || junk.safeBytes == 0)
            }
            if !model.license.isPro && model.junk.safeBytes > 0 {
                ProBanner(title: "\(Fmt.bytes(model.junk.safeBytes)) of junk, ready when you are",
                          line: "Pro clears it with a preview first and leaves open apps and IDE history alone. No second cleaner needed.")
            }
            hero
            if firstScan {
                SkeletonRows(count: 6)
            } else if junk.categories.isEmpty {
                EmptyState(symbol: "sparkles", title: "Nothing to clear.", message: "No caches, logs, or leftovers worth cleaning right now.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(junk.categories) { tile($0) }
                }
            }
            InfoBanner(text: "SpawnSweep only cleans things apps and tools can rebuild. Documents, photos and projects are never touched here.")
            // Totals differ between cleaners because each counts different things; say what this one counts.
            InfoBanner(text: "Other cleaners may show a different total. SpawnSweep counts developer caches (npm, Yarn, Gradle, Homebrew) that most skip, and leaves out system caches that need an admin password, Apple's own caches, open apps' caches, and IDE local history.", symbol: "info.circle")
        }
    }

    private var hero: some View {
        HeroCard(padding: 32) {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    if firstScan {
                        SkeletonBlock(width: 260, height: 34).padding(.vertical, 4)
                        Text("Measuring caches, logs, and leftovers…")
                    } else {
                        Text("\(Fmt.bytes(junk.totalBytes)) of junk").font(.system(size: 40)).tracking(-1)
                            .monospacedDigit().foregroundStyle(Theme.text).contentTransition(.numericText())
                        Text(junk.safeBytes > 0 ? "\(Fmt.bytes(junk.safeBytes)) is safe to clean now. Apps and tools rebuild it as needed."
                                                : "Nothing rebuildable to clean right now.")
                    }
                    HStack(spacing: 12) {
                        Button("Rescan") { junk.scan() }.buttonStyle(.quiet).disabled(junk.scanning)
                        Text(junk.scanning ? "Scanning…" : "Updated \(Fmt.ago(junk.scannedAt))").font(.meta)
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 16)
                IconTile(symbol: "bubbles.and.sparkles", size: 96, tone: .peach)
            }
        }
    }

    private func tile(_ c: JunkCategory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                IconTile(symbol: c.symbol, size: 64, tone: tone(c.id))
                Spacer(minLength: 10)
                if !c.unreadable { Badge(text: "\(c.items.count) item\(c.items.count == 1 ? "" : "s")") }
            }
            Text(c.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).padding(.top, 18)
            Text(c.unreadable ? "Private" : Fmt.bytes(c.bytes)).font(.system(size: 30)).tracking(-0.6).monospacedDigit()
                .foregroundStyle(Theme.text).contentTransition(.numericText()).padding(.top, 2)
            Text(c.note).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            Spacer(minLength: 16)
            if c.unreadable {
                Button("Open Trash") { NSWorkspace.shared.open(URL(fileURLWithPath: Shell.home + "/.Trash")) }.buttonStyle(.quiet)
            } else {
                Button(c.id == "trash" ? "Empty Trash" : "Review") { open([c.id]) }
                    .buttonStyle(QuietButtonStyle(destructive: c.id == "trash"))
                    .disabled(junk.scanning)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .clay(radius: 24, glass: false)
    }

    private func tone(_ id: String) -> ClayTone {
        switch id {
        case "caches": return .lilac
        case "dev": return .sky
        case "xcode": return .sage
        case "logs": return .sand
        case "installers": return .mint
        default: return .peach
        }
    }
}
