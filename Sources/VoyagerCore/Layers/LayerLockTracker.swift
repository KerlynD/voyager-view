/// Infers which layers are locked with QK_LLCK.
///
/// The firmware only reports the highest active layer, never *why* it's active. But while paired it
/// also reports every key press, so when the key pressed on the current layer is QK_LLCK we know that
/// layer just got locked (or unlocked). Returning to the base layer clears everything, which also
/// covers the firmware's lock idle timeout. Toggle keys (TG/TO) aren't tracked, so no badge for those.
public struct LayerLockTracker: Equatable, Sendable {
    public private(set) var lockedLayers: Set<Int> = []
    public private(set) var currentLayer: Int = 0
    public let baseLayer: Int

    public init(baseLayer: Int = 0) { self.baseLayer = baseLayer }

    public var isCurrentLayerLocked: Bool { lockedLayers.contains(currentLayer) }

    public mutating func layerChanged(to layer: Int) {
        currentLayer = layer
        if layer == baseLayer { lockedLayers.removeAll() }
    }

    /// Call on KEYDOWN with the Oryx key index and the code that key has on the current layer.
    public mutating func keyPressed(code: String?) {
        guard let code, code == "QK_LLCK" || code == "QK_LAYER_LOCK", currentLayer != baseLayer else { return }
        if lockedLayers.contains(currentLayer) {
            lockedLayers.remove(currentLayer)
        } else {
            lockedLayers.insert(currentLayer)
        }
    }
}
