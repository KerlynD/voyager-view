import AppKit
import VoyagerCore

/// A borderless, click-through, never-key panel that floats over everything, including fullscreen games.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: 320),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func level(for setting: AppSettings.WindowLevel, custom: Int) -> NSWindow.Level {
        switch setting {
        case .shielding: return NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        case .screenSaver: return .screenSaver
        case .popUpMenu: return .popUpMenu
        case .statusBar: return .statusBar
        case .floating: return .floating
        case .custom: return NSWindow.Level(rawValue: custom)
        }
    }
}
