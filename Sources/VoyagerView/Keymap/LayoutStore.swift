import Foundation
import VoyagerCore

/// Fetches the keymap from the Oryx GraphQL API and caches the last good copy. Main thread API.
final class LayoutStore {
    private(set) var layout: OryxLayout?
    private(set) var statusText = "Layout: not loaded"
    var onChange: ((OryxLayout?) -> Void)?

    private let cacheURL: URL
    private var currentTask: URLSessionDataTask?
    private static let endpoint = URL(string: "https://oryx.zsa.io/graphql")!

    init(cacheURL: URL = AppPaths.layoutCache) {
        self.cacheURL = cacheURL
    }

    private struct Cache: Codable {
        var hashId: String
        var fetchedAt: Date
        var layout: OryxLayout
    }

    /// Load the cached copy (if it's for this hash ID), then fetch a fresh one.
    func start(hashId: String) {
        if let cache = readCache(), cache.hashId == hashId {
            layout = cache.layout
            statusText = "Layout: \(cache.layout.title) (cached)"
            onChange?(layout)
        }
        reload(hashId: hashId)
    }

    func reload(hashId: String) {
        currentTask?.cancel()
        statusText = "Layout: loading \(hashId)…"
        Log.info("Fetching Oryx layout \(hashId)")

        var req = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "operationName": "getLayout",
            "variables": ["hashId": hashId, "revisionId": "latest", "geometry": "voyager"],
            "query": "query getLayout($hashId: String!, $revisionId: String!, $geometry: String) { layout(hashId: $hashId, geometry: $geometry, revisionId: $revisionId) { title geometry revision { hashId title qmkVersion layers { title position color keys } } } }",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let result: Result<OryxLayout, Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(NSError(domain: "Oryx", code: http.statusCode,
                                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
            } else {
                result = Result { try OryxLayout.decodeGraphQLResponse(data ?? Data()) }
            }
            DispatchQueue.main.async { self?.finish(hashId: hashId, result: result) }
        }
        currentTask = task
        task.resume()
    }

    private func finish(hashId: String, result: Result<OryxLayout, Error>) {
        switch result {
        case .success(let fresh):
            let changed = fresh != layout
            layout = fresh
            statusText = "Layout: \(fresh.title)"
            Log.info("Loaded layout \"\(fresh.title)\" with \(fresh.layers.count) layers: \(fresh.layers.map(\.title).joined(separator: ", "))")
            writeCache(Cache(hashId: hashId, fetchedAt: Date(), layout: fresh))
            if changed { onChange?(fresh) }
        case .failure(let error):
            if (error as NSError).code == NSURLErrorCancelled { return }
            let message = (error as? OryxLayout.LayoutError)?.description ?? error.localizedDescription
            Log.error("Layout fetch failed: \(message)")
            if let cache = readCache(), cache.hashId == hashId {
                if layout != cache.layout {
                    layout = cache.layout
                    onChange?(layout)
                }
                statusText = "Layout: \(cache.layout.title) (offline, cached)"
            } else {
                if layout != nil {
                    layout = nil
                    onChange?(nil)
                }
                statusText = "Layout: failed to load (\(message))"
            }
        }
    }

    private func readCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Cache.self, from: data)
    }

    private func writeCache(_ cache: Cache) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        do {
            try enc.encode(cache).write(to: cacheURL, options: .atomic)
        } catch {
            Log.error("Couldn't write layout cache: \(error.localizedDescription)")
        }
    }
}
