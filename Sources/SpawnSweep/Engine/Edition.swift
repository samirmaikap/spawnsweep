import Foundation

/// What SpawnSweep Pro adds, as seen from the public code. The official build compiles in `Sources/SpawnSweep/Pro`
/// (the private `samirmaikap/spawnsweep-pro` repo), whose `@objc(SpawnSweepProFeatures)` class conforms to this.
/// A build from the public repo alone has no such class, so `Edition.pro` is nil and the app is the free edition.
protocol ProFeatures: AnyObject, Sendable {
    init()
    func findJunk() -> [JunkCategory]
    func cleanJunk(_ picks: [(String, JunkItem)]) -> (Actions.Outcome, Set<String>)
    func findLargeFiles(minBytes: Int64) -> [LargeFile]
    func trash(_ files: [LargeFile]) -> Actions.Outcome
    /// `rules` are those whose effective mode is .ask or .auto, with their fresh matches.
    @MainActor func act(_ model: AppModel, _ rules: [(Rule, [RuleMatch])])
    /// Space Lens: measures the whole disk once. Blocks until done or `scan` is cancelled, so call it off the main thread.
    func lensMap(scan: LensScan, progress: @escaping @Sendable (LensProgress) -> Void) -> LensMap
    /// Space Lens: one folder's contents, sized from `map` (or measured now if the scan didn't go that deep) and classified.
    func lensLevel(_ path: String, map: LensMap, scan: LensScan) -> [LensNode]
    func selfTest()
}

enum Edition {
    /// Looked up by Objective-C runtime name, so no build setting or file check decides the edition.
    static let pro: ProFeatures? = (NSClassFromString("SpawnSweepProFeatures") as? ProFeatures.Type)?.init()
    static var hasPro: Bool { pro != nil }
}
