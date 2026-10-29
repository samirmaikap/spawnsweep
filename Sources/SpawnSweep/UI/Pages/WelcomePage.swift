import SwiftUI

/// Onboarding: choose folders, optionally connect an agent and allow notifications, then explore.
struct WelcomePage: View {
    @Environment(AppModel.self) private var model
    @State private var notifications: Bool?   // nil until asked; the answer only arrives after a request

    var body: some View {
        let folders = model.prefs.devFolders
        let connected = [Agent.claudeCode, .codex, .cursor, .claudeApp, .gemini].contains {
            if case .connected = Integrations.status(of: $0) { return true }
            return false
        }

        PageScroll {
            PageHeader(title: "A softer landing for your Mac.", subtitle: "A few permissions. Then a clear view of what's running.")

            VStack(spacing: 12) {
                Moon(size: 110, rings: false).padding(.bottom, 18)
                Text("Your code stays yours.").heading(24)
                Text("SpawnSweep finds agent leftovers locally. Every cleanup starts with a preview.")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .clay(radius: 30, fill: Theme.heroGradient)

            Panel(title: "Set up your workspace") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 236), spacing: 16, alignment: .top)], spacing: 16) {
                    ResourceRow(symbol: "folder", title: "Choose your development folders",
                                subtitle: folders.isEmpty ? "Allow access only to folders you select."
                                    : "\(folders.count) folder\(folders.count == 1 ? "" : "s") chosen: "
                                        + folders.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")) {
                        folders.isEmpty ? Badge(text: "Required") : Badge(text: "Chosen", style: .success)
                        Button("Add folders") { model.chooseDevFolders() }.buttonStyle(.quiet)
                    }
                    ResourceRow(symbol: "terminal", title: "Connect your first agent",
                                subtitle: "Start with Claude Code, Codex, or Cursor.") {
                        connected ? Badge(text: "Connected", style: .success) : Badge(text: "Optional")
                        Button("Connect") { model.go(.connections) }.buttonStyle(.quiet).accessibilityLabel("Connect an agent")
                    }
                    ResourceRow(symbol: "bell", title: "Enable notifications", subtitle: notificationText) {
                        switch notifications {
                        case nil: Badge(text: "Optional")
                        case true?: Badge(text: "On", style: .success)
                        case false?: Badge(text: "Off")
                        }
                        Button("Enable") { Notifier.shared.requestPermission { notifications = $0 } }
                            .buttonStyle(.quiet)
                            .disabled(notifications == true)
                            .accessibilityLabel("Enable notifications")
                    }
                }
                .environment(\.rowLayout, .tile)
            }

            Button("Explore workspace") {
                model.prefs.onboarded = true
                model.go(.sessions)
                model.refreshDisk()
            }
            .buttonStyle(.primaryLarge)
        }
    }

    private var notificationText: String {
        switch notifications {
        case nil: return "Review idle resources without opening the app."
        case true?: return "You'll get a Review or Keep choice when a finished session leaves things running."
        case false?: return "Notifications are off. Turn them on in System Settings › Notifications."
        }
    }
}
