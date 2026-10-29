import SwiftUI
import AppKit

extension AppModel {
    /// Runs `action` with Pro; without it, opens the Pro page instead. The one gate every Pro button goes through.
    func requirePro(_ action: () -> Void) {
        if license.isPro { action() } else { dismissDialog(); go(.pro) }
    }

    /// Clean-ups Autopilot previewed in the last week: what Pro would have done for you.
    var previewsThisWeek: Int {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        return activity.filter { $0.kind == .dryRun && $0.date > weekAgo }.count
    }
}

extension DialogSpec {
    /// Without Pro, a cleaning preview still lists everything (that's the value) but its button opens the Pro page.
    @MainActor mutating func lockForPro(_ model: AppModel) {
        guard !model.license.isPro, action != nil else { return }
        confirmTitle = "Unlock Pro to clean"
        destructive = false
        notes.insert("Cleaning is part of SpawnSweep Pro. Nothing here changes until you unlock it.", at: 0)
        action = DialogSpec.followUp { model.dismissDialog(); model.go(.pro) }
    }
}

extension Theme {
    /// Sage into warm sand: the Pro surfaces, so they stand apart from regular cards.
    static let proGradient = LinearGradient(
        colors: [Color(light: 0xDDEBD3, dark: 0x3F5A48), Color(light: 0xF4E9D2, dark: 0x4C4330)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let proGold = Color(light: 0x9A6B1F, dark: 0xE9C98A)
}

/// Small "PRO" capsule for sidebar items and headings.
struct ProPill: View {
    var body: some View {
        if Edition.hasPro {
            Text("PRO").font(.system(size: 9.5, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Theme.proGold)
                .padding(.horizontal, 6).padding(.vertical, 2.5)
                .background(Capsule().fill(Theme.amberFill.shadow(.inner(color: Theme.clayHighlight, radius: 1.5, x: 0.5, y: 1))))
                .accessibilityLabel("Pro")
        }
    }
}

/// A contextual Pro pitch: a headline that names the problem, this Mac's real numbers, one button.
struct ProBanner: View {
    @Environment(AppModel.self) private var model
    let title: String
    let line: String
    var button = "Unlock Pro"

    var body: some View {
        if Edition.hasPro {
            HStack(alignment: .center, spacing: 20) {
                IconTile(symbol: "crown.fill", size: 58, tone: ClayTone(fill: Theme.amberFill, glyph: Theme.proGold))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) { ProPill(); Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text) }
                    Text(line).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button(button) { model.go(.pro) }.buttonStyle(.primary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clay(radius: 26, fill: Theme.proGradient)
        }
    }
}

/// Bottom of the sidebar while Pro isn't on: what Pro would do on this Mac right now.
struct SidebarProCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if Edition.hasPro {
            let junk = model.junk.totalBytes
            let selected = model.page == .pro
            Button { model.go(.pro) } label: {
                HStack(spacing: 10) {
                    IconTile(symbol: "crown.fill", size: 30, tone: ClayTone(fill: Theme.amberFill, glyph: Theme.proGold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SpawnSweep Pro").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(junk > 1_000_000_000 ? "\(Fmt.bytes(junk)) ready to clean" : "Clean up and automate")
                            .font(.system(size: 11)).foregroundStyle(Theme.proGold).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(ClayBackground(radius: 16, fill: AnyShapeStyle(Theme.proGradient), glass: false, raised: selected))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.proGold.opacity(selected ? 0.5 : 0.2)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .accessibilityLabel("SpawnSweep Pro")
        }
    }
}

/// What Pro adds, shown with this Mac's own numbers, then how to get it.
struct ProPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pro = model.license.isPro
        let junk = model.junk, large = model.largeFiles
        let measuring = junk.scannedAt == nil || large.scannedAt == nil
        PageScroll {
            PageHeader(eyebrow: "SpawnSweep Pro", title: pro ? "Pro is on. Thank you." : "Your whole Mac, looked after.",
                       subtitle: pro ? "Everything below is unlocked on this Mac." : "Everything you use today stays free. Pro cleans the rest of your Mac and lets Autopilot do the work.")

            hero(pro: pro)

            Panel(title: "On this Mac right now") {
                HStack(spacing: 16) {
                    valueTile("bubbles.and.sparkles", .peach, measuring && junk.totalBytes == 0 ? "…" : Fmt.bytes(junk.totalBytes),
                              "of junk ready to clean", "Caches, logs, developer caches, Xcode leftovers.") { model.go(.junk) }
                    valueTile("doc.text.magnifyingglass", .sand, measuring && large.staleBytes == 0 ? "…" : Fmt.bytes(large.staleBytes),
                              "in files untouched for 6 months", "Big files you can review and send to the Trash.") { model.go(.largeFiles) }
                    valueTile("sparkles", .mint, "\(model.previewsThisWeek)",
                              "clean-ups Autopilot only previewed", "In the last week. With Pro, rules can ask or just do them.") { model.go(.autopilot) }
                }
            }

            Panel(title: "What Pro adds") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    feature("bubbles.and.sparkles", .peach, "Junk cleaner",
                            "Caches, logs, npm/Yarn/Gradle caches, Xcode leftovers and old installers. Open apps and IDE history are left alone.")
                    feature("doc.text.magnifyingglass", .sand, "Large & old files",
                            "Big files you haven't opened in months, with the reason for each. They go to the Trash, so nothing is lost.")
                    feature("laptopcomputer", .sky, "Instead of another cleaner",
                            "Disk, memory and junk in the same calm place as your agent leftovers. One app, one set of safety rules.")
                    feature("bell.badge", .lilac, "Autopilot asks first",
                            "A notification when a rule matches. One click opens the preview.")
                    feature("bolt", .mint, "Autopilot acts on its own",
                            "Rules stop leftovers and tidy worktrees by themselves, and log a way back for each change.")
                    feature("clock", .sage, "Rules that run themselves",
                            "Clean up at the end of the day, battery saver when unplugged, room to breathe when the disk runs low.")
                }
            }

            comparison

            HStack(spacing: 12) {
                trust("lock.shield", "Same safety: preview first, recycle bin, nothing outside its folder")
                trust("wifi.slash", "Works offline for weeks between checks")
                trust("heart", "Supports the free, open-source app")
            }

            LicensePanel(compact: true)
        }
    }

    private func hero(pro: Bool) -> some View {
        HStack(alignment: .center, spacing: 28) {
            AppMark(size: 92)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) { ProPill(); Text(pro ? "Unlocked" : "One-time purchase").font(.meta).foregroundStyle(Theme.secondary) }
                Text(pro ? "Clean, automate, and forget about it." : "One app for agent leftovers and your whole Mac.")
                    .heading(24).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if pro {
                        Button("Open This Mac") { model.go(.mac) }.buttonStyle(.primaryLarge)
                    } else if let url = License.checkoutURL {
                        Button("Get SpawnSweep Pro") { NSWorkspace.shared.open(url) }.buttonStyle(.primaryLarge)
                    } else {
                        Button("Get SpawnSweep Pro") {}.buttonStyle(.primaryLarge).disabled(true)
                            .help("Checkout opens when Pro goes on sale.")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clay(radius: 30, fill: Theme.proGradient)
    }

    private func valueTile(_ symbol: String, _ tone: ClayTone, _ value: String, _ label: String, _ note: String,
                           open: @escaping () -> Void) -> some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                IconTile(symbol: symbol, size: 44, tone: tone)
                Text(value).font(.system(size: 30)).tracking(-0.6).monospacedDigit().foregroundStyle(Theme.text).padding(.top, 4)
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(note).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
            .clay(radius: 22, glass: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func feature(_ symbol: String, _ tone: ClayTone, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: symbol, size: 48, tone: tone)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .clay(radius: 22, glass: false)
    }

    private var comparison: some View {
        let rows: [(String, Bool)] = [
            ("Sessions, ports, resources and the menu bar", true),
            ("Worktrees: slim, recycle, restore", true),
            ("Disk and memory overview, junk and large-file scans", true),
            ("Autopilot dry runs and Run now", true),
            ("Clean junk and large & old files", false),
            ("Autopilot Ask first and Automatic", false),
            ("End-of-day, battery and low-disk rules acting on their own", false)
        ]
        return Panel(title: "Free and Pro") {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Text("Free").frame(width: 70)
                    HStack(spacing: 4) { ProPill() }.frame(width: 70)
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 16).padding(.bottom, 8)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack {
                        Text(row.0).font(.system(size: 13)).foregroundStyle(Theme.text)
                        Spacer()
                        mark(row.1).frame(width: 70)
                        mark(true).frame(width: 70)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(i % 2 == 0 ? Theme.tint.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.vertical, 6)
            .clayInset(radius: 18, fill: Theme.surface.opacity(0.4))
        }
    }

    private func mark(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "minus")
            .font(.system(size: on ? 15 : 12, weight: .semibold))
            .foregroundStyle(on ? Theme.activeText : Theme.secondary.opacity(0.6))
            .accessibilityLabel(on ? "Included" : "Not included")
    }

    private func trust(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.activeText)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .clayInset(radius: 16)
    }
}
