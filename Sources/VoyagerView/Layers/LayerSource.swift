import Foundation

enum LayerSourceStatus: Equatable {
    case idle
    case searching
    case connected          // device opened, waiting for pairing
    case paired(protocolVersion: Int?)
    case permissionDenied
    case error(String)

    var menuText: String {
        switch self {
        case .idle: return "Stopped"
        case .searching: return "Voyager not found"
        case .connected: return "Voyager found · pairing…"
        case .paired: return "Voyager connected"
        case .permissionDenied: return "Input Monitoring permission needed"
        case .error(let m): return "Error: \(m)"
        }
    }
}

/// Something that reports the keyboard's active layer. All callbacks arrive on the main thread.
protocol LayerSource: AnyObject {
    var onLayer: ((Int) -> Void)? { get set }
    /// Oryx key index, pressed (true) or released (false). Optional for sources that can't tell.
    var onKey: ((Int, Bool) -> Void)? { get set }
    var onStatus: ((LayerSourceStatus) -> Void)? { get set }
    func start()
    func stop()
}
