import AppKit
import SwiftUI
import VoyagerCore

/// Decides when the overlay is visible and keeps its contents in sync. Main thread only.
final class OverlayController {
    private let panel = OverlayPanel()
    private let model = OverlayModel()
    private let hosting: NSHostingView<KeyboardOverlayView>

    private(set) var settings = AppSettings.defaults
    private var layout: OryxLayout?
    private(set) var currentLayer = 0
    private var lockTracker = LayerLockTracker()
    private var pressed: Set<Int> = []

    /// Layer forced on screen by "Show test overlay".
    private var forcedLayer: Int?
    /// Auto-hide fired for this layer; stay hidden until the layer changes.
    private var autoHiddenLayer: Int?

    private var isShown = false
    /// Strict (non-coalesced) one-shot timer for the show delay. asyncAfter/Timer get coalesced by the
    /// system for a windowless app and fired up to ~100 ms late.
    private var pendingShow: DispatchSourceTimer?
    private var autoHide: DispatchWorkItem?
    private var fadeGeneration = 0
    private var layerChangedAt = Date()

    init() {
        hosting = NSHostingView(rootView: KeyboardOverlayView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        prewarm()
    }

    /// Do the first (slow, ~30 ms) layout and screen lookup at launch instead of on the first layer change.
    private func prewarm() {
        panel.alphaValue = 0
        positionPanel()
        hosting.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        panel.orderOut(nil)
    }

    var isTestOverlayOn: Bool { forcedLayer != nil }

    /// Diagnostic: each time the overlay appears, use the next window level and print its name on it.
    var cycleWindowLevels = false {
        didSet {
            levelCycleIndex = 0
            if !cycleWindowLevels {
                model.note = nil
                panel.level = OverlayPanel.level(for: settings.windowLevel, custom: settings.customWindowLevel)
            }
        }
    }
    private var levelCycleIndex = 0
    private static let levelCycle: [AppSettings.WindowLevel] = [.shielding, .screenSaver, .popUpMenu, .statusBar, .floating]

    // MARK: Inputs

    func apply(settings newSettings: AppSettings) {
        let old = settings
        settings = newSettings
        model.settings = newSettings
        if !cycleWindowLevels {
            panel.level = OverlayPanel.level(for: newSettings.windowLevel, custom: newSettings.customWindowLevel)
        }
        if old.baseLayer != newSettings.baseLayer {
            lockTracker = LayerLockTracker(baseLayer: newSettings.baseLayer)
            lockTracker.layerChanged(to: currentLayer)
        }
        if old.baseLayer != newSettings.baseLayer { refreshContent() }
        if isShown { positionPanel() }
        evaluate(layerChanged: false)
    }

    func setLayout(_ newLayout: OryxLayout?) {
        layout = newLayout
        refreshContent()
    }

    func layerChanged(_ layer: Int) {
        guard layer != currentLayer else { return }
        currentLayer = layer
        layerChangedAt = Date()
        lockTracker.layerChanged(to: layer)
        autoHiddenLayer = nil
        evaluate(layerChanged: true)
    }

    func keyEvent(index: Int, down: Bool) {
        if down {
            pressed.insert(index)
            let code = layout?.layer(at: currentLayer).flatMap { $0.keys.indices.contains(index) ? $0.keys[index].tap?.code : nil }
            let wasLocked = lockTracker.isCurrentLayerLocked
            lockTracker.keyPressed(code: code)
            if wasLocked != lockTracker.isCurrentLayerLocked, isShown { model.locked = lockTracker.isCurrentLayerLocked }
        } else {
            pressed.remove(index)
        }
        if isShown && settings.highlightPressedKeys { model.pressed = pressed }
    }

    func setTestOverlay(_ on: Bool) {
        if on {
            let candidates = (layout?.layers.map(\.position) ?? [1]).filter { $0 != settings.baseLayer }
            forcedLayer = candidates.first ?? 1
        } else {
            forcedLayer = nil
        }
        evaluate(layerChanged: true)
    }

    // MARK: Visibility

    private func evaluate(layerChanged: Bool) {
        let wantsShow: Bool
        if forcedLayer != nil {
            wantsShow = true
        } else {
            wantsShow = settings.shouldShowOverlay(forLayer: currentLayer) && autoHiddenLayer != currentLayer
        }

        guard wantsShow else {
            pendingShow?.cancel()
            pendingShow = nil
            if isShown { hide() }
            return
        }

        if isShown {
            // Already up: swap contents in place, no window animation.
            if layerChanged {
                refreshContent()
                scheduleAutoHide()
            }
            return
        }

        // Not visible yet. The layer must stay active for the show delay (restarted on every change),
        // so tapping a dual-role key like Space/MO(1) doesn't flash the overlay.
        if layerChanged || pendingShow == nil {
            pendingShow?.cancel()
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
            let delayMs = forcedLayer != nil ? 0 : Int(settings.showDelayMs.rounded())
            timer.schedule(deadline: .now() + .milliseconds(delayMs), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.pendingShow?.cancel()
                self.pendingShow = nil
                self.show()
            }
            pendingShow = timer
            timer.resume()
        }
    }

    private func show() {
        let stillWanted = forcedLayer != nil || (settings.shouldShowOverlay(forLayer: currentLayer) && autoHiddenLayer != currentLayer)
        guard stillWanted else { return }
        let firedAt = Date()
        if cycleWindowLevels {
            let choice = Self.levelCycle[levelCycleIndex % Self.levelCycle.count]
            levelCycleIndex += 1
            panel.level = OverlayPanel.level(for: choice, custom: settings.customWindowLevel)
            model.note = "level test: \(choice.rawValue) (\(panel.level.rawValue))"
        }
        isShown = true
        refreshContent()
        model.pressed = settings.highlightPressedKeys ? pressed : []
        positionPanel()
        panel.orderFrontRegardless()
        fadeGeneration += 1
        animateAlpha(to: 1)
        scheduleAutoHide()
        let total = Date().timeIntervalSince(layerChangedAt) * 1000
        let work = Date().timeIntervalSince(firedAt) * 1000
        Log.info(String(format: "overlay shown: layer %d (%@), %.0f ms after the layer change (%.1f ms to draw), window level %d",
                        forcedLayer ?? currentLayer, model.layerTitle, total, work, panel.level.rawValue))
    }

    private func hide() {
        isShown = false
        autoHide?.cancel()
        fadeGeneration += 1
        let generation = fadeGeneration
        animateAlpha(to: 0) { [weak self] in
            guard let self, self.fadeGeneration == generation, !self.isShown else { return }
            self.panel.orderOut(nil)
        }
        Log.info("overlay hidden")
    }

    private func animateAlpha(to target: CGFloat, completion: (() -> Void)? = nil) {
        let duration = settings.fadeDurationMs / 1000
        if duration <= 0 {
            panel.alphaValue = target
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.allowsImplicitAnimation = false
            panel.animator().alphaValue = target
        }, completionHandler: completion)
    }

    private func scheduleAutoHide() {
        autoHide?.cancel()
        autoHide = nil
        guard settings.autoHideSeconds > 0, forcedLayer == nil else { return }
        let layer = currentLayer
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isShown, self.currentLayer == layer else { return }
            self.autoHiddenLayer = layer
            self.hide()
        }
        autoHide = item
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.autoHideSeconds, execute: item)
    }

    // MARK: Content

    private func refreshContent() {
        let layer = forcedLayer ?? currentLayer
        if let layout {
            model.caps = KeyLabeler.caps(forLayer: layer, in: layout, baseLayer: settings.baseLayer)
            let l = layout.layer(at: layer)
            model.layerTitle = l?.title ?? "Layer \(layer)"
            model.layerColorHex = l?.color
            model.hasLayout = true
        } else {
            model.caps = Array(repeating: .blank, count: KeyLabeler.keysPerLayer)
            model.layerTitle = "Layer \(layer)"
            model.layerColorHex = nil
            model.hasLayout = false
        }
        model.layerIndex = layer
        model.locked = forcedLayer == nil && lockTracker.isCurrentLayerLocked
    }

    // MARK: Position

    /// Centered (by default) on the screen that has the mouse cursor. Re-checked every time it appears.
    private func positionPanel() {
        let size = OverlayMetrics(scale: settings.scale).totalSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.frame else { return }
        let margin: CGFloat = 40

        var x: CGFloat
        var y: CGFloat
        switch settings.position {
        case .center, .top, .bottom: x = frame.midX - size.width / 2
        case .topLeft, .bottomLeft: x = frame.minX + margin
        case .topRight, .bottomRight: x = frame.maxX - size.width - margin
        }
        switch settings.position {
        case .center: y = frame.midY - size.height / 2
        case .top, .topLeft, .topRight: y = frame.maxY - size.height - margin
        case .bottom, .bottomLeft, .bottomRight: y = frame.minY + margin
        }
        x += settings.offsetX
        y += settings.offsetY // positive = up

        let rect = NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        if panel.frame != rect { panel.setFrame(rect, display: false) }
    }
}
