import AppKit
import VoyagerCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private let config = ConfigStore()
    private let layouts = LayoutStore()
    private let overlay = OverlayController()
    private let hid = OryxHIDLayerSource()
    private var demo: DemoLayerSource?
    private lazy var settingsModel = SettingsModel(settings: config.settings)
    private lazy var settingsWindow = SettingsWindowController(model: settingsModel)

    private var hidStatus: LayerSourceStatus = .idle
    private var hidLayer = 0
    private var signalSources: [DispatchSourceSignal] = []
    /// Keeps App Nap from coalescing our timers. Without it, a windowless menu bar app gets its
    /// show-delay timer fired 100–900 ms late.
    private var latencyActivity: NSObjectProtocol?

    // Menu items that change
    private let statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let layoutLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Open Input Monitoring Settings…", action: #selector(openInputMonitoring), keyEquivalent: "")
    private let testItem = NSMenuItem(title: "Show test overlay", action: #selector(toggleTestOverlay), keyEquivalent: "t")
    private let demoItem = NSMenuItem(title: "Demo mode", action: #selector(toggleDemo), keyEquivalent: "d")
    private let levelTestItem = NSMenuItem(title: "Window level test (demo)", action: #selector(toggleLevelTest), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        latencyActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Showing keyboard layer overlay with low latency")
        buildMenu()

        overlay.apply(settings: config.settings)
        hid.logKeyEvents = config.settings.logKeyEvents

        config.onExternalChange = { [weak self] s in
            guard let self else { return }
            self.settingsModel.replace(s)
            self.settingsChanged(s, persist: false)
        }
        settingsModel.onChange = { [weak self] s in self?.settingsChanged(s, persist: true) }
        settingsModel.onReloadLayout = { [weak self] in self?.reloadLayout() }

        layouts.onChange = { [weak self] layout in
            guard let self else { return }
            self.overlay.setLayout(layout)
            self.settingsModel.layers = layout?.layers.map { ($0.position, $0.title) } ?? []
            self.updateMenu()
        }
        layouts.start(hashId: config.settings.layoutHashId)

        hid.onStatus = { [weak self] s in
            self?.hidStatus = s
            self?.updateMenu()
        }
        hid.onLayer = { [weak self] layer in
            guard let self else { return }
            self.hidLayer = layer
            if self.demo == nil { self.overlay.layerChanged(layer) }
            self.updateMenu()
        }
        hid.onKey = { [weak self] index, down in
            guard let self, self.demo == nil else { return }
            self.overlay.keyEvent(index: index, down: down)
        }
        hid.start()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        installSignalHandlers()

        if CommandLine.arguments.contains("--demo") { toggleDemo() }
        if CommandLine.arguments.contains("--level-test") { toggleLevelTest() }
        if CommandLine.arguments.contains("--test-overlay") { toggleTestOverlay() }
        updateMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hid.stop()
    }

    // MARK: Settings

    /// The settings currently in effect (what the overlay and HID source were last given).
    private lazy var applied = config.settings

    private func settingsChanged(_ new: AppSettings, persist: Bool) {
        let s = new.normalized()
        let old = applied
        applied = s
        if persist { config.update(s) }
        overlay.apply(settings: s)
        hid.logKeyEvents = s.logKeyEvents
        if old.layoutHashId != s.layoutHashId {
            layouts.reload(hashId: s.layoutHashId)
        }
        updateMenu()
    }

    // MARK: Menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "VoyagerView")
            button.image?.isTemplate = true
        }
        statusLine.isEnabled = false
        layoutLine.isEnabled = false
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(statusLine)
        menu.addItem(layoutLine)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(testItem)
        menu.addItem(demoItem)
        menu.addItem(levelTestItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Reload layout", action: #selector(reloadLayoutAction), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit VoyagerView", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) { updateMenu() }

    private func updateMenu() {
        var line = demo != nil ? "Demo mode" : hidStatus.menuText
        if demo == nil, case .paired = hidStatus {
            let title = layouts.layout?.layer(at: hidLayer)?.title ?? "\(hidLayer)"
            line += " · layer: \(title)"
        }
        statusLine.title = line
        layoutLine.title = layouts.statusText
        permissionItem.isHidden = hidStatus != .permissionDenied
        testItem.state = overlay.isTestOverlayOn ? .on : .off
        demoItem.state = demo != nil && !overlay.cycleWindowLevels ? .on : .off
        levelTestItem.state = overlay.cycleWindowLevels ? .on : .off
        settingsModel.layoutStatus = layouts.statusText
    }

    // MARK: Actions

    @objc private func toggleTestOverlay() {
        overlay.setTestOverlay(!overlay.isTestOverlayOn)
        updateMenu()
    }

    @objc private func toggleDemo() {
        if let d = demo {
            d.stop()
            demo = nil
            overlay.cycleWindowLevels = false
            overlay.layerChanged(hidLayer)
            Log.info("Demo mode off")
        } else {
            let d = DemoLayerSource(layerCount: layouts.layout?.layers.count ?? 4)
            d.onLayer = { [weak self] layer in self?.overlay.layerChanged(layer) }
            demo = d
            d.start()
            Log.info("Demo mode on")
        }
        updateMenu()
    }

    /// Demo mode that uses a different window level every time the overlay appears and prints its name,
    /// so you can see from inside a fullscreen game which levels make it on screen.
    @objc private func toggleLevelTest() {
        if overlay.cycleWindowLevels {
            toggleDemo() // turns demo and the level cycle off
        } else {
            if demo == nil { toggleDemo() }
            overlay.cycleWindowLevels = true
            Log.info("Window level test on")
        }
        updateMenu()
    }

    @objc private func openSettings() { settingsWindow.show() }

    @objc private func reloadLayoutAction() { reloadLayout() }

    private func reloadLayout() {
        layouts.reload(hashId: applied.layoutHashId)
        updateMenu()
    }

    @objc private func openInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Sleep / wake / signals

    @objc private func willSleep() {
        Log.info("Mac going to sleep")
        hid.prepareForSleep()
    }

    @objc private func didWake() {
        Log.info("Mac woke up, re-pairing")
        // Give USB a moment to come back before re-pairing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.hid.repair() }
    }

    /// Ctrl-C in the terminal or `kill`: send DISCONNECT before we stop reading.
    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                Log.info("Signal \(sig), shutting down")
                self?.hid.stop()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }
}
