import Foundation
import AppKit
import Security

/// SpawnSweep Pro, licensed through Dodo Payments. Activate, validate and deactivate are public Dodo endpoints,
/// so the app talks to Dodo directly and ships no secret. The key and this Mac's activation live in the Keychain.
enum License {
    enum Environment: String, Codable {
        case test, live
        var base: URL { URL(string: self == .test ? "https://test.dodopayments.com" : "https://live.dodopayments.com")! }
    }

    /// Live: real purchases and keys. Switch to .test (with Dodo's test cards) to try changes to licensing.
    static let environment = Environment.live
    /// Dodo checkout for SpawnSweep Pro ($9, license key, 3 Macs), under the SpawnSweep brand.
    static var checkoutURL: URL? {
        switch environment {
        case .test: return URL(string: "https://test.checkout.dodopayments.com/buy/pdt_0Nqn0spYBPpXDKtw9rcTG?quantity=1")
        case .live: return URL(string: "https://checkout.dodopayments.com/buy/pdt_0Nqn3fOmfcDQwcQysr6t5?quantity=1")
        }
    }
    static let repoURL = URL(string: "https://github.com/samirmaikap/spawnsweep")!

    /// Re-check with Dodo once a week; if Dodo can't be reached, Pro keeps working for two more weeks.
    static let recheckInterval: TimeInterval = 7 * 86400
    static let offlineGrace: TimeInterval = 14 * 86400
    /// While a re-check keeps failing (offline), try again at most once a day.
    static let retryInterval: TimeInterval = 86400

    struct Record: Codable, Equatable {
        var key: String
        var instanceID: String
        var environment: Environment
        var email: String?
        var activatedAt: Date
        /// Last time Dodo said the license is valid.
        var lastValidated: Date
        /// Last time we tried to ask.
        var lastChecked: Date
    }

    // MARK: - Rules (pure, covered by --selftest)

    /// Pro while Dodo confirmed the license within the last week plus the offline grace.
    static func isPro(_ r: Record?, now: Date) -> Bool {
        guard let r, r.environment == environment else { return false }
        return now.timeIntervalSince(r.lastValidated) <= recheckInterval + offlineGrace
    }

    /// When the grace runs out if Dodo stays unreachable.
    static func graceEnds(_ r: Record) -> Date { r.lastValidated.addingTimeInterval(recheckInterval + offlineGrace) }

    /// A week since the last confirmation, and no attempt in the last day.
    static func needsCheck(_ r: Record, now: Date) -> Bool {
        now.timeIntervalSince(r.lastValidated) >= recheckInterval && now.timeIntervalSince(r.lastChecked) >= retryInterval
    }

    enum Verdict: Equatable { case valid, invalid, unreachable }

    /// Maps a validate response: 2xx {"valid": true} is valid; any other answer from Dodo means no;
    /// server errors and no answer mean "try again later" (Pro stays on during the grace).
    static func verdict(status: Int?, body: Data?) -> Verdict {
        guard let status else { return .unreachable }
        if status >= 500 { return .unreachable }
        guard (200..<300).contains(status) else { return .invalid }
        struct V: Decodable { let valid: Bool }
        guard let body, let v = try? JSONDecoder().decode(V.self, from: body) else { return .unreachable }
        return v.valid ? .valid : .invalid
    }

    /// A license key has no spaces or line breaks; drop the ones that come along when it's copied from an email.
    static func cleanKey(_ s: String) -> String { s.filter { !$0.isWhitespace } }

    /// Plain words for an activation that Dodo refused.
    static func activationError(status: Int?) -> String {
        switch status {
        case nil: return "Couldn't reach Dodo Payments. Check your connection and try again."
        case 403?: return "This license isn't active. If you were refunded or it expired, buy a new one."
        case 404?: return "That license key wasn't found. Check it against the email from Dodo Payments."
        case 422?: return "This license is already on its maximum number of Macs. Remove it from another Mac first."
        default: return "Dodo Payments couldn't activate the license right now. Try again in a minute."
        }
    }

    // MARK: - Dodo calls

    struct Activation: Decodable {
        struct Customer: Decodable { let email: String? }
        let id: String
        let customer: Customer?
    }

    private static func post(_ path: String, _ body: [String: String]) async -> (status: Int?, data: Data?) {
        var req = URLRequest(url: environment.base.appendingPathComponent(path), timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return (nil, nil) }
        return ((resp as? HTTPURLResponse)?.statusCode, data)
    }

    struct Refused: Error { let message: String }

    static func activate(key: String, machine: String) async -> Result<Record, Refused> {
        let r = await post("licenses/activate", ["license_key": key, "name": machine])
        guard let status = r.status, (200..<300).contains(status), let data = r.data,
              let a = try? JSONDecoder().decode(Activation.self, from: data) else {
            return .failure(Refused(message: activationError(status: r.status)))
        }
        let now = Date()
        return .success(Record(key: key, instanceID: a.id, environment: environment, email: a.customer?.email,
                               activatedAt: now, lastValidated: now, lastChecked: now))
    }

    static func validate(_ r: Record) async -> Verdict {
        let res = await post("licenses/validate", ["license_key": r.key, "license_key_instance_id": r.instanceID])
        return verdict(status: res.status, body: res.data)
    }

    /// Frees this Mac's slot. Returns false only when Dodo couldn't be reached (the local license is removed anyway).
    static func deactivate(_ r: Record) async -> Bool {
        let res = await post("licenses/deactivate", ["license_key": r.key, "license_key_instance_id": r.instanceID])
        return res.status != nil && res.status! < 500
    }

    // MARK: - Keychain

    private static let service = "app.spawnsweep.mac.license"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pro"]
    }

    static func loadRecord() -> Record? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(Record.self, from: data)
    }

    static func saveRecord(_ r: Record?) {
        SecItemDelete(query as CFDictionary)
        guard let r else { return }
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(r) else { return }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        q[kSecAttrLabel as String] = "SpawnSweep Pro license"
        SecItemAdd(q as CFDictionary, nil)
    }

    static var machineName: String { Host.current().localizedName ?? ProcessInfo.processInfo.hostName }
}

/// What the UI reads: the stored license, whether Pro is on, and what's happening right now.
@MainActor @Observable
final class LicenseStore {
    private(set) var record: License.Record?
    var busy = false
    /// The last thing worth telling the person (an activation error, a lapsed license).
    var message: String?

    var isPro: Bool { License.isPro(record, now: Date()) }

    func load() {
        record = License.loadRecord()
        // A key from the other Dodo mode (e.g. a test purchase) can't unlock this build; clear it and say why.
        if let r = record, r.environment != License.environment {
            set(nil)
            message = "This Mac had a \(r.environment == .test ? "test-mode" : "live") key, which doesn't work here. Activate a \(License.environment == .live ? "real" : "test") SpawnSweep Pro key to turn Pro on."
        }
    }

    func activate(_ raw: String) {
        let key = License.cleanKey(raw)
        guard !key.isEmpty, !busy else { return }
        busy = true; message = nil
        Task {
            let result = await License.activate(key: key, machine: License.machineName)
            busy = false
            switch result {
            case .success(let r): set(r)
            case .failure(let why): message = why.message
            }
        }
    }

    /// Removes the license from this Mac and frees its slot at Dodo.
    func deactivate() {
        guard let r = record, !busy else { return }
        busy = true; message = nil
        Task {
            let reached = await License.deactivate(r)
            busy = false
            set(nil)
            if !reached { message = "Removed from this Mac. Dodo couldn't be reached, so the slot may stay used until it's freed from your Dodo customer portal." }
        }
    }

    /// Called on every scan tick; only goes to the network when a check is due (or `force`).
    func recheckIfDue(force: Bool = false) {
        guard let r = record, !busy, force || License.needsCheck(r, now: Date()) else { return }
        busy = true
        Task {
            let verdict = await License.validate(r)
            busy = false
            guard var cur = record, cur.key == r.key else { return }
            cur.lastChecked = Date()
            switch verdict {
            case .valid:
                cur.lastValidated = Date(); message = nil; set(cur)
            case .unreachable:
                set(cur)
                if force { message = "Couldn't reach Dodo Payments. Pro stays on until \(Fmt.date(License.graceEnds(cur)))." }
            case .invalid:
                set(nil)
                message = "This license is no longer active on this Mac. Autopilot rules that ask or act now preview only."
            }
        }
    }

    private func set(_ r: License.Record?) {
        record = r
        License.saveRecord(r)
    }
}
