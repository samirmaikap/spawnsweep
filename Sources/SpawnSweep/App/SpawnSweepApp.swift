import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement
import Carbon.HIToolbox

/// The binary is the app and two helpers: `--session-end` (agent hook) and `--mcp` (MCP server for agents).
@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--session-end") { CLI.sessionEnd(); return }
        if args.contains("--mcp") { CLI.mcp(); return }
        if args.contains("--scan") { CLI.printScan(); return }
        if args.contains("--selftest") { CLI.selfTest(); return }
        if args.contains("--lens") { CLI.printLens(); return }
        if args.contains("--edition") { print(Edition.hasPro ? "pro" : "free"); return }
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count { IconRenderer.render(to: args[i + 1]); return }
        SpawnSweepApp.main()
    }
}

struct SpawnSweepApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("SpawnSweep", id: "main") {
            RootView()
                .environment(model)
                .onAppear {
                    delegate.model = model
                    model.start()
                    applyAppearance(model.prefs.appearance)
                    if !model.prefs.onboarded { model.go(.welcome) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1180, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rescan") { model.refresh(withStats: true); model.refreshDisk() }.keyboardShortcut("r")
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
                .onAppear { model.start() }
        } label: {
            let n = model.attentionSessions.count
            Image(nsImage: MenuBarIcon.image)
            if n > 0 { Text("\(n)") }
        }
        .menuBarExtraStyle(.window)
    }
}

func applyAppearance(_ value: String) {
    switch value {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
    default: NSApp.appearance = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var hotKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerHotKey()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// ⌘⇧L from anywhere: bring the window forward with the command palette open.
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                guard let d = NSApp.delegate as? AppDelegate, let model = d.model else { return }
                MainActor.assumeIsolated {
                    model.openMainWindow()
                    model.paletteOpen = true
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4C4F5554), id: 1)   // 'LOUT'
        RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
}

// MARK: - Login item

enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { NSLog("SpawnSweep login item: \(error)") }
    }
}

// MARK: - Notifications

/// Actionable alerts: Review opens the end-of-day sweep; Keep snoozes for a day.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    weak var model: AppModel?
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func setUp(model: AppModel) {
        self.model = model
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let review = UNNotificationAction(identifier: "REVIEW", title: "Review", options: [.foreground])
        let keep = UNNotificationAction(identifier: "KEEP", title: "Keep", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "LEFTOVERS", actions: [review, keep], intentIdentifiers: [])])
    }

    func requestPermission(_ done: @escaping (Bool) -> Void = { _ in }) {
        guard available else { done(false); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    /// `rule` routes Review to that rule's Run now preview instead of the end-of-day sweep.
    func post(id: String, title: String, body: String, actionable: Bool, rule: UUID? = nil) {
        guard available else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        if let rule { c.userInfo = ["rule": rule.uuidString] }
        if actionable { c.categoryIdentifier = "LEFTOVERS" }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler done: @escaping () -> Void) {
        let action = response.actionIdentifier
        let ruleID = (response.notification.request.content.userInfo["rule"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor in
            guard let model = self.model else { done(); return }
            if let ruleID {
                if action == "KEEP" {
                    model.prefs.snoozedUntil["rule:\(ruleID)"] = Date().addingTimeInterval(86400)
                } else if let rule = model.prefs.rules.first(where: { $0.id == ruleID }) {
                    model.openMainWindow()
                    model.go(.autopilot)
                    model.runNow(rule, force: false)
                }
            } else if action == "KEEP" {
                model.prefs.snoozedUntil["ended"] = Date().addingTimeInterval(86400)
            } else {
                model.openMainWindow()
                model.go(.sessions)
                model.reviewSweep()
            }
            done()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
