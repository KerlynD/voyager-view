import AppKit
import ServiceManagement
import SwiftUI
import VoyagerCore

final class SettingsModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { onChange?(settings) } }
    }
    @Published var layers: [(position: Int, title: String)] = []
    @Published var layoutStatus = ""
    // View-local state lives here: Command Line Tools ship no SwiftUI macro plugin, so @State won't compile.
    @Published var hashIdDraft = ""
    @Published var launchAtLogin = false
    @Published var launchError: String?
    var onChange: ((AppSettings) -> Void)?
    var onReloadLayout: (() -> Void)?

    init(settings: AppSettings) { self.settings = settings }

    /// Update from outside (hot reload) without echoing back through onChange.
    func replace(_ s: AppSettings) {
        let cb = onChange
        onChange = nil
        settings = s
        onChange = cb
    }
}

final class SettingsWindowController {
    private var window: NSWindow?
    let model: SettingsModel

    init(model: SettingsModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "VoyagerView Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Look") {
                slider("Overall opacity", $model.settings.overallOpacity, AppSettings.opacityRange, percent: true)
                slider("Background opacity", $model.settings.backgroundOpacity, AppSettings.fillOpacityRange, percent: true)
                slider("Key fill opacity", $model.settings.keyFillOpacity, AppSettings.fillOpacityRange, percent: true)
                slider("Label opacity", $model.settings.labelOpacity, AppSettings.opacityRange, percent: true)
                slider("Size", $model.settings.scale, AppSettings.scaleRange, percent: true)
                Picker("Theme", selection: $model.settings.theme) {
                    Text("Dark").tag(AppSettings.Theme.dark)
                    Text("Light").tag(AppSettings.Theme.light)
                }
                Picker("Accent", selection: $model.settings.accentMode) {
                    Text("Layer color").tag(AppSettings.AccentMode.layerColor)
                    Text("Custom").tag(AppSettings.AccentMode.custom)
                }
                if model.settings.accentMode == .custom {
                    ColorPicker("Custom accent", selection: Binding(
                        get: { Color(hex: model.settings.customAccentHex) ?? .blue },
                        set: { model.settings.customAccentHex = $0.hexString ?? model.settings.customAccentHex }
                    ), supportsOpacity: false)
                }
                Toggle("Show hold labels", isOn: $model.settings.showHoldLabels)
                Picker("Transparent keys", selection: $model.settings.transparentKeys) {
                    Text("Dim (show base layer)").tag(AppSettings.TransparentKeyStyle.dim)
                    Text("Blank").tag(AppSettings.TransparentKeyStyle.blank)
                }
                Toggle("Highlight pressed keys", isOn: $model.settings.highlightPressedKeys)
            }

            Section("Position") {
                Picker("Position", selection: $model.settings.position) {
                    ForEach(AppSettings.Position.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                slider("X offset", $model.settings.offsetX, -1000...1000, step: 1, unit: "pt")
                slider("Y offset", $model.settings.offsetY, -1000...1000, step: 1, unit: "pt")
            }

            Section("Behavior") {
                slider("Show delay", $model.settings.showDelayMs, 0...500, step: 5, unit: "ms")
                slider("Fade duration", $model.settings.fadeDurationMs, 0...500, step: 5, unit: "ms")
                slider("Auto-hide after", $model.settings.autoHideSeconds, 0...30, step: 1, unit: "s", zeroLabel: "Off")
                Picker("Base layer", selection: $model.settings.baseLayer) {
                    ForEach(layerChoices, id: \.position) { l in
                        Text("\(l.position) · \(l.title)").tag(l.position)
                    }
                }
            }

            Section("Never show for these layers") {
                ForEach(layerChoices.filter { $0.position != model.settings.baseLayer }, id: \.position) { l in
                    Toggle("\(l.position) · \(l.title)", isOn: Binding(
                        get: { model.settings.hiddenLayers.contains(l.position) },
                        set: { on in
                            var h = Set(model.settings.hiddenLayers)
                            if on { h.insert(l.position) } else { h.remove(l.position) }
                            model.settings.hiddenLayers = h.sorted()
                        }
                    ))
                }
            }

            Section("Layout") {
                HStack {
                    TextField("Oryx layout hash ID", text: $model.hashIdDraft)
                        .onSubmit(applyHashId)
                    Button("Apply", action: applyHashId)
                        .disabled(model.hashIdDraft.trimmingCharacters(in: .whitespaces) == model.settings.layoutHashId)
                }
                HStack {
                    Text(model.layoutStatus).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button("Reload layout") { model.onReloadLayout?() }
                }
            }

            Section("Advanced") {
                Picker("Window level", selection: $model.settings.windowLevel) {
                    Text("Shielding (default, over captured displays)").tag(AppSettings.WindowLevel.shielding)
                    Text("Screen saver").tag(AppSettings.WindowLevel.screenSaver)
                    Text("Pop-up menu").tag(AppSettings.WindowLevel.popUpMenu)
                    Text("Status bar").tag(AppSettings.WindowLevel.statusBar)
                    Text("Floating").tag(AppSettings.WindowLevel.floating)
                    Text("Custom").tag(AppSettings.WindowLevel.custom)
                }
                if model.settings.windowLevel == .custom {
                    TextField("Custom level", value: $model.settings.customWindowLevel, format: .number)
                }
                Toggle("Log key events", isOn: $model.settings.logKeyEvents)
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let error = model.launchError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Button("Open config folder") { NSWorkspace.shared.open(AppPaths.supportDir) }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 500)
        .onAppear {
            model.hashIdDraft = model.settings.layoutHashId
            model.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: model.settings.layoutHashId) { _, new in model.hashIdDraft = new }
    }

    private var layerChoices: [(position: Int, title: String)] {
        model.layers.isEmpty ? (0..<4).map { ($0, "Layer \($0)") } : model.layers
    }

    private func applyHashId() {
        let id = model.hashIdDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id != model.settings.layoutHashId else { return }
        model.settings.layoutHashId = id
    }

    private func setLaunchAtLogin(_ on: Bool) {
        model.launchError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            model.launchError = Bundle.main.bundleURL.pathExtension == "app"
                ? "Couldn't change login item: \(error.localizedDescription)"
                : "Launch at login only works from the bundled VoyagerView.app (scripts/bundle.sh)."
        }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            model.launchError = "Approve VoyagerView in System Settings → General → Login Items."
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        step: Double? = nil, percent: Bool = false, unit: String = "", zeroLabel: String? = nil) -> some View {
        HStack {
            Text(title)
            if let step {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }
            Text(format(value.wrappedValue, percent: percent, unit: unit, zeroLabel: zeroLabel))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ v: Double, percent: Bool, unit: String, zeroLabel: String?) -> String {
        if let zeroLabel, v == 0 { return zeroLabel }
        if percent { return "\(Int((v * 100).rounded()))%" }
        return "\(Int(v.rounded())) \(unit)"
    }
}

extension AppSettings.Position {
    var label: String {
        switch self {
        case .center: return "Center"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}

extension Color {
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
