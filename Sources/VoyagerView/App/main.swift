import AppKit

// `VoyagerView --hid-probe [seconds]`: log raw HID events from the terminal, no UI.
if CommandLine.arguments.contains("--hid-probe") {
    let seconds = CommandLine.arguments.last.flatMap(Double.init) ?? 10
    let source = OryxHIDLayerSource()
    source.logKeyEvents = true
    source.onStatus = { Log.info("status: \($0.menuText)") }
    source.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        source.stop()
        exit(0)
    }
    RunLoop.main.run()
}

// `VoyagerView --render <layer> <out.png> [settings.json]`: draw the overlay for a layer from the cached
// layout into a PNG, without showing a window. Handy for checking the drawing without a screen recording.
if let i = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > i + 2 {
    let args = Array(CommandLine.arguments[(i + 1)...])
    MainActor.assumeIsolated {
        OverlaySnapshot.render(layer: Int(args[0]) ?? 1, to: URL(fileURLWithPath: args[1]),
                               settingsPath: args.count > 2 ? args[2] : nil)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
