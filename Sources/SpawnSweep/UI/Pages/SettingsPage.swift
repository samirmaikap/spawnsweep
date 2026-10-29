import SwiftUI
import AppKit

/// Persistent preferences: switches for settings, buttons only for immediate actions.
struct SettingsPage: View {
    @Environment(AppModel.self) private var model
    @State private var loginOn = LoginItem.isOn
    @State private var loginRefused = false

    var body: some View {
        @Bindable var model = model
        let custom = model.prefs.devFolders
        let folders = custom.isEmpty ? DiskScanner.defaultDevFolders() : custom
        let appearance = model.prefs.appearance

        PageScroll {
            PageHeader(title: "Make yourself at home.", subtitle: "Small preferences for a quieter development day.")

            if Edition.hasPro { LicensePanel(compact: true) }

            Panel(title: "General") {
                TileGrid {
                    Tile(symbol: "power", title: "Launch at login",
                         subtitle: loginRefused ? "macOS didn't allow it. Check System Settings › General › Login Items."
                                                : "Keep an eye on leftovers from the menu bar.") {
                        Switch(label: "Launch at login", isOn: Binding(get: { loginOn }, set: { on in
                            LoginItem.set(on)
                            loginOn = LoginItem.isOn
                            loginRefused = on && !loginOn
                        }))
                    }
                    Tile(symbol: "circle.lefthalf.filled", title: "Appearance",
                         subtitle: appearance == "light" ? "Always light." : appearance == "dark" ? "Always dark." : "Follow your Mac's light and dark appearance.") {
                        ClayPicker(title: "Appearance",
                                   selection: Binding(get: { model.prefs.appearance.lowercased() }, set: { v in
                                       model.prefs.appearance = v
                                       applyAppearance(v)
                                   }),
                                   options: [("system", "System"), ("light", "Light"), ("dark", "Dark")])
                    }
                    Tile(symbol: "command", title: "Command palette", subtitle: "Find a project, port, or session from anywhere.") {
                        Text("⌘ ⇧ L").font(.system(size: 13)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
                            .accessibilityLabel("Shortcut: Command Shift L")
                    }
                }
            }

            Panel(title: "Safety & privacy") {
                VStack(spacing: 14) {
                    TileGrid {
                        Tile(symbol: "eye", title: "Always preview actions", subtitle: "Review resources before anything is stopped.") {
                            Badge(text: "Always on", style: .success)
                        }
                        Tile(symbol: "pin", title: "Protected list", subtitle: "Pinned sessions and protected ports you've chosen to keep.") {
                            Button("Manage") { model.go(.safety) }.buttonStyle(.quiet).accessibilityLabel("Manage protected list")
                        }
                        Tile(symbol: "clock.arrow.circlepath", title: "Local activity history", subtitle: "Keep an on-device record of actions.") {
                            ClayPicker(title: "Local activity history", selection: $model.prefs.historyDays,
                                       options: ([7, 30, 90].contains(model.prefs.historyDays) ? [7, 30, 90] : [7, 30, 90, model.prefs.historyDays].sorted())
                                           .map { ($0, "\($0) days") })
                        }
                    }
                    // Long content: its own full-width card below the grid.
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            IconTile(symbol: "folder", size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Development folders").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                                Text(custom.isEmpty ? "SpawnSweep looks for repositories in these folders by default."
                                                    : "SpawnSweep looks for repositories only in the folders you chose.")
                                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 16)
                            Button("Add folders") { model.chooseDevFolders() }.buttonStyle(.quiet)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            if folders.isEmpty {
                                Text("No default folders found. Choose where your projects live.")
                                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            }
                            ForEach(folders, id: \.self) { f in
                                HStack {
                                    Text((f as NSString).abbreviatingWithTildeInPath).font(.mono(12)).foregroundStyle(Theme.text)
                                        .textSelection(.enabled)
                                    Spacer()
                                    if folders.count > 1 {
                                        Button { model.removeDevFolder(f) } label: { Image(systemName: "minus.circle") }
                                            .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                                            .help("Stop looking in this folder")
                                            .accessibilityLabel("Remove \((f as NSString).lastPathComponent)")
                                    }
                                }
                            }
                            if model.diskScanning {
                                Text("Scanning…").font(.meta).foregroundStyle(Theme.secondary).padding(.top, 4)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clayInset(radius: 14)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clay(radius: 20, glass: false)
                }
            }

            Panel(title: "Notifications") {
                TileGrid {
                    Tile(symbol: "bell.badge", title: "Actionable alerts", subtitle: "Get a Review or Keep choice when a finished session leaves things running.") {
                        Switch(label: "Actionable alerts", isOn: $model.prefs.actionableAlerts)
                    }
                    Tile(symbol: "gauge.with.dots.needle.67percent", title: "Budget warnings", subtitle: "Know when simulators or worktree storage exceed a budget.") {
                        Switch(label: "Budget warnings", isOn: $model.prefs.budgetWarnings)
                    }
                }
            }

            AboutPanel()

            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield")
                Text(Edition.hasPro ? "Local only. No telemetry. No account required. The only network call checks a Pro license with Dodo Payments."
                                    : "Local only. No telemetry. No account required. This build makes no network calls.")
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.secondary)
        }
        .onAppear { loginOn = LoginItem.isOn }
    }
}

extension AppModel {
    /// Asks which folders hold projects, saves them, and rescans disk. Used by Settings and Welcome.
    func chooseDevFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.message = "Choose the folders where your projects live. SpawnSweep only looks inside these."
        panel.directoryURL = URL(fileURLWithPath: Shell.home)
        panel.prompt = "Add"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        // Add to what's there (starting from the defaults if none were chosen yet), skipping duplicates.
        var folders = prefs.devFolders.isEmpty ? DiskScanner.defaultDevFolders() : prefs.devFolders
        for p in panel.urls.map(\.path) where !folders.contains(p) { folders.append(p) }
        prefs.devFolders = folders
        refreshDisk()
    }

    func removeDevFolder(_ path: String) {
        var folders = prefs.devFolders.isEmpty ? DiskScanner.defaultDevFolders() : prefs.devFolders
        folders.removeAll { $0 == path }
        prefs.devFolders = folders
        refreshDisk()
    }
}

// MARK: - Tiles

/// Version, source code, and Pro as the way to support the app.
private struct AboutPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Panel(title: "About", boxed: true) {
            HStack(alignment: .center, spacing: 16) {
                AppMark(size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SpawnSweep \(version)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(Edition.hasPro ? "Free and open source. Pro unlocks cleaning and automation."
                                        : "Free edition, built from source. SpawnSweep Pro comes with the official download.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { NSWorkspace.shared.open(License.repoURL) } label: { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                    .buttonStyle(.quiet)
                if !Edition.hasPro {
                    Button { NSWorkspace.shared.open(URL(string: "https://github.com/samirmaikap/spawnsweep/releases")!) } label: { Label("Official download", systemImage: "arrow.down.circle") }
                        .buttonStyle(.primary)
                } else if !model.license.isPro {
                    // Pro is the one way to support the app.
                    Button { model.go(.pro) } label: { Label("Get Pro", systemImage: "crown.fill") }
                        .buttonStyle(.primary)
                }
            }
        }
    }
}

private struct TileGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14, content: content)
    }
}

/// One setting: a clay tile with its icon and control on top, then title and description.
private struct Tile<Control: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                IconTile(symbol: symbol, size: 40)
                Spacer(minLength: 12)
                control()
            }
            .padding(.bottom, 10)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)   // ponytail: min height evens rows; LazyVGrid won't stretch cells
        .clay(radius: 20, glass: false)
    }
}

/// Switch followed by a quiet On/Off label, as in the mockup.
private struct Switch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle(label, isOn: $isOn).toggleStyle(.switch).tint(Theme.accent).labelsHidden()
            Text(isOn ? "On" : "Off").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                .frame(width: 24, alignment: .leading)
                .accessibilityHidden(true)
        }
    }
}
