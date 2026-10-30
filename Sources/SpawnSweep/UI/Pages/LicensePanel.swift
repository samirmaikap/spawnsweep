import SwiftUI
import AppKit

/// Settings › SpawnSweep Pro: enter a Dodo Payments license, see its status, or remove it from this Mac.
struct LicensePanel: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    /// Skips the feature list (the Pro page shows its own); adds a link to it from Settings.
    var compact = false

    var body: some View {
        let lic = model.license
        Panel(title: compact && !lic.isPro ? "Already have a license key?" : "SpawnSweep Pro", boxed: true, trailing: {
            HStack(spacing: 8) {
                if License.environment == .test { Badge(text: "Test mode", style: .warning) }
                if lic.isPro { Badge(text: "Pro", style: .success, symbol: "checkmark.seal.fill") }
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                if let r = lic.record, lic.isPro { active(r, lic) } else { locked(lic) }
                if let m = lic.message { WarningBanner(text: m) }
            }
        }
    }

    // MARK: - Free

    private func locked(_ lic: LicenseStore) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !compact { HStack(alignment: .top, spacing: 16) {
                IconTile(symbol: "sparkles", size: 52, tone: .mint)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Let Autopilot do the putting away.").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    perk("bell.badge", "Ask first: a notification, then one click to review")
                    perk("bolt", "Automatic: rules act on their own and log a way back")
                    perk("clock", "End of day, battery and low-disk rules that run themselves")
                }
            } }
            HStack(spacing: 10) {
                // Cleaned as it comes in: a pasted "KEY⏎⏎" would otherwise show only its empty last line.
                TextField("License key from your Dodo Payments email", text: Binding(get: { key }, set: { key = License.cleanKey($0) }))
                    .textFieldStyle(.plain).font(.mono(13))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .clayInset(radius: 12)
                    .onSubmit { lic.activate(key) }
                    .disabled(lic.busy)
                Button { lic.activate(key) } label: {
                    HStack(spacing: 6) {
                        if lic.busy { ProgressView().controlSize(.small) }
                        Text(lic.busy ? "Activating…" : "Activate")
                    }
                }
                .buttonStyle(.primary)
                .disabled(lic.busy || key.isEmpty)
                Button { if let url = License.checkoutURL { NSWorkspace.shared.open(url) } } label: {
                    Label("Get a key", systemImage: "cart")
                }
                .buttonStyle(.quiet)
                .disabled(License.checkoutURL == nil)
                .help(License.checkoutURL == nil ? "Checkout opens when Pro goes on sale." : "Buy SpawnSweep Pro. Your key arrives by email.")
            }
            HStack(spacing: 14) {
                if model.page != .pro { NavLink(title: "See what's in Pro") { model.go(.pro) } }
                Text("Everything else in SpawnSweep stays free.").font(.meta).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func perk(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 13)).foregroundStyle(Theme.secondary)
    }

    // MARK: - Pro

    private func active(_ r: License.Record, _ lic: LicenseStore) -> some View {
        let offline = Date().timeIntervalSince(r.lastValidated) > License.recheckInterval
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                IconTile(symbol: "checkmark.seal.fill", size: 52, tone: .mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pro is on for this Mac.").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text([r.email, "Key ending \(r.key.suffix(4))", License.machineName].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Text(offline ? "Couldn't confirm with Dodo since \(Fmt.date(r.lastValidated)). Pro stays on until \(Fmt.date(License.graceEnds(r)))."
                                 : "Confirmed \(Fmt.ago(r.lastValidated)). Checked again weekly.")
                        .font(.system(size: 12)).foregroundStyle(offline ? Theme.amberText : Theme.secondary)
                }
            }
            HStack(spacing: 10) {
                Button { lic.recheckIfDue(force: true) } label: {
                    HStack(spacing: 6) { if lic.busy { ProgressView().controlSize(.small) }; Text("Check now") }
                }
                .buttonStyle(.quiet).disabled(lic.busy)
                Button("Remove from this Mac") { lic.deactivate() }
                    .buttonStyle(QuietButtonStyle(destructive: true)).disabled(lic.busy)
                    .help("Frees this Mac's slot so the license can be used on another Mac.")
            }
        }
    }
}
