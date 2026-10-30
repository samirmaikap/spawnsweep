import SwiftUI
import AppKit

struct MacOverviewPage: View {
    @Environment(AppModel.self) private var model

    private let grid = [GridItem(.adaptive(minimum: 200), spacing: 16, alignment: .top)]

    var body: some View {
        PageScroll {
            PageHeader(title: "Your Mac at a glance.", subtitle: Edition.hasPro ? "Space, memory, junk, and big forgotten files. Open any card for the details."
                                                     : "Space, memory, and developer leftovers. Open any card for the details.")
            if !model.license.isPro {
                let found = model.junk.totalBytes + model.largeFiles.staleBytes
                ProBanner(title: "Clean your whole Mac from here.",
                          line: found > 0 ? "SpawnSweep already found \(Fmt.bytes(model.junk.totalBytes)) of junk and \(Fmt.bytes(model.largeFiles.staleBytes)) in files you haven't opened in months. Pro clears them with a preview first and the same safety rules, so you don't need a second cleaner."
                                          : "Disk, memory, junk and forgotten files, next to your agent leftovers. Pro clears them with a preview first and the same safety rules, so you don't need a second cleaner.",
                          button: "See Pro")
            }
            storageHero
            quickWins
            memoryPanel
            appsPanel
        }
        .onAppear { model.system.refresh() }
    }

    private var junkMeasuring: Bool { model.junk.scanning || model.junk.scannedAt == nil }
    private var largeMeasuring: Bool { model.largeFiles.scanning || model.largeFiles.scannedAt == nil }
    /// Worktree dependencies plus unused simulators. Xcode DerivedData is left out only when Pro's Junk counts it,
    /// so the same gigabytes aren't counted twice; the free edition has no Junk and adds it here.
    private var devLeftovers: Int64 {
        let base = model.disk.slimBytes + model.disk.unusedDeviceBytes
        return Edition.hasPro ? base : base + model.disk.derivedData.reduce(0) { $0 + $1.bytes }
    }
    private var devMeasuring: Bool { model.diskUpdatedAt == nil && (model.disk.inProgress || model.diskScanning) }

    /// Memory reads in binary units, like Activity Monitor ("16 GB", not "17.2 GB").
    private func mem(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .memory) }

    // MARK: - Storage

    private static let junkColor = ClayTone.peach.glyph, largeColor = ClayTone.sand.glyph, devColor = ClayTone.sage.glyph
    private static let otherColor = Theme.barNeutral, freeColor = Theme.barTrack

    private var storageHero: some View {
        let v = model.system.volume
        let junk = junkMeasuring ? 0 : model.junk.totalBytes
        let large = largeMeasuring ? 0 : model.largeFiles.staleBytes
        let dev = devMeasuring ? 0 : devLeftovers
        let other = max(0, v.used - junk - large - dev)
        return HeroCard(padding: 30) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        if v.total == 0 {
                            SkeletonBlock(width: 240, height: 30).padding(.vertical, 4)
                            Text("Measuring…")
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Fmt.bytes(v.free)).font(.system(size: 36)).tracking(-0.9).monospacedDigit()
                                    .foregroundStyle(Theme.text).contentTransition(.numericText())
                                Text("free of \(Fmt.bytes(v.total))").font(.system(size: 17))
                            }
                            Text(storageInsight(v, reclaim: junk + large + dev))
                        }
                    }
                    .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 16)
                    if v.total > 0 { Chip(text: "\(Int((Double(v.used) / Double(v.total) * 100).rounded()))% used").monospacedDigit() }
                }
                StorageBar(segments: [(other, Self.otherColor), (dev, Self.devColor), (large, Self.largeColor), (junk, Self.junkColor)],
                           total: max(v.total, 1), height: 16)
                    .padding(.top, 24)
                legend((Edition.hasPro ? [
                    ("Junk", junkMeasuring ? "Measuring…" : Fmt.bytes(junk), Self.junkColor),
                    ("Large & old files", largeMeasuring ? "Measuring…" : Fmt.bytes(large), Self.largeColor)
                ] : []) + [
                    ("Developer leftovers", devMeasuring ? "Measuring…" : Fmt.bytes(dev), Self.devColor),
                    ("Everything else", Fmt.bytes(other), Self.otherColor),
                    ("Free", Fmt.bytes(v.free), Self.freeColor)
                ])
                .padding(.top, 18)
            }
        }
    }

    private func storageInsight(_ v: VolumeStats, reclaim: Int64) -> String {
        let tight = Double(v.free) < Double(v.total) * 0.1
        switch (tight, reclaim > 0) {
        case (true, true): return Edition.hasPro ? "Space is tight. Junk, old files, and developer leftovers could give back about \(Fmt.bytes(reclaim))."
                                                 : "Space is tight. Developer leftovers could give back about \(Fmt.bytes(reclaim))."
        case (true, false): return "Space is tight. macOS works best with at least 10% free."
        case (false, true): return Edition.hasPro ? "About \(Fmt.bytes(reclaim)) of the used space is junk, old files, or developer leftovers."
                                                  : "About \(Fmt.bytes(reclaim)) of the used space is developer leftovers."
        case (false, false): return "Plenty of room. Nothing much is piling up."
        }
    }

    // MARK: - Memory

    private var memoryPanel: some View {
        let m = model.system.memory
        let free = max(0, m.total - m.used - m.cached)
        let colors: [Color] = [Theme.accent, ClayTone.lilac.glyph, ClayTone.sky.glyph, Theme.barNeutral]
        return Panel(title: "Memory", boxed: true, trailing: { pressureBadge(m.pressure) }) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mem(m.used)).font(.system(size: 30)).tracking(-0.6).monospacedDigit()
                    .foregroundStyle(Theme.text).contentTransition(.numericText())
                Text("used of \(mem(m.total))").font(.system(size: 15)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 16)
                Chip(text: m.swapUsed > 0 ? "Swap · \(mem(m.swapUsed))" : "No swap in use").monospacedDigit()
            }
            StorageBar(segments: zip([m.app, m.wired, m.compressed, m.cached], colors).map { ($0, $1) }, total: max(m.total, 1), height: 14)
            legend([
                ("App memory", mem(m.app), colors[0]),
                ("Wired", mem(m.wired), colors[1]),
                ("Compressed", mem(m.compressed), colors[2]),
                ("Cached files", mem(m.cached), colors[3]),
                ("Free", mem(free), Self.freeColor)
            ])
            switch m.pressure {
            case .critical: WarningBanner(text: "Memory is under heavy pressure. Quit apps you're not using. That helps more than any 'free memory' button.")
            case .warning: WarningBanner(text: "Memory is under pressure. Closing apps you're not using helps more than any 'free memory' button.")
            case .normal:
                InfoBanner(text: m.compressed > 0
                           ? "Plenty of room. Compressed memory is normal; macOS packs idle data so it stays quick to reach."
                           : "Plenty of room. Cached files are let go the moment apps need the space.",
                           symbol: "memorychip")
            }
        }
    }

    @ViewBuilder private func pressureBadge(_ p: MemoryStats.Pressure) -> some View {
        switch p {
        case .normal: Badge(text: "Pressure normal", style: .success, symbol: "checkmark")
        case .warning: Badge(text: "Under pressure", style: .warning, symbol: "exclamationmark.triangle")
        case .critical: Badge(text: "Heavy pressure", style: .warning, symbol: "exclamationmark.triangle.fill")
        }
    }

    // MARK: - Top apps

    private var appsPanel: some View {
        let apps = model.system.topApps
        let leftovers = model.workspace.allResources.reduce(Int64(0)) { $0 + $1.memoryBytes }
        let running = NSWorkspace.shared.runningApplications
        return Panel(title: "Using the most memory") {
            if apps.isEmpty {
                SkeletonRows(count: 3)
            } else {
                LazyVGrid(columns: grid, alignment: .leading, spacing: 16) {
                    ForEach(apps) { a in
                        appTile(a, gui: a.bundleID.flatMap { id in running.first { $0.bundleIdentifier == id && $0.activationPolicy == .regular } })
                    }
                    if leftovers > 0 {
                        Tile(title: "Agent leftovers", value: mem(leftovers), caption: "Servers and tools agents left running.") {
                            IconTile(symbol: Page.sessions.symbol, size: 50, tone: .sage)
                        } action: {
                            NavLink(title: "Review in Sessions") { model.go(.sessions) }
                        }
                    }
                }
            }
        }
    }

    private func appTile(_ a: AppMemory, gui: NSRunningApplication?) -> some View {
        Tile(title: a.name, value: mem(a.bytes),
             caption: gui != nil ? "Open app" : a.bundleID != nil ? "Running in the background" : "System or command-line process") {
            if let icon = gui?.icon {
                Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                    .frame(width: 50, height: 50).clay(radius: 16, glass: false)
            } else {
                IconTile(symbol: a.bundleID != nil ? "app" : "gearshape.2", size: 50, tone: .sky)
            }
        } action: {
            // Graceful quit: the app may ask to save first.
            if let gui, gui != .current { Button("Quit") { gui.terminate() }.buttonStyle(.quiet) }
        }
    }

    // MARK: - Quick wins

    /// Each card is closed by default: a total and one line of what's inside. Clicking opens its page.
    private var quickWins: some View {
        let junkTop = model.junk.categories.filter { $0.bytes > 0 && !$0.unreadable }.sorted { $0.bytes > $1.bytes }.prefix(2)
            .map { "\($0.title) \(Fmt.bytes($0.bytes))" }.joined(separator: " · ")
        let files = model.largeFiles.files
        return Panel(title: "Clean up this Mac") {
            LazyVGrid(columns: grid, alignment: .leading, spacing: 16) {
                if Edition.hasPro {
                    card(.junk, title: "Junk", value: junkMeasuring ? "Measuring…" : Fmt.bytes(model.junk.totalBytes),
                         caption: junkMeasuring || junkTop.isEmpty ? "Caches, logs, and leftovers apps don't clean up." : junkTop, tone: .peach)
                    card(.largeFiles, title: "Large & old files", value: largeMeasuring ? "Measuring…" : Fmt.bytes(model.largeFiles.totalBytes),
                         caption: largeMeasuring ? "Big files you haven't opened in a while."
                            : "\(files.count) file\(files.count == 1 ? "" : "s") · \(Fmt.bytes(model.largeFiles.staleBytes)) not opened in 6 months", tone: .sand)
                    card(.spaceLens, title: "Space Lens", value: "Explore", caption: "See what fills your disk, folder by folder.", tone: .sky)
                }
                card(.storage, title: "Developer leftovers", value: devMeasuring ? "Measuring…" : Fmt.bytes(devLeftovers),
                     caption: "Dependencies and build output your projects can rebuild.", tone: .sage)
            }
        }
    }

    private func card(_ page: Page, title: String, value: String, caption: String, tone: ClayTone) -> some View {
        Button { model.go(page) } label: {
            Tile(title: title, value: value, caption: caption) {
                IconTile(symbol: page.symbol, size: 56, tone: tone)
            } action: {
                HStack(spacing: 6) {
                    Text("Open").font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.activeText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title), \(value)")
    }

    // MARK: - Pieces

    private func legend(_ items: [(String, String, Color)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 12) {
            ForEach(items, id: \.0) { label, value, color in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(color).frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Theme.secondary.opacity(0.45), lineWidth: 1))   // dark swatches stay visible
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        Text(value).font(.system(size: 14)).monospacedDigit().foregroundStyle(Theme.text)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Clay tile: icon and value on top, name and context below, one action at the bottom.
private struct Tile<Icon: View, Action: View>: View {
    let title: String
    let value: String
    var caption = ""
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                icon()
                Spacer(minLength: 10)
                Text(value).font(.system(size: 20)).tracking(-0.3).monospacedDigit().foregroundStyle(Theme.text)
                    .lineLimit(1).contentTransition(.numericText())
            }
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                .padding(.top, 14)
            if !caption.isEmpty {
                Text(caption).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            Spacer(minLength: 12)
            HStack { action(); Spacer(minLength: 0) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .clay(radius: 22, glass: false)
    }
}
