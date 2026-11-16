import Foundation

/// Everything in `~/Library/Application Support/VoyagerView/config.json`.
/// Missing or invalid keys fall back to defaults individually, so a hand-edited file never wipes the rest.
public struct AppSettings: Codable, Equatable, Sendable {
    public enum Position: String, Codable, CaseIterable, Sendable {
        case center, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    }
    public enum TransparentKeyStyle: String, Codable, CaseIterable, Sendable { case dim, blank }
    public enum Theme: String, Codable, CaseIterable, Sendable { case dark, light }
    public enum AccentMode: String, Codable, CaseIterable, Sendable { case layerColor, custom }
    public enum WindowLevel: String, Codable, CaseIterable, Sendable {
        /// CGShieldingWindowLevel(): above apps that capture the display.
        case shielding
        case screenSaver
        case popUpMenu
        case statusBar
        case floating
        /// Use `customWindowLevel`.
        case custom
    }

    // Look
    public var overallOpacity: Double = 0.92
    public var backgroundOpacity: Double = 0.55
    public var keyFillOpacity: Double = 0.65
    public var labelOpacity: Double = 1.0
    /// 1.0 = default width (~860 pt).
    public var scale: Double = 1.0
    public var position: Position = .center
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public var theme: Theme = .dark
    public var accentMode: AccentMode = .layerColor
    public var customAccentHex: String = "#7AA2F7"
    public var showHoldLabels: Bool = true
    public var transparentKeys: TransparentKeyStyle = .dim
    public var highlightPressedKeys: Bool = true
    /// Font family for labels. Empty, or not installed, = the system font.
    public var fontFamily: String = "ABC Areal Mono"

    // Behaviour
    public var showDelayMs: Double = 120
    public var fadeDurationMs: Double = 100
    /// 0 = never auto-hide.
    public var autoHideSeconds: Double = 0
    public var baseLayer: Int = 0
    public var hiddenLayers: [Int] = []

    // Data
    public var layoutHashId: String = "dMyG6"

    // Advanced
    public var windowLevel: WindowLevel = .shielding
    public var customWindowLevel: Int = 1000
    /// Log every HID event (layer changes always get logged).
    public var logKeyEvents: Bool = false

    public init() {}

    public static let defaults = AppSettings()

    public static let scaleRange: ClosedRange<Double> = 0.4...1.5
    public static let opacityRange: ClosedRange<Double> = 0.1...1.0
    public static let fillOpacityRange: ClosedRange<Double> = 0.0...1.0

    /// Clamp everything into sane ranges.
    public func normalized() -> AppSettings {
        var s = self
        s.overallOpacity = s.overallOpacity.clamped(to: Self.opacityRange)
        s.backgroundOpacity = s.backgroundOpacity.clamped(to: Self.fillOpacityRange)
        s.keyFillOpacity = s.keyFillOpacity.clamped(to: Self.fillOpacityRange)
        s.labelOpacity = s.labelOpacity.clamped(to: Self.opacityRange)
        s.scale = s.scale.clamped(to: Self.scaleRange)
        s.showDelayMs = s.showDelayMs.clamped(to: 0...2000)
        s.fadeDurationMs = s.fadeDurationMs.clamped(to: 0...2000)
        s.autoHideSeconds = s.autoHideSeconds.clamped(to: 0...3600)
        s.offsetX = s.offsetX.clamped(to: -5000...5000)
        s.offsetY = s.offsetY.clamped(to: -5000...5000)
        s.baseLayer = max(0, s.baseLayer)
        s.hiddenLayers = Array(Set(s.hiddenLayers.filter { $0 >= 0 })).sorted()
        s.layoutHashId = s.layoutHashId.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.layoutHashId.isEmpty { s.layoutHashId = Self.defaults.layoutHashId }
        s.fontFamily = s.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }

    /// Whether `layer` should make the overlay visible.
    public func shouldShowOverlay(forLayer layer: Int) -> Bool {
        layer != baseLayer && !hiddenLayers.contains(layer)
    }

    // MARK: Lenient JSON

    /// Decode a config file. Unknown keys are ignored; keys with bad values keep their defaults.
    public static func decodeLenient(_ data: Data) -> AppSettings {
        guard let user = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(AppSettings.defaults),
              var merged = (try? JSONSerialization.jsonObject(with: defaultsData)) as? [String: Any]
        else { return .defaults }

        let decoder = JSONDecoder()
        func decodes(_ dict: [String: Any]) -> AppSettings? {
            guard let d = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(AppSettings.self, from: d)
        }
        // Apply keys one at a time so one bad value can't take the others down with it.
        for (key, value) in user where merged[key] != nil {
            var candidate = merged
            candidate[key] = value
            if decodes(candidate) != nil { merged = candidate }
        }
        return (decodes(merged) ?? .defaults).normalized()
    }

    public func encodedJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
