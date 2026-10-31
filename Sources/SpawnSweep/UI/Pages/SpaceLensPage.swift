import SwiftUI
import AppKit

/// This Mac › Space Lens: the whole disk, measured once, as a list with checkboxes beside a cluster of clay moons.
/// Tick what you don't need and Remove sends it to the Trash through a preview. Locked rows say why they can't go.
struct SpaceLensPage: View {
    @Environment(AppModel.self) private var model
    private var lens: LensStore { model.lens }

    var body: some View {
        PageScroll {
            BackLink(title: "This Mac") { model.go(.mac) }.padding(.bottom, -14)
            PageHeader(title: "See where your space went.", subtitle: "Your whole disk by size. Tick what you don't need, then remove it.") {
                if lens.phase == .ready {
                    Button { lens.start() } label: { Label("Start over", systemImage: "arrow.counterclockwise") }.buttonStyle(.quiet)
                }
            }
            switch lens.phase {
            case .idle: startCard
            case .scanning: scanningCard
            case .ready: results
            }
        }
        .onAppear { lens.refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in lens.refreshAccess() }
    }

    // MARK: - Start and scanning

    /// Laid out like the Sessions hero: words and the app's pill button on the left, the moon on the right.
    private var startCard: some View {
        HeroCard {
            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SPACE LENS").font(.system(size: 11, weight: .semibold)).tracking(1.6).foregroundStyle(Theme.activeText)
                    Text("Map your whole disk.").heading(26).padding(.top, 8)
                    Text(lens.stoppedEarly ? "Stopped. Scan again whenever you like."
                         : "Space Lens measures everything on Macintosh HD once, then you can look through it instantly. It takes a few minutes.")
                        .font(.system(size: 14)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                    if !lens.hasAccess {
                        Label("Needs Full Disk Access. Scan opens the switch in System Settings.", systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.amberText)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.amberFill))
                            .padding(.top, 16)
                    }
                    Button { lens.start() } label: {
                        HStack(spacing: 8) { Text("Scan disk"); Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)) }
                    }
                    .buttonStyle(.primaryLarge)
                    .padding(.top, 24)
                }
                Spacer(minLength: 0)
                Moon(size: 130).frame(width: 190, height: 150)
            }
        }
    }

    private var scanningCard: some View {
        VStack(spacing: 16) {
            HeroCard {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Measuring your disk…").heading(26)
                        Text(lens.progress.path.isEmpty ? "Starting…" : lens.progress.path)
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondary)
                            .lineLimit(1).truncationMode(.middle).padding(.top, 14)
                        progressBar.padding(.top, 12)
                        Button { lens.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                            .buttonStyle(.quiet).padding(.top, 20)
                            .accessibilityLabel("Stop measuring")
                    }
                    GatherMoons().frame(width: 290, height: 180)
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                scanTiles(elapsed: ctx.date.timeIntervalSince(lens.startedAt))
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.barTrack)
                Capsule().fill(Theme.accentLight).frame(width: max(8, g.size.width * lens.done))
            }
        }
        .frame(height: 7)
        .animation(.easeOut(duration: 0.4), value: lens.done)
    }

    /// The Sessions page's stat tiles: what's measured, how far through the disk, and time.
    private func scanTiles(elapsed: TimeInterval) -> some View {
        let percent: String = "\(Int(lens.done * 100))%"
        let of: String = lens.diskUsed > 0 ? "Of \(Fmt.bytes(lens.diskUsed)) in use" : "Of your disk"
        return HStack(spacing: 16) {
            SessionStatTile(symbol: "internaldrive", tone: .sage) {
                StatBlock(value: Fmt.bytes(lens.progress.bytes), label: "Measured so far")
            }
            SessionStatTile(symbol: "folder", tone: .sky) { StatBlock(value: percent, label: of) }
            SessionStatTile(symbol: "clock", tone: .sand) {
                StatBlock(value: Self.clock(elapsed), label: Self.timeLeft(elapsed: elapsed, done: lens.done))
            }
        }
    }

    /// "48s", "2m 05s".
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s < 60 ? "\(s)s" : String(format: "%dm %02ds", s / 60, s % 60)
    }

    /// A rough finish time from the pace so far, once there's enough of it to go on.
    static func timeLeft(elapsed: TimeInterval, done: Double) -> String {
        guard done >= 0.05, elapsed >= 5 else { return "Working out time left" }
        let left: Double = elapsed * (1 - done) / done
        if left < 60 { return "Less than a minute left" }
        let minutes = Int((left / 60).rounded())
        return "About \(minutes) minute\(minutes == 1 ? "" : "s") left"
    }

    // MARK: - Results

    private var results: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                list.frame(width: 410)
                Rectangle().fill(Theme.border.opacity(0.6)).frame(width: 1).padding(.vertical, 18)
                moons.frame(maxWidth: .infinity)
            }
            .frame(height: 480)
            footer
        }
        .clay(radius: 30, fill: Theme.heroGradient, glass: false)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            pathBar.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
            if let nodes = lens.levels[lens.current] {
                if nodes.isEmpty {
                    Text("Nothing here takes up space.").font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) { ForEach(nodes) { row($0) } }.padding(.horizontal, 8).padding(.bottom, 10)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Measuring \(Self.title(lens.current))…").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                .padding(20)
            }
            Spacer(minLength: 0)
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            navButton("chevron.left", enabled: lens.stack.count > 1) { lens.back() }
            navButton("chevron.right", enabled: !lens.forward.isEmpty) { lens.goForward() }
            // Deep folders run past the edge, so the crumbs always scroll to the folder you're in.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(lens.stack.enumerated()), id: \.offset) { i, path in
                            if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary) }
                            let last = i == lens.stack.count - 1
                            Button { lens.up(to: i) } label: {
                                Text(Self.title(path)).font(.system(size: 13, weight: last ? .semibold : .medium))
                                    .foregroundStyle(last ? Theme.text : Theme.secondary).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .id(i)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(lens.stack.count - 1, anchor: .trailing) }
                .onChange(of: lens.stack) { _, stack in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(stack.count - 1, anchor: .trailing) }
                }
            }
        }
    }

    private func navButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? Theme.text : Theme.secondary.opacity(0.5))
                .frame(width: 30, height: 28).clayInset(radius: 9)
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    private func row(_ n: LensNode) -> some View {
        let refusal = lens.refusals[n.path]
        let isChecked = lens.checked[n.path] != nil
        let canOpen = n.isDir && !n.locked
        return HStack(spacing: 12) {
            if let refusal {
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.secondary.opacity(0.6))
                    .frame(width: 22).help(refusal)
            } else {
                Button { lens.toggle(n) } label: {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square").font(.system(size: 17))
                        .foregroundStyle(isChecked ? Theme.accentLight : Theme.secondary).frame(width: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isChecked ? "Untick \(n.name)" : "Tick \(n.name) for removal")
            }
            Circle()
                .fill(RadialGradient(colors: LensMoon.palette(n.kind).map { Color(hex: $0) }, center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: 22))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(n.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text(Self.describe(n)).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(n.locked ? "—" : Fmt.bytes(n.bytes)).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.text)
            Button { if canOpen { lens.open(n.path) } } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(canOpen ? Theme.secondary : .clear).frame(width: 18, height: 24)
            }
            .buttonStyle(.plain).disabled(!canOpen)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(lens.hovered == n.path ? Theme.tintStrong.opacity(0.8) : .clear))
        .contentShape(Rectangle())
        .onHover { inside in if inside { lens.hovered = n.path } else if lens.hovered == n.path { lens.hovered = nil } }
        .onTapGesture(count: 2) { if canOpen { lens.open(n.path) } }
        .contextMenu {
            if canOpen { Button("Open") { lens.open(n.path) } }
            if n.kind != .unmeasured {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: n.path)]) }
            }
        }
    }

    /// The packed layout, scaled to the panel. Hover and ticks only restyle moons; nothing is repacked.
    private var moons: some View {
        GeometryReader { geo in
            if let layout = lens.layouts[lens.current], !layout.moons.isEmpty {
                let w = geo.size.width, h = geo.size.height, b = layout.bounds
                let k = min((w - 36) / max(1, b.width), (h - 36) / max(1, b.height))
                ZStack {
                    ForEach(Array(layout.moons.enumerated()), id: \.element.path) { i, n in
                        LensMoon(node: n, r: layout.radii[i] * k, hovered: lens.hovered == n.path,
                                 dimmed: lens.hovered != nil && lens.hovered != n.path, checked: lens.checked[n.path] != nil)
                            .position(x: w / 2 + (layout.points[i].x - b.midX) * k, y: h / 2 + (layout.points[i].y - b.midY) * k)
                            .onHover { inside in if inside { lens.hovered = n.path } else if lens.hovered == n.path { lens.hovered = nil } }
                            .onTapGesture { if n.isDir && !n.locked { lens.open(n.path) } }
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: lens.hovered)
            }
        }
        .padding(.vertical, 10)
    }

    private var footer: some View {
        let map = lens.map
        let used = map?.diskUsed ?? 0, total = map?.diskTotal ?? 0
        let n = lens.checked.count
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Macintosh HD · \(Fmt.bytes(used)) used of \(Fmt.bytes(total))").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.barTrack)
                        Capsule().fill(Theme.accentLight).frame(width: total > 0 ? g.size.width * CGFloat(Double(used) / Double(total)) : 0)
                    }
                }
                .frame(width: 260, height: 7)
            }
            Spacer()
            Text(n == 0 ? "Tick what you don't need" : "\(n) item\(n == 1 ? "" : "s") · \(Fmt.bytes(lens.checkedBytes)) to the Trash")
                .font(.system(size: 13)).monospacedDigit().foregroundStyle(Theme.secondary)
            Button { model.reviewLensRemove(Array(lens.checked.values)) } label: { Label("Move to Trash", systemImage: "trash") }
                .buttonStyle(.primary).disabled(n == 0)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Theme.tint.opacity(0.35))
    }

    // MARK: - Words

    static func title(_ path: String) -> String {
        path == "/" ? "Macintosh HD" : (path as NSString).lastPathComponent
    }

    /// One line under each name: what it is, in plain words.
    static func describe(_ n: LensNode) -> String {
        if n.locked { return "Needs Full Disk Access to measure" }
        let home = Shell.home
        let known: [String: String] = [
            "/Users": "Your home folder and other accounts", "/System": "macOS itself", "/Applications": "Your apps",
            "/Library": "Shared app data for every account", "/private": "System caches, logs and swap",
            "/opt": "Homebrew and other tools", "/usr": "Command-line tools", "/bin": "macOS command-line tools",
            "/sbin": "macOS system tools", "/cores": "Crash dumps",
            home: "Your home folder", home + "/Library": "Your apps' data and settings", home + "/Applications": "Apps just for you",
            home + "/.npm": "npm download cache. Rebuilt on demand", home + "/.cache": "Tool caches. Rebuilt on demand",
            home + "/.cocoapods": "CocoaPods cache. Rebuilt on demand", home + "/.gradle": "Gradle settings and caches",
            home + "/.android": "Android SDK and emulators", home + "/.claude": "Claude Code data", home + "/.codex": "Codex data",
            home + "/.docker": "Docker settings", home + "/.cursor": "Cursor data", home + "/.vscode": "VS Code extensions",
        ]
        if let k = known[n.path] { return k }
        if (n.path as NSString).deletingLastPathComponent == home + "/Library/Developer/CoreSimulator/Devices" {
            return "Simulator. Xcode can make a new one any time"
        }
        switch n.kind {
        case .unmeasured: return LensAccess.full ? "Snapshots, purgeable and hidden system data"
                                                 : "Folders skipped without Full Disk Access, snapshots and system data"
        case .rebuildable: return "Safe to clear. Rebuilt on demand"
        case .project: return "Project"
        case .apps: return n.isDir ? "App" : "File"
        case .appData: return "App data"
        case .system: return "Part of macOS"
        case .yourFiles, .other: return n.isDir ? "Folder" : "File"
        }
    }
}

/// A folder or file as a clay moon, with the app icon's moon gradient in the color of what it is.
struct LensMoon: View {
    let node: LensNode
    let r: CGFloat
    var hovered = false
    var dimmed = false
    var checked = false

    static func palette(_ k: LensKind) -> [UInt32] {
        switch k {
        case .project: return [0xF7FAEC, 0xD3E2BE, 0x9DBB88, 0x5F8A66]
        case .rebuildable: return [0xF0FAF5, 0xC7EBD8, 0x86C9A6, 0x3F8A66]
        case .yourFiles: return [0xFBF6EA, 0xEAD9B4, 0xC9A86E, 0x8E6E3A]
        case .appData: return [0xF1F6FC, 0xCFE0F2, 0x93B4D8, 0x557BA6]
        case .apps: return [0xF6F3FD, 0xDCD3F3, 0xA899D6, 0x6A5BA6]
        case .system: return [0xF1F3F5, 0xD3D9E0, 0x9DA9B6, 0x5E6B7A]
        case .unmeasured: return [0x8A9A90, 0x6F8076, 0x56665C, 0x3E4C43]
        case .other: return [0xF6F3FD, 0xDCD3F3, 0xA899D6, 0x6A5BA6]
        }
    }
    static func ink(_ k: LensKind) -> Color {
        switch k {
        case .yourFiles: return Color(hex: 0x4A3712)
        case .appData: return Color(hex: 0x1E3A5A)
        case .apps, .other: return Color(hex: 0x3A2F66)
        case .system: return Color(hex: 0x2E3A47)
        case .unmeasured: return Color(hex: 0xE6EEE9)
        case .project, .rebuildable: return Color(hex: 0x24382C)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: Self.palette(node.kind).map { Color(hex: $0) },
                                     center: UnitPoint(x: 0.3, y: 0.24), startRadius: 0, endRadius: r * 1.7))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(node.kind == .unmeasured ? 0.25 : 0.85), .clear],
                                                              startPoint: .topLeading, endPoint: .center), lineWidth: 1.5))
                .overlay(node.kind == .unmeasured
                         ? Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(Color.white.opacity(0.35)).padding(4)
                         : nil)
                .frame(width: r * 2, height: r * 2)
                .shadow(color: .black.opacity(hovered ? 0.5 : 0.32), radius: r * (hovered ? 0.2 : 0.12), x: r * 0.03, y: r * (hovered ? 0.13 : 0.07))
            if r > 36 {
                VStack(spacing: 3) {
                    Text(node.name).font(.system(size: r > 90 ? 16 : r > 55 ? 13 : 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(node.locked ? "Not measured" : Fmt.bytes(node.bytes)).font(.system(size: r > 90 ? 14 : 11, weight: .medium)).monospacedDigit().opacity(0.8)
                    if hovered && node.kind == .rebuildable {
                        Text("Safe to clear").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0x24563A))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.75))).padding(.top, 4)
                    }
                }
                .foregroundStyle(Self.ink(node.kind))
                .frame(width: max(r * 1.6, hovered ? 120 : 0))
            } else if hovered {
                // Too small to hold its own label: a readable tag above the moon instead.
                VStack(spacing: 2) {
                    Text(node.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(node.locked ? "Not measured" : Fmt.bytes(node.bytes)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3))
                .fixedSize()
                .offset(y: -r - 26)
            }
            if checked {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, Theme.accent)
                    .offset(x: r * 0.62, y: -r * 0.62)
            }
        }
        .scaleEffect(hovered ? 1.1 : 1)
        .opacity(dimmed ? 0.55 : 1)
        .zIndex(hovered ? 2 : 0)
        .contentShape(Circle())
        .help("\(node.name) · \(node.locked ? "not measured" : Fmt.bytes(node.bytes))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(node.name), \(node.locked ? "not measured" : Fmt.bytes(node.bytes))")
    }
}

/// While Space Lens measures, small moons in the colors of what it finds drift out from behind the app's moon
/// and settle into a cluster, a hint of the map to come. Still with Reduce Motion. The app's only looping motion,
/// and only while it's working.
struct GatherMoons: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let moons: [(kind: LensKind, size: CGFloat, x: CGFloat, y: CGFloat)] = [
        (.yourFiles, 30, 106, -40), (.appData, 22, 124, 6), (.apps, 26, 100, 48),
        (.rebuildable, 18, -92, 44), (.system, 20, -86, -50), (.project, 14, 58, -72)
    ]
    static let period = 6.0

    /// One moon's trip, `f` from 0 to 1: out from behind the big moon (first 55%), a gentle bob, then a fade.
    static func stage(_ f: Double) -> (travel: Double, opacity: Double, scale: Double, bob: Double) {
        let x: Double = min(1, f / 0.55)
        let travel: Double = x * x * (3 - 2 * x)
        let opacity: Double = f < 0.15 ? f / 0.15 : f > 0.85 ? (1 - f) / 0.15 : 1
        let shrink: Double = f > 0.85 ? 0.1 * (f - 0.85) / 0.15 : 0
        let bob: Double = f > 0.55 ? -4 * sin(min(1, (f - 0.55) / 0.3) * .pi) : 0
        return (travel, opacity, 0.2 + 0.8 * travel - shrink, bob)
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let breathe: CGFloat = reduceMotion ? 1 : 1 + 0.015 * CGFloat(sin(t * 2 * .pi / 3.2))
            ZStack {
                ForEach(0..<Self.moons.count, id: \.self) { i in
                    moon(i, t: t)
                }
                Moon(size: 110, rings: false).scaleEffect(breathe)
            }
        }
        .accessibilityHidden(true)
    }

    private func moon(_ i: Int, t: Double) -> some View {
        let m = Self.moons[i]
        let f: Double = (t - Double(i)).truncatingRemainder(dividingBy: Self.period) / Self.period
        let s = reduceMotion ? (travel: 1.0, opacity: 1.0, scale: 1.0, bob: 0.0) : Self.stage(f)
        let colors: [Color] = LensMoon.palette(m.kind).map { Color(hex: $0) }
        return Circle()
            .fill(RadialGradient(colors: colors, center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: m.size))
            .frame(width: m.size, height: m.size)
            .shadow(color: .black.opacity(0.3), radius: 4, x: 1, y: 3)
            .scaleEffect(s.scale)
            .opacity(s.opacity)
            .offset(x: m.x * CGFloat(s.travel), y: m.y * CGFloat(s.travel) + CGFloat(s.bob))
    }
}
