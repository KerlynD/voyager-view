import AppKit
import SwiftUI
import VoyagerCore

enum OverlaySnapshot {
    @MainActor
    static func render(layer: Int, to url: URL, settingsPath: String?) {
        struct Cache: Decodable { let layout: OryxLayout }
        let layout = (try? Data(contentsOf: AppPaths.layoutCache))
            .flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }?.layout
        var settings = AppSettings.defaults
        if let settingsPath, let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)) {
            settings = AppSettings.decodeLenient(data)
        }
        let model = OverlayModel()
        model.settings = settings
        if let layout {
            model.caps = KeyLabeler.caps(forLayer: layer, in: layout, baseLayer: settings.baseLayer)
            model.layerTitle = layout.layer(at: layer)?.title ?? "Layer \(layer)"
            model.layerColorHex = layout.layer(at: layer)?.color
            model.hasLayout = true
        } else {
            model.layerTitle = "Layer \(layer)"
        }
        // Put something behind it so transparency is visible.
        let view = KeyboardOverlayView(model: model)
            .padding(30)
            .background(LinearGradient(colors: [.green.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { Log.error("render failed"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        Log.info("Rendered layer \(layer) to \(url.path)")
    }
}
