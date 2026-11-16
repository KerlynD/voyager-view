import Foundation
import VoyagerCore

/// Persists AppSettings to config.json and hot-reloads it when edited by hand. Main thread only.
final class ConfigStore {
    private(set) var settings: AppSettings
    /// Called when the file changed on disk (not for our own saves).
    var onExternalChange: ((AppSettings) -> Void)?

    private let url: URL
    private var lastWritten: Data?
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?

    init(url: URL = AppPaths.config) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            settings = AppSettings.decodeLenient(data)
            lastWritten = data
            Log.info("Loaded settings from \(url.path)")
        } else {
            settings = .defaults
            Log.info("No config yet, writing defaults to \(url.path)")
        }
        save()
        watch()
    }

    func update(_ new: AppSettings) {
        let n = new.normalized()
        guard n != settings else { return }
        settings = n
        save()
    }

    private func save() {
        guard let data = try? settings.encodedJSON() else { return }
        guard data != lastWritten || !FileManager.default.fileExists(atPath: url.path) else { return }
        lastWritten = data
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("Couldn't save settings: \(error.localizedDescription)")
        }
        armFileWatcher()
    }

    // MARK: Watching

    /// Watch the directory (catches atomic replace, which most editors do) and the file itself (in-place writes).
    private func watch() {
        let dirFD = open(url.deletingLastPathComponent().path, O_EVTONLY)
        if dirFD >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: [.write], queue: .main)
            src.setEventHandler { [weak self] in self?.scheduleReload() }
            src.setCancelHandler { close(dirFD) }
            src.resume()
            dirSource = src
        }
        armFileWatcher()
    }

    private func armFileWatcher() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.scheduleReload() }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reloadFromDisk() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func reloadFromDisk() {
        armFileWatcher()
        guard let data = try? Data(contentsOf: url), data != lastWritten else { return }
        lastWritten = data
        let decoded = AppSettings.decodeLenient(data)
        guard decoded != settings else { return }
        settings = decoded
        Log.info("config.json changed on disk, reloaded")
        onExternalChange?(decoded)
    }
}
