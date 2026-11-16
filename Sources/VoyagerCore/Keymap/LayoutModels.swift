import Foundation

// Models for the Oryx GraphQL `getLayout` response. Decoding is deliberately lenient: Oryx omits
// fields on some keys (e.g. `hold`, `modifier`), so everything except `code` is optional.

public struct OryxLayout: Codable, Equatable, Sendable {
    public var title: String
    public var geometry: String
    public var revisionHashId: String
    public var layers: [OryxLayer]

    public init(title: String, geometry: String, revisionHashId: String, layers: [OryxLayer]) {
        self.title = title
        self.geometry = geometry
        self.revisionHashId = revisionHashId
        self.layers = layers
    }

    public func layer(at position: Int) -> OryxLayer? {
        layers.first { $0.position == position } ?? (layers.indices.contains(position) ? layers[position] : nil)
    }

    /// Parses the raw GraphQL response body (`{"data":{"layout":{…}}}`).
    public static func decodeGraphQLResponse(_ data: Data) throws -> OryxLayout {
        let envelope = try JSONDecoder().decode(GraphQLEnvelope.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw LayoutError.graphQL(errors.map(\.message).joined(separator: "; "))
        }
        guard let layout = envelope.data?.layout else { throw LayoutError.notFound }
        guard !layout.revision.layers.isEmpty else { throw LayoutError.noLayers }
        return OryxLayout(
            title: layout.title ?? "Untitled",
            geometry: layout.geometry ?? "voyager",
            revisionHashId: layout.revision.hashId ?? "",
            layers: layout.revision.layers.sorted { $0.position < $1.position }
        )
    }

    public enum LayoutError: Error, CustomStringConvertible {
        case graphQL(String)
        case notFound
        case noLayers
        public var description: String {
            switch self {
            case .graphQL(let m): return "Oryx API error: \(m)"
            case .notFound: return "Layout not found (check the hash ID)"
            case .noLayers: return "Layout has no layers"
            }
        }
    }

    private struct GraphQLEnvelope: Decodable {
        struct Payload: Decodable { let layout: RawLayout? }
        struct RawLayout: Decodable {
            let title: String?
            let geometry: String?
            let revision: Revision
        }
        struct Revision: Decodable {
            let hashId: String?
            let layers: [OryxLayer]
        }
        struct GQLError: Decodable { let message: String }
        let data: Payload?
        let errors: [GQLError]?
    }
}

public struct OryxLayer: Codable, Equatable, Sendable {
    public var title: String
    public var position: Int
    public var color: String?
    public var keys: [OryxKey]

    public init(title: String, position: Int, color: String?, keys: [OryxKey]) {
        self.title = title
        self.position = position
        self.color = color
        self.keys = keys
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        let t = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        title = t.isEmpty ? "Layer \(position)" : t
        color = try c.decodeIfPresent(String.self, forKey: .color)
        keys = try c.decodeIfPresent([OryxKey].self, forKey: .keys) ?? []
    }
}

public struct OryxKey: Codable, Equatable, Sendable {
    public var tap: OryxAction?
    public var hold: OryxAction?
    public var doubleTap: OryxAction?
    public var tapHold: OryxAction?
    public var customLabel: String?
    public var icon: String?
    public var emoji: String?
    public var glowColor: String?

    public init(tap: OryxAction? = nil, hold: OryxAction? = nil, doubleTap: OryxAction? = nil, tapHold: OryxAction? = nil,
                customLabel: String? = nil, icon: String? = nil, emoji: String? = nil, glowColor: String? = nil) {
        self.tap = tap
        self.hold = hold
        self.doubleTap = doubleTap
        self.tapHold = tapHold
        self.customLabel = customLabel
        self.icon = icon
        self.emoji = emoji
        self.glowColor = glowColor
    }
}

public struct OryxAction: Codable, Equatable, Sendable {
    public var code: String
    public var layer: Int?
    public var modifiers: OryxModifiers?
    public var description: String?

    public init(code: String, layer: Int? = nil, modifiers: OryxModifiers? = nil, description: String? = nil) {
        self.code = code
        self.layer = layer
        self.modifiers = modifiers
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? "KC_NO"
        layer = try c.decodeIfPresent(Int.self, forKey: .layer)
        modifiers = try? c.decodeIfPresent(OryxModifiers.self, forKey: .modifiers)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
    }
}

/// Oryx sends modifiers as an object of eight booleans, e.g. `{"leftGui":true,"leftShift":true,…}`.
public struct OryxModifiers: Codable, Equatable, Sendable {
    public var leftCtrl = false, leftShift = false, leftAlt = false, leftGui = false
    public var rightCtrl = false, rightShift = false, rightAlt = false, rightGui = false

    public init(leftCtrl: Bool = false, leftShift: Bool = false, leftAlt: Bool = false, leftGui: Bool = false,
                rightCtrl: Bool = false, rightShift: Bool = false, rightAlt: Bool = false, rightGui: Bool = false) {
        self.leftCtrl = leftCtrl; self.leftShift = leftShift; self.leftAlt = leftAlt; self.leftGui = leftGui
        self.rightCtrl = rightCtrl; self.rightShift = rightShift; self.rightAlt = rightAlt; self.rightGui = rightGui
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func b(_ k: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: k)).flatMap { $0 } ?? false }
        leftCtrl = b(.leftCtrl); leftShift = b(.leftShift); leftAlt = b(.leftAlt); leftGui = b(.leftGui)
        rightCtrl = b(.rightCtrl); rightShift = b(.rightShift); rightAlt = b(.rightAlt); rightGui = b(.rightGui)
    }

    public var ctrl: Bool { leftCtrl || rightCtrl }
    public var shift: Bool { leftShift || rightShift }
    public var alt: Bool { leftAlt || rightAlt }
    public var gui: Bool { leftGui || rightGui }
    public var isEmpty: Bool { !(ctrl || shift || alt || gui) }

    /// Order from the spec: ⌘⌥⌃⇧ (so LGUI+LSHIFT+KC_4 → "⌘⇧4").
    public var glyphs: String {
        (gui ? "⌘" : "") + (alt ? "⌥" : "") + (ctrl ? "⌃" : "") + (shift ? "⇧" : "")
    }
}
