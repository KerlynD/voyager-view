import Foundation

/// Cycles through layers on a timer so the overlay can be tested without the keyboard
/// (e.g. while sitting in a League game, where the menu bar can't be reached).
final class DemoLayerSource: LayerSource {
    var onLayer: ((Int) -> Void)?
    var onKey: ((Int, Bool) -> Void)?
    var onStatus: ((LayerSourceStatus) -> Void)?

    /// (layer, seconds to stay on it). Includes a short tap to check the show delay suppresses flashes.
    private let script: [(Int, TimeInterval)]
    private var step = 0
    private var timer: DispatchSourceTimer?

    init(layerCount: Int) {
        var s: [(Int, TimeInterval)] = []
        for layer in 1..<max(layerCount, 2) {
            s.append((0, 1.5))
            s.append((layer, 2.5))
        }
        s.append((0, 1.5))
        s.append((1, 0.06)) // a quick tap: should NOT flash the overlay
        script = s
    }

    func start() {
        stop()
        step = 0
        onStatus?(.paired(protocolVersion: nil))
        advance()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func advance() {
        let (layer, duration) = script[step % script.count]
        step += 1
        onLayer?(layer)
        // Strict timer: the 60 ms tap must really be 60 ms, and normal timers get coalesced.
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        t.schedule(deadline: .now() + .milliseconds(Int(duration * 1000)), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.advance() }
        timer?.cancel()
        timer = t
        t.resume()
    }
}
