import SwiftUI
import AppKit

// MARK: - Colors (Design guidelines §1)

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// A color that follows light and dark appearance.
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        })
    }
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

enum Theme {
    static let bg = Color(light: 0xF2F6EF, dark: 0x1C2821)
    static let sidebar = Color(light: 0xE6EDE3, dark: 0x2B3B30)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A392F)
    static let text = Color(light: 0x263A30, dark: 0xE5EEE9)
    static let secondary = Color(light: 0x6E7D72, dark: 0xA5B7AB)
    static let border = Color(light: 0xDFE6DB, dark: 0x46594A)
    /// Emerald primary. Bright fills take dark ink labels: white on this green is only 3.4:1.
    static let accent = Color(hex: 0x0E9F5B)
    static let accentLight = Color(hex: 0x2CC97A)
    static let onAccent = Color(hex: 0x0F2418)
    /// The primary as text or a glyph: links, checkmarks, icons on tints. Readable on every surface (4.8:1 or more).
    static let accentText = Color(light: 0x08703F, dark: 0x5BE3A0)

    /// Soft sage fill for neutral badges, info banners and segmented tracks.
    static let tint = Color(light: 0xE7EEE3, dark: 0x33463A)
    static let tintStrong = Color(light: 0xDCE6D6, dark: 0x3A4F40)
    static let activeText = Color(light: 0x08703F, dark: 0x5BE3A0)
    static let amberFill = Color(light: 0xF6E8D9, dark: 0x4A3B26)
    static let amberText = Color(light: 0x8E5527, dark: 0xEBC395)
    static let warningFill = Color(light: 0xF5EADF, dark: 0x45382A)
    static let destructive = Color(nsColor: .systemRed)

    /// Clay depth: a soft colored drop shadow, a bright upper-left edge and a darker lower-right edge.
    static let clayShadow = Color(light: 0x6F8C74, dark: 0x000000, lightAlpha: 0.22, darkAlpha: 0.45)
    static let clayHighlight = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.9, darkAlpha: 0.10)
    static let clayShade = Color(light: 0x5C7A62, dark: 0x000000, lightAlpha: 0.14, darkAlpha: 0.45)
    /// Glass on clay: a thin bright rim and a soft sheen across the top of translucent cards.
    static let glassRim = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.55, darkAlpha: 0.16)
    static let glassSheen = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.35, darkAlpha: 0.10)

    /// Soft color fields behind the content, so the glass has something to pick up.
    /// Storage bars: the empty track reads as a recessed slot, "everything else" as a solid neutral.
    static let barTrack = Color(light: 0xDCE5D6, dark: 0x16211A)
    static let barNeutral = Color(light: 0x93A697, dark: 0x6F8574)

    static let blobMint = Color(light: 0xD3EBDC, dark: 0x294334)
    static let blobSky = Color(light: 0xDCE8F4, dark: 0x25384A)
    static let blobSand = Color(light: 0xF2EAD8, dark: 0x3A3426)

    static let heroGradient = LinearGradient(
        colors: [Color(light: 0xD7E6CB, dark: 0x3E5848), Color(light: 0xF1F6EC, dark: 0x2C3D31)],
        startPoint: .topTrailing, endPoint: .bottomLeading)
}

/// Pastel clay palette for large icons: a fill and a matching glyph color.
struct ClayTone: Equatable {
    let fill: Color
    let glyph: Color

    static let sage = ClayTone(fill: Color(light: 0xDCE9D5, dark: 0x3A5242), glyph: Color(light: 0x4C7A5A, dark: 0xA8D3B4))
    static let mint = ClayTone(fill: Color(light: 0xD2EDE0, dark: 0x2F5145), glyph: Color(light: 0x357A62, dark: 0x9BDCC4))
    static let sky = ClayTone(fill: Color(light: 0xD8E6F6, dark: 0x2E4559), glyph: Color(light: 0x3C6A96, dark: 0xA9CBEB))
    static let sand = ClayTone(fill: Color(light: 0xF2E6CC, dark: 0x4E4532), glyph: Color(light: 0x8A6A2A, dark: 0xE6CC94))
    static let peach = ClayTone(fill: Color(light: 0xF6DDD1, dark: 0x51392F), glyph: Color(light: 0x9A533C, dark: 0xF0B7A1))
    static let lilac = ClayTone(fill: Color(light: 0xE4DDF6, dark: 0x41395A), glyph: Color(light: 0x6555A2, dark: 0xC5B8F0))

    /// A tone for common symbols, so the same kind of thing always has the same color.
    static func forSymbol(_ s: String) -> ClayTone {
        if s.contains("branch") { return .sand }
        if s.contains("iphone") || s.contains("ipad") { return .lilac }
        if s.contains("shippingbox") || s.contains("cube") { return .sky }
        if s.contains("eye") || s.contains("sparkles") || s.contains("leaf") { return .mint }
        if s.contains("globe") || s.contains("antenna") || s.contains("network") || s.contains("point.3") { return .sky }
        if s.contains("archivebox") || s.contains("trash") || s.contains("exclamation") { return .peach }
        if s.contains("doc") || s.contains("internaldrive") || s.contains("folder") { return .sand }
        if s.contains("bubble") || s.contains("cursorarrow") { return .lilac }
        return .sage
    }
}

extension Page {
    var tone: ClayTone {
        switch self {
        case .sessions, .safety, .welcome: return .sage
        case .ports, .connections: return .sky
        case .resources, .settings: return .lilac
        case .mac: return .sky
        case .junk: return .peach
        case .largeFiles: return .sand
        case .spaceLens: return .sky
        case .pro: return ClayTone(fill: Theme.amberFill, glyph: Theme.proGold)
        case .storage, .activity: return .sand
        case .recycle: return .peach
        case .autopilot: return .mint
        }
    }

    /// Sidebar groups (§6 order kept within and across groups).
    static let sections: [(String, [Page])] = [
        ("Overview", [.sessions, .ports, .resources, .mac]),
        ("Clean up", [.storage, .recycle]),
        ("Automate", [.autopilot, .connections]),
        ("Trust", [.safety, .activity])
    ]
}

// MARK: - Type (Design guidelines §2)

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
    static let body13 = Font.system(size: 13)
    static let meta = Font.system(size: 12)
    static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, design: .monospaced) }
}

extension View {
    /// Large headings: medium weight, slightly tight.
    func heading(_ size: CGFloat) -> some View {
        font(.display(size)).tracking(-size * 0.025).foregroundStyle(Theme.text)
    }
}

// MARK: - Clay glass material

/// Claymorphic surface: optional frosted glass under a soft tinted fill, an inner highlight at the
/// upper left, an inner shade at the lower right, and a broad colored drop shadow.
struct ClayBackground: View {
    var radius: CGFloat = 24
    var fill = AnyShapeStyle(Theme.surface)
    var glass = true
    var raised = true
    var inset = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            let frosted = glass && !reduceTransparency
            if frosted { shape.fill(.ultraThinMaterial) }
            if inset {
                shape.fill(fill.shadow(.inner(color: Theme.clayShade, radius: 5, x: 2, y: 3))
                               .shadow(.inner(color: Theme.clayHighlight, radius: 4, x: -2, y: -2)))
            } else {
                shape.fill(fill.opacity(frosted ? 0.62 : 1)
                               .shadow(.inner(color: Theme.clayHighlight, radius: 7, x: 3, y: 4))
                               .shadow(.inner(color: Theme.clayShade, radius: 10, x: -4, y: -6)))
                // Every raised card gets the glass edge; small solid tiles (glass: false) stay opaque for steady reading.
                if !reduceTransparency {
                    shape.fill(LinearGradient(colors: [Theme.glassSheen, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.38)))
                    shape.strokeBorder(Theme.glassRim, lineWidth: 1)
                }
            }
        }
        // A gradient fill with inner shadows leaves a bright fringe on the curved edge pixels (seen on
        // the hero card's corners). Trimming 1pt off the edge removes it; solid fills look the same.
        .clipShape(shape.inset(by: 1))
        .shadow(color: raised ? Theme.clayShadow : .clear, radius: raised ? 22 : 0, x: 0, y: raised ? 12 : 0)
    }
}

extension View {
    func clay(radius: CGFloat = 24, fill: some ShapeStyle = Theme.surface, glass: Bool = true, raised: Bool = true) -> some View {
        background(ClayBackground(radius: radius, fill: AnyShapeStyle(fill), glass: glass, raised: raised))
    }

    func clayInset(radius: CGFloat = 16, fill: some ShapeStyle = Theme.tint) -> some View {
        background(ClayBackground(radius: radius, fill: AnyShapeStyle(fill), glass: false, raised: false, inset: true))
    }
}

/// The content canvas: calm background with soft color fields.
struct Canvas: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.blobMint, Theme.blobMint.opacity(0)], center: .topTrailing, startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Theme.blobSky, Theme.blobSky.opacity(0)], center: .bottomLeading, startRadius: 0, endRadius: 560)
            RadialGradient(colors: [Theme.blobSand.opacity(0.7), Theme.blobSand.opacity(0)], center: UnitPoint(x: 0.75, y: 0.95), startRadius: 0, endRadius: 420)
            // A faint glow of the primary, so the glass cards have some color to pick up.
            RadialGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0)], center: UnitPoint(x: 0.3, y: 0.18), startRadius: 0, endRadius: 310)
            RadialGradient(colors: [Theme.accentLight.opacity(0.18), Theme.accentLight.opacity(0)], center: UnitPoint(x: 0.85, y: 0.62), startRadius: 0, endRadius: 260)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page scaffold

/// Page header: a large clay icon for the page, eyebrow, heading, subtitle, optional primary action.
struct PageHeader<Trailing: View>: View {
    var eyebrow: String?
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            IconTile(symbol: model.page.symbol, size: 64, tone: model.page.tone)
            VStack(alignment: .leading, spacing: 0) {
                Text((eyebrow ?? model.page.title).uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.8)
                    .foregroundStyle(model.page.tone.glyph)
                    .padding(.bottom, 6)
                Text(title).heading(30)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.secondary).padding(.top, 6)
            }
            Spacer(minLength: 24)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// Scrollable page body with the standard inset and footer.
struct PageScroll<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                content()
                Footer()
            }
            .padding(.horizontal, 36)
            .padding(.top, 40)
            .padding(.bottom, 28)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

struct Footer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 5)) { _ in
                Text(model.scanning ? "Scanning…" : "Updated \(Fmt.ago(model.workspace.scannedAt))")
            }
            Button("Rescan") { model.refresh(withStats: true); model.refreshDisk() }
                .buttonStyle(.link).foregroundStyle(Theme.accentText)
            Spacer()
            Button("Welcome & setup") { model.go(.welcome) }.buttonStyle(.plain)
        }
        .font(.meta)
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .clayInset(radius: 14, fill: Theme.tint.opacity(0.6))
    }
}

// MARK: - Surfaces (Design guidelines §4)

/// Content section: a glass clay card with an optional title row.
/// A titled section: heading and content straight on the page, because what's inside is usually clay tiles,
/// and a card around cards looks heavy. An untitled Panel is a single clay card. `boxed: true` keeps the card
/// for a titled section whose content isn't tiles (a form, a chart, a paragraph with a button).
struct Panel<Content: View, Trailing: View>: View {
    var title: String?
    var boxed: Bool?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        if boxed ?? (title == nil) {
            VStack(alignment: .leading, spacing: 16) {
                if let title { header(title, size: 16) }
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clay(radius: 26)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if let title { header(title, size: 18) }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ title: String, size: CGFloat) -> some View {
        HStack {
            Text(title).font(.system(size: size, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            trailing()
        }
    }
}

extension Panel where Trailing == EmptyView {
    init(title: String? = nil, boxed: Bool? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, boxed: boxed, trailing: { EmptyView() }, content: content)
    }
}

/// Sage clay card used for page heroes and summaries.
struct HeroCard<Content: View>: View {
    var padding: CGFloat = 40
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clay(radius: 30, fill: Theme.heroGradient)
    }
}

/// Puffy clay icon. `tone` picks a pastel; without it the tone follows the symbol.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 44
    var tone: ClayTone?

    init(symbol: String, size: CGFloat = 44, tone: ClayTone? = nil) {
        self.symbol = symbol; self.size = size; self.tone = tone
    }

    /// Older call sites passed explicit colors; they map onto a tone with the same fill.
    init(symbol: String, size: CGFloat = 44, tint: Color, fg: Color = Theme.accentText) {
        self.symbol = symbol; self.size = size; self.tone = ClayTone(fill: tint, glyph: fg)
    }

    var body: some View {
        let t = tone ?? ClayTone.forSymbol(symbol)
        let shape = RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(t.glyph)
            .frame(width: size, height: size)
            .background {
                shape.fill(t.fill
                    .shadow(.inner(color: Theme.clayHighlight, radius: size * 0.08, x: size * 0.05, y: size * 0.06))
                    .shadow(.inner(color: Theme.clayShade, radius: size * 0.1, x: -size * 0.05, y: -size * 0.07)))
                    .shadow(color: Theme.clayShadow, radius: size * 0.16, x: 0, y: size * 0.1)
            }
            .accessibilityHidden(true)
    }
}

/// Status badge. Color always comes with a label (§1).
struct Badge: View {
    enum Style { case neutral, active, ended, pinned, warning, success }
    let text: String
    var style: Style = .neutral
    var symbol: String?

    var body: some View {
        HStack(spacing: 5) {
            if style == .active { Circle().fill(Theme.activeText).frame(width: 7, height: 7) }
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            if style == .pinned && symbol == nil { Image(systemName: "pin.fill").font(.system(size: 9)) }
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .foregroundStyle(fg)
        .background(Capsule().fill(bg.shadow(.inner(color: Theme.clayHighlight, radius: 2, x: 1, y: 1))))
    }

    private var fg: Color {
        switch style {
        case .ended, .warning: return Theme.amberText
        case .active, .success: return Theme.activeText
        default: return Theme.secondary
        }
    }
    private var bg: Color {
        switch style {
        case .ended, .warning: return Theme.amberFill
        case .success: return Theme.tintStrong
        default: return Theme.tint
        }
    }
}

extension Session {
    var badge: Badge {
        if pinned { return Badge(text: "Pinned", style: .pinned) }
        switch state {
        case .active: return Badge(text: "Active", style: .active)
        case .idle(let since): return Badge(text: "Idle · \(Fmt.duration(Date().timeIntervalSince(since)))")
        case .ended: return Badge(text: "Ended", style: resources.isEmpty ? .neutral : .ended)
        }
    }
}

// MARK: - Tiles (lists render as card grids)

enum RowLayout { case row, tile }

private struct RowLayoutKey: EnvironmentKey { static let defaultValue = RowLayout.row }
extension EnvironmentValues {
    var rowLayout: RowLayout {
        get { self[RowLayoutKey.self] }
        set { self[RowLayoutKey.self] = newValue }
    }
}

/// Icon → name → context → value → action (§7). Inside a RowList it renders as a clay tile.
struct ResourceRow<Action: View>: View {
    let symbol: String
    let title: String
    var subtitle: String = ""
    var value: String?
    var valueCaption: String?
    var monoTitle = false
    @ViewBuilder var action: () -> Action
    @Environment(\.rowLayout) private var layout

    var body: some View {
        if layout == .tile { tile } else { row }
    }

    private var row: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(monoTitle ? .mono(14) : .system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                    .lineLimit(1).truncationMode(.middle)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 16)
            if let value {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(value).font(.system(size: 15)).monospacedDigit().foregroundStyle(Theme.text)
                    if let valueCaption { Text(valueCaption).font(.meta).foregroundStyle(Theme.secondary) }
                }
            }
            action()
        }
        .padding(.vertical, 12)
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                IconTile(symbol: symbol, size: 50)
                Spacer(minLength: 10)
                if let value {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(value).font(.system(size: 20)).tracking(-0.3).monospacedDigit().foregroundStyle(Theme.text)
                        if let valueCaption { Text(valueCaption).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                    }
                }
            }
            Text(title).font(monoTitle ? .mono(14) : .system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                .lineLimit(2).truncationMode(.middle)
                .padding(.top, 16)
            if !subtitle.isEmpty {
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.secondary).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
            Spacer(minLength: 14)
            HStack { action(); Spacer(minLength: 0) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
        .clay(radius: 22, glass: false)
    }
}

extension ResourceRow where Action == EmptyView {
    init(symbol: String, title: String, subtitle: String = "", value: String? = nil, valueCaption: String? = nil) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, value: value, valueCaption: valueCaption, action: { EmptyView() })
    }
}

/// A collection shown as a grid of clay tiles (no plain lists, by design).
struct RowList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row

    private let columns = [GridItem(.adaptive(minimum: 236, maximum: 420), spacing: 16, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(items) { item in
                row(item).environment(\.rowLayout, .tile)
            }
        }
    }
}

// MARK: - Buttons (§7)

struct PrimaryButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: large ? 14 : 11, style: .continuous)
        configuration.label
            .font(.system(size: large ? 15 : 13, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, large ? 24 : 16).padding(.vertical, large ? 13 : 8)
            .background {
                shape.fill(LinearGradient(colors: [Theme.accentLight, Theme.accent], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .white.opacity(0.35), radius: 3, x: 1, y: 2))
                    .shadow(.inner(color: .black.opacity(0.18), radius: 4, x: -1, y: -2)))
                    .opacity(enabled ? 1 : 0.45)
            }
            .shadow(color: Theme.accent.opacity(configuration.isPressed ? 0.15 : 0.35), radius: configuration.isPressed ? 4 : 12, y: configuration.isPressed ? 2 : 7)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(destructive ? Theme.destructive : Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background {
                shape.fill((configuration.isPressed ? Theme.tint : Theme.surface)
                    .shadow(.inner(color: Theme.clayHighlight, radius: 3, x: 1, y: 2))
                    .shadow(.inner(color: Theme.clayShade, radius: 4, x: -1, y: -2)))
            }
            .shadow(color: Theme.clayShadow.opacity(configuration.isPressed ? 0.3 : 0.8), radius: configuration.isPressed ? 2 : 6, y: configuration.isPressed ? 1 : 3)
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var primaryLarge: PrimaryButtonStyle { PrimaryButtonStyle(large: true) }
}
extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

/// "‹ Storage": back to the page a detail page opened from. ⌘[ works too.
struct BackLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text(title)
            }
            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("[", modifiers: .command)
        .accessibilityLabel("Back to \(title)")
    }
}

/// Minimal-chrome navigation link: "View session ›".
struct NavLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { Text(title); Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accentText)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Banners, stats, segments

struct InfoBanner: View {
    let text: String
    var symbol = "checkmark.shield"
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(symbol: symbol, size: 32, tone: .sage)
            Text(text).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16).padding(.vertical, 12)
        .clayInset(radius: 18)
    }
}

struct WarningBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(symbol: "exclamationmark.triangle", size: 32, tone: .peach)
            Text(text).foregroundStyle(Theme.amberText).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16).padding(.vertical, 12)
        .clayInset(radius: 18, fill: Theme.warningFill)
    }
}

/// Big number with a caption, as in the session overview strip.
struct StatBlock: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 30, weight: .regular)).tracking(-0.6).monospacedDigit().foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondary)
        }
    }
}

/// Segmented clay control: a pressed-in track with the selected segment raised.
struct ChipTabs<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, label in
                let on = selection == value
                Button { withAnimation(.easeOut(duration: 0.18)) { selection = value } } label: {
                    Text(label)
                        .font(.system(size: 13, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.text : Theme.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.surface.shadow(.inner(color: Theme.clayHighlight, radius: 3, x: 1, y: 2)))
                                    .shadow(color: Theme.clayShadow, radius: 6, y: 3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .clayInset(radius: 14)
        .fixedSize()
    }
}

/// Dropdown in the clay style: a raised pill showing the current value. The menu that opens stays native,
/// with a checkmark on the current choice.
struct ClayPicker<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(T, String)]
    var fullWidth = false

    var body: some View {
        let current = options.first { $0.0 == selection }?.1 ?? "\(selection)"
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.0) { value, label in Text(label).tag(value) }
            }
            .pickerStyle(.inline).labelsHidden()
        } label: {
            HStack(spacing: 8) {
                Text(current).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                if fullWidth { Spacer(minLength: 8) }
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
            .accessibilityElement(children: .combine)   // one control for VoiceOver, not text + chevron
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.surface.shadow(.inner(color: Theme.clayHighlight, radius: 3, x: 1, y: 2))
                                       .shadow(.inner(color: Theme.clayShade, radius: 4, x: -1, y: -2)))
                    .shadow(color: Theme.clayShadow.opacity(0.8), radius: 6, y: 3)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize(horizontal: !fullWidth, vertical: true)
        .accessibilityLabel(title)
        .accessibilityValue(current)
    }
}

/// "Show 3 more · 40 GB ⌄" / "Show fewer ⌃": a centered clay pill under a grid that's cut short.
struct ShowMoreButton: View {
    let expanded: Bool
    let hiddenCount: Int
    var detail: String?
    let toggle: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button { withAnimation(.easeOut(duration: 0.2)) { toggle() } } label: {
                HStack(spacing: 8) {
                    Text(expanded ? "Show fewer" : "Show \(hiddenCount) more" + (detail.map { " · " + $0 } ?? ""))
                        .monospacedDigit()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(.quiet)
            Spacer()
        }
        .padding(.top, 4)
    }
}

/// Small pill used for chips like "localhost" or "1.8 GB".
struct Chip: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Theme.tint.shadow(.inner(color: Theme.clayShade, radius: 2, x: 1, y: 1))))
    }
}

/// Loading placeholder: the shape of what's coming, no looping animation (§9).
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 12
    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(Theme.tint)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

struct SkeletonRows: View {
    var count = 3
    private let columns = [GridItem(.adaptive(minimum: 236, maximum: 420), spacing: 16)]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(0..<count, id: \.self) { i in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.tint).frame(width: 50, height: 50)
                    SkeletonBlock(width: 150 - CGFloat(i * 16), height: 13)
                    SkeletonBlock(width: 190 - CGFloat(i * 20), height: 11)
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                .clay(radius: 22, glass: false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// Empty, loading and all-clear states.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            IconTile(symbol: symbol, size: 64)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).padding(.top, 6)
            Text(message).font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .clayInset(radius: 24, fill: Theme.tint.opacity(0.45))   // a quiet recess, not another card
    }
}

// MARK: - The moon (§5). Decorative only, never a gauge.

struct Moon: View {
    var size: CGFloat = 250
    var rings = true

    var body: some View {
        ZStack {
            if rings {
                Circle().fill(Color.white.opacity(0.12)).frame(width: size * 1.45, height: size * 1.45)
                Circle().strokeBorder(Theme.accent.opacity(0.14), lineWidth: 1).frame(width: size * 1.35, height: size * 1.35)
            }
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF7FAEC), Color(hex: 0xD3E2BE), Color(hex: 0x9DBB88), Color(hex: 0x5F8A66)],
                                     center: UnitPoint(x: 0.28, y: 0.22), startRadius: 0, endRadius: size * 0.85))
                .frame(width: size, height: size)
                .shadow(color: Color(hex: 0x3F6447).opacity(0.25), radius: size * 0.08, x: size * 0.03, y: size * 0.06)
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0xE3EBD9), Color(hex: 0xC4D5BA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .shadow(.inner(color: Color(hex: 0x587A5C).opacity(0.35), radius: size * 0.035, x: size * 0.012, y: size * 0.02)))
                .frame(width: size * 0.64, height: size * 0.64)
                .offset(x: size * 0.06, y: -size * 0.1)
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .clear], startPoint: .topLeading, endPoint: .center), lineWidth: 1.5)
                .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// The app's mark: the moon on a deep sage clay tile, as on the Sessions hero. App icon, sidebar, menu bar popover.
struct AppMark: View {
    var size: CGFloat = 42

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(hex: 0x4F6B57), Color(hex: 0x2B3C30)], startPoint: .topLeading, endPoint: .bottomTrailing)
                           .shadow(.inner(color: .white.opacity(0.2), radius: size * 0.03, x: size * 0.015, y: size * 0.02))
                           .shadow(.inner(color: .black.opacity(0.35), radius: size * 0.05, x: -size * 0.02, y: -size * 0.03)))
                // Same 1-pixel trim as ClayBackground: gradient + inner shadow leaves a bright fringe on curves.
                .clipShape(shape.inset(by: max(0.5, size * 0.002)))
            Moon(size: size * 0.58, rings: true)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The moon on its own, sized for the menu bar. Kept in color, like the app icon.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let r = ImageRenderer(content: Moon(size: 15, rings: false).frame(width: 18, height: 18))
        r.scale = 2
        let img = r.nsImage ?? NSImage()
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = false
        return img
    }()
}

// MARK: - Glass

/// NSVisualEffectView for navigation chrome (sidebar, popover). Falls back to opaque with Reduce Transparency.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
