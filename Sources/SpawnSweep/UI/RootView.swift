import SwiftUI

/// Main window: glass sidebar, page content, and a blurred backdrop under dialogs.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: 236)
                ZStack(alignment: .topTrailing) {
                    Canvas()
                    page
                        .transition(.opacity)
                        .id(model.page)
                    PaletteHint()
                        .padding(.top, 30).padding(.trailing, 32)
                }
            }
            .blur(radius: model.dialog != nil || model.paletteOpen ? 14 : 0)
            .allowsHitTesting(model.dialog == nil && !model.paletteOpen)

            if model.dialog != nil {
                Color.black.opacity(0.12).ignoresSafeArea()
                    .onTapGesture { if case .running = model.dialog?.phase {} else { model.dismissDialog() } }
                DialogView()
                    .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
            if model.paletteOpen {
                Color.black.opacity(0.10).ignoresSafeArea().onTapGesture { model.paletteOpen = false }
                CommandPalette()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.dialog?.id)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.paletteOpen)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: model.page)
        .background(Theme.bg)
        .ignoresSafeArea()
        .frame(minWidth: 1040, minHeight: 720)
        .onKeyPress(.escape) {
            if model.paletteOpen { model.paletteOpen = false; return .handled }
            if model.dialog != nil { model.dismissDialog(); return .handled }
            return .ignored
        }
        .background(
            Button("") { model.paletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
        )
    }

    @ViewBuilder private var page: some View {
        switch model.page {
        case .sessions:
            if let folder = model.sessionDetail { SessionDetailPage(folder: folder) } else { SessionsPage() }
        case .ports: PortsPage()
        case .resources: ResourcesPage()
        case .mac: MacOverviewPage()
        case .junk: JunkPage()
        case .largeFiles: LargeFilesPage()
        case .storage:
            if let repo = model.repoDetail { WorktreeDetailPage(repoPath: repo) } else { StoragePage() }
        case .recycle: RecyclePage()
        case .autopilot: AutopilotPage()
        case .connections: ConnectionsPage()
        case .safety: SafetyPage()
        case .activity: ActivityPage()
        case .settings: SettingsPage()
        case .welcome: WelcomePage()
        case .pro: ProPage()
        }
    }
}

struct PaletteHint: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { model.paletteOpen = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                Text("⌘ K")
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .clay(radius: 12, glass: true)
        }
        .buttonStyle(.plain)
        .help("Find a project, port, or session")
    }
}

/// Glass sidebar: brand, grouped sections of large clay icons, Settings pinned at the bottom.
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppMark(size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("SpawnSweep").font(.display(19)).tracking(-0.4).foregroundStyle(Theme.text)
                        if model.license.isPro { ProPill() }
                    }
                    Text("On your Mac. Only.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.leading, 20)
            .padding(.top, 46)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Page.sections, id: \.0) { title, pages in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(1.4)
                                .foregroundStyle(Theme.secondary.opacity(0.85))
                                .padding(.leading, 22).padding(.bottom, 4)
                            ForEach(pages) { p in SidebarItem(page: p, selected: model.page.sidebarPage == p) }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            if Edition.hasPro && !model.license.isPro { SidebarProCard().padding(.top, 6) }
            SidebarItem(page: .settings, selected: model.page == .settings)
                .padding(.bottom, 18).padding(.top, 6)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                VisualEffect(material: .sidebar)
                LinearGradient(colors: [Theme.sidebar.opacity(0.35), Theme.sidebar.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            }
        }
        .overlay(alignment: .trailing) {
            LinearGradient(colors: [Theme.clayHighlight.opacity(0.6), Theme.border.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                .frame(width: 1)
        }
    }
}

struct SidebarItem: View {
    @Environment(AppModel.self) private var model
    let page: Page
    let selected: Bool
    @State private var hover = false

    private var count: (Int, Bool)? {
        switch page {
        case .sessions: let n = model.attentionSessions.count; return n > 0 ? (n, true) : nil
        case .ports: let n = model.workspace.servers.count; return n > 0 ? (n, false) : nil
        case .recycle: return model.bin.isEmpty ? nil : (model.bin.count, false)
        default: return nil
        }
    }

    var body: some View {
        Button { model.go(page) } label: {
            HStack(spacing: 12) {
                IconTile(symbol: page.symbol, size: 30, tone: page.tone)
                Text(page.title).font(.system(size: 14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.text : Theme.text.opacity(0.8))
                Spacer(minLength: 4)
                if [.mac, .autopilot].contains(page) && !model.license.isPro { ProPill() }
                if let (n, alert) = count {
                    Text("\(n)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(alert ? Theme.amberText : Theme.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(alert ? Theme.amberFill : Theme.tint))
                }
            }
            .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 4)
            .background {
                if selected {
                    ClayBackground(radius: 16, fill: AnyShapeStyle(Theme.surface), glass: false)
                } else if hover {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface.opacity(0.4))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
