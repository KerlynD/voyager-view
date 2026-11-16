import Foundation

/// What to draw on one key.
public struct KeyCap: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case normal
        /// KC_TRANSPARENT: shows what falls through from the base layer, dimmed.
        case transparent
        /// KC_NO or no action at all.
        case blank
    }

    public var primary: String
    public var secondary: String?
    public var style: Style

    public init(primary: String, secondary: String? = nil, style: Style = .normal) {
        self.primary = primary
        self.secondary = secondary
        self.style = style
    }

    public static let blank = KeyCap(primary: "", style: .blank)
}

public enum KeyLabeler {
    public static let keysPerLayer = 52

    /// All 52 caps for one layer. Missing keys are blank.
    public static func caps(forLayer position: Int, in layout: OryxLayout, baseLayer: Int = 0) -> [KeyCap] {
        guard let layer = layout.layer(at: position) else {
            return Array(repeating: .blank, count: keysPerLayer)
        }
        return (0..<keysPerLayer).map { idx in
            cap(for: layer.keys.indices.contains(idx) ? layer.keys[idx] : nil,
                index: idx, layerPosition: position, layout: layout, baseLayer: baseLayer)
        }
    }

    public static func cap(for key: OryxKey?, index: Int, layerPosition: Int, layout: OryxLayout, baseLayer: Int = 0) -> KeyCap {
        guard let key else { return .blank }

        let tap = key.tap
        let hold = key.hold

        // KC_TRANSPARENT: borrow the base layer's key, dimmed.
        if let tap, KeycodeLabels.transparentCodes.contains(tap.code), hold == nil, key.customLabel.isNilOrEmpty {
            guard layerPosition != baseLayer,
                  let base = layout.layer(at: baseLayer),
                  base.keys.indices.contains(index) else { return .blank }
            var inherited = cap(for: base.keys[index], index: index, layerPosition: baseLayer, layout: layout, baseLayer: baseLayer)
            if inherited.style == .blank { return .blank }
            inherited.style = .transparent
            return inherited
        }

        let tapIsReal = tap.map { !KeycodeLabels.noCodes.contains($0.code) } ?? false
        let holdIsReal = hold.map { !KeycodeLabels.noCodes.contains($0.code) } ?? false

        // Rule 1: customLabel always wins. Oryx also lets you put an emoji on a key instead.
        let custom = key.customLabel.nonEmpty ?? key.emoji.nonEmpty

        if let custom {
            let secondary = (tapIsReal && holdIsReal) ? actionLabel(hold!, layout: layout) : nil
            return KeyCap(primary: custom, secondary: secondary)
        }

        if tapIsReal, let tap {
            // Rule 2 + 4: tap label, hold as secondary.
            return KeyCap(primary: actionLabel(tap, layout: layout),
                          secondary: holdIsReal ? actionLabel(hold!, layout: layout) : nil)
        }
        if holdIsReal, let hold {
            // Rule 3: hold-only key.
            return KeyCap(primary: actionLabel(hold, layout: layout))
        }
        return .blank
    }

    /// Label for a single action: modifier glyphs + keycode label, or the target layer title.
    public static func actionLabel(_ action: OryxAction, layout: OryxLayout) -> String {
        if KeycodeLabels.layerCodes.contains(action.code), let target = action.layer {
            return layout.layer(at: target)?.title ?? "L\(target)"
        }
        let base = KeycodeLabels.label(for: action.code)
        guard let mods = action.modifiers, !mods.isEmpty else { return base }
        return mods.glyphs + base
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
    var isNilOrEmpty: Bool { nonEmpty == nil }
}
