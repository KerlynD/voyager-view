import SwiftUI
import VoyagerCore

/// State the overlay draws. Only changes when the layer, settings, layout or (while visible) pressed keys change,
/// so SwiftUI does no work otherwise.
final class OverlayModel: ObservableObject {
    @Published var caps: [KeyCap] = Array(repeating: .blank, count: KeyLabeler.keysPerLayer)
    @Published var layerIndex = 0
    @Published var layerTitle = ""
    @Published var layerColorHex: String?
    @Published var locked = false
    @Published var pressed: Set<Int> = []
    @Published var settings = AppSettings.defaults
    @Published var hasLayout = false
    /// Extra text in the header (used by the window level test).
    @Published var note: String?
}

/// Sizes in points, derived from the scale setting.
struct OverlayMetrics {
    let unit: CGFloat
    let padding: CGFloat
    let headerHeight: CGFloat
    let boardSize: CGSize

    init(scale: Double) {
        unit = (54 * scale).rounded()
        padding = (unit * 0.35).rounded()
        headerHeight = (unit * 0.62).rounded()
        let g = VoyagerGeometry.drawSize
        boardSize = CGSize(width: g.width * unit, height: g.height * unit)
    }

    var totalSize: CGSize {
        CGSize(width: boardSize.width + padding * 2,
               height: headerHeight + padding * 0.6 + boardSize.height + padding * 2)
    }
}

struct Palette {
    let background: Color
    let keyFill: Color
    let keyStroke: Color
    let text: Color
    let accent: Color

    init(settings: AppSettings, layerColorHex: String?) {
        switch settings.theme {
        case .dark:
            background = Color(white: 0.06)
            keyFill = Color(white: 0.20)
            keyStroke = Color(white: 1, opacity: 0.12)
            text = .white
        case .light:
            background = Color(white: 0.97)
            keyFill = Color.white
            keyStroke = Color(white: 0, opacity: 0.15)
            text = Color(white: 0.08)
        }
        let accentHex = settings.accentMode == .custom ? settings.customAccentHex : (layerColorHex ?? settings.customAccentHex)
        accent = Color(hex: accentHex) ?? .accentColor
    }
}

struct KeyboardOverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        let s = model.settings
        let m = OverlayMetrics(scale: s.scale)
        let palette = Palette(settings: s, layerColorHex: model.layerColorHex)

        VStack(spacing: m.padding * 0.6) {
            header(m, palette)
            ZStack(alignment: .topLeading) {
                ForEach(VoyagerGeometry.keys, id: \.index) { key in
                    let origin = VoyagerGeometry.drawOrigin(of: key)
                    KeyCapView(cap: model.caps[key.index],
                               pressed: s.highlightPressedKeys && model.pressed.contains(key.index),
                               unit: m.unit, settings: s, palette: palette)
                        .rotationEffect(.degrees(VoyagerGeometry.rotationDegrees(of: key)))
                        .position(x: (origin.x + 0.5) * m.unit, y: (origin.y + 0.5) * m.unit)
                }
            }
            .frame(width: m.boardSize.width, height: m.boardSize.height, alignment: .topLeading)
        }
        .padding(m.padding)
        .frame(width: m.totalSize.width, height: m.totalSize.height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: m.unit * 0.32, style: .continuous)
                .fill(palette.background.opacity(s.backgroundOpacity))
        )
        .compositingGroup()
        .opacity(s.overallOpacity)
    }

    private func header(_ m: OverlayMetrics, _ palette: Palette) -> some View {
        let tint = Color(hex: model.layerColorHex ?? "") ?? palette.accent
        let fg = Color.contrasting(hex: model.layerColorHex) ?? palette.text
        return HStack(spacing: m.unit * 0.18) {
            Text(model.layerTitle)
                .font(.system(size: m.unit * 0.32, weight: .semibold, design: .default))
            if model.locked {
                Text("🔒").font(.system(size: m.unit * 0.28))
            }
            if let note = model.note {
                Text("· \(note)")
                    .font(.system(size: m.unit * 0.22, weight: .regular, design: .monospaced))
            }
            if !model.hasLayout {
                Text("· layout not loaded")
                    .font(.system(size: m.unit * 0.22, weight: .regular, design: .default))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(fg.opacity(model.settings.labelOpacity))
        .padding(.horizontal, m.unit * 0.4)
        .frame(height: m.headerHeight)
        .background(Capsule().fill(tint.opacity(0.9)))
    }
}

struct KeyCapView: View {
    let cap: KeyCap
    let pressed: Bool
    let unit: CGFloat
    let settings: AppSettings
    let palette: Palette

    var body: some View {
        let size = unit * 0.92
        let shape = RoundedRectangle(cornerRadius: unit * 0.14, style: .continuous)
        let isBlank = cap.style == .blank || (cap.style == .transparent && settings.transparentKeys == .blank)
        let fillOpacity = settings.keyFillOpacity * (isBlank ? 0.45 : 1)
        let labelOpacity = settings.labelOpacity * (cap.style == .transparent ? 0.38 : 1)

        ZStack {
            shape.fill(pressed ? palette.accent.opacity(0.9) : palette.keyFill.opacity(fillOpacity))
            shape.strokeBorder(palette.keyStroke, lineWidth: max(1, unit * 0.02))
            if !isBlank {
                VStack(spacing: unit * 0.02) {
                    Text(cap.primary)
                        .font(.system(size: primaryFontSize, weight: .medium, design: .default))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.45)
                    if settings.showHoldLabels, let secondary = cap.secondary {
                        Text(secondary)
                            .font(.system(size: unit * 0.15, weight: .regular, design: .default))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .opacity(0.65)
                    }
                }
                .foregroundStyle(palette.text.opacity(labelOpacity))
                .padding(.horizontal, unit * 0.05)
                .padding(.vertical, unit * 0.04)
            }
        }
        .frame(width: size, height: size)
    }

    private var primaryFontSize: CGFloat {
        switch cap.primary.count {
        case 0...2: return unit * 0.34
        case 3: return unit * 0.28
        case 4...5: return unit * 0.22
        default: return unit * 0.18
        }
    }
}

extension Color {
    init?(hex: String) {
        guard let rgb = RGB(hex: hex) else { return nil }
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// Black or white, whichever reads better on the given background.
    static func contrasting(hex: String?) -> Color? {
        guard let hex, let rgb = RGB(hex: hex) else { return nil }
        return rgb.luminance > 0.5 ? Color(white: 0.08) : .white
    }
}

struct RGB {
    let r: Double, g: Double, b: Double

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}
