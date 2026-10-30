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
            if !LensAccess.full { accessBanner }
            switch lens.phase {
            case .idle: startCard
            case .scanning: scanningCard
            case .ready: results
            }
        }
    }

    // MARK: - Start and scanning

    private var startCard: some View {
        VStack(spacing: 16) {
            OrbitMoons(moving: false).padding(.top, 10)
            Text("Build your storage map").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
            Text(lens.stoppedEarly ? "Stopped. Start again whenever you like."
                 : "Space Lens measures your whole disk once, then you can look through it instantly. It takes a few minutes.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            RoundButton(title: "Scan") { lens.start() }.padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .clay(radius: 30, fill: Theme.heroGradient, glass: false)
    }

    private var scanningCard: some View {
        let p = lens.progress
        return VStack(spacing: 16) {
            OrbitMoons(moving: true)
            Text("Building your storage map…").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
            Text(p.path.isEmpty ? "Starting…" : p.path)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondary)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 560)
            HStack(spacing: 18) {
                StopRing(fraction: p.fraction) { lens.stop() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.bytes(p.bytes)).font(.system(size: 20, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                    Text("measured so far").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .clay(radius: 30, fill: Theme.heroGradient, glass: false)
    }

    private var accessBanner: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "lock.shield", size: 32, tone: .sky)
            VStack(alignment: .leading, spacing: 2) {
                Text("Desktop, Documents, Downloads and other apps' data are skipped.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text("macOS would ask about each one. Give SpawnSweep Full Disk Access once to measure everything, then quit and reopen it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open Settings") { NSWorkspace.shared.open(LensAccess.settings) }.buttonStyle(.quiet)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .clayInset(radius: 18)
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
                    }
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
            RoundButton(title: "Remove", enabled: n > 0) { model.reviewLensRemove(Array(lens.checked.values)) }
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
            if r > 36 || hovered {
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

/// Small moons orbiting the app's moon while Space Lens measures; still before a scan and with Reduce Motion.
/// The only looping motion in the app, and only while it's working.
struct OrbitMoons: View {
    var moving: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let moons: [(tone: LensKind, size: CGFloat, speed: Double, phase: Double)] =
        [(.yourFiles, 26, 0.55, 0.6), (.appData, 18, 0.8, 2.8), (.apps, 14, 1.1, 4.6)]

    var body: some View {
        TimelineView(.animation(paused: !moving || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Ellipse().stroke(Color.white.opacity(0.10), lineWidth: 1).frame(width: 270, height: 112)
                ForEach(0..<Self.moons.count, id: \.self) { i in
                    let m = Self.moons[i]
                    let a = (moving && !reduceMotion ? t * m.speed : 0) + m.phase
                    Circle()
                        .fill(RadialGradient(colors: LensMoon.palette(m.tone).map { Color(hex: $0) }, center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: m.size))
                        .frame(width: m.size, height: m.size)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
                        .offset(x: 135 * CGFloat(cos(a)), y: 56 * CGFloat(sin(a)))
                        .zIndex(sin(a) < 0 ? -1 : 1)   // behind the moon on the far side of the orbit
                }
                Moon(size: 140, rings: false).zIndex(0)
            }
            .frame(width: 300, height: 220)
        }
        .accessibilityHidden(true)
    }
}

/// The round Stop button: its ring fills as the scan gets through the disk.
struct StopRing: View {
    let fraction: Double
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Theme.barTrack, lineWidth: 4)
                Circle().trim(from: 0, to: max(0.02, fraction)).stroke(Theme.accentLight, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: fraction)
                Text("Stop").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    .frame(width: 70, height: 70).background(Circle().fill(Theme.tintStrong))
            }
            .frame(width: 82, height: 82)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop measuring")
    }
}

/// The big round action button (Scan, Remove), a clay pill turned into a disc.
struct RoundButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 86, height: 86)
                .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x6A9A79), Color(hex: 0x4A7357)], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .white.opacity(0.35), radius: 3, x: 1, y: 2))))
                .shadow(color: .black.opacity(enabled ? 0.35 : 0.1), radius: 10, y: 6)
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
