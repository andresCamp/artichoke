import Foundation

/// File-backed store for the `FilterDocument` in the App Group container.
/// Atomic writes; the extension only ever reads. Reads are cheap and cached
/// with a short TTL so the per-flow hot path doesn't hit disk every time.
/// All access is serialized on `queue`, so the type is safe to share.
final class SharedStore: @unchecked Sendable {
    static let shared = SharedStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.serdna.hotspotguard.store")
    private var cached: FilterDocument?
    private var cachedAt: Date = .distantPast
    private let ttl: TimeInterval = 0.5

    private init() {
        let dir = AppGroup.containerURL ?? FileManager.default.temporaryDirectory
        fileURL = dir.appendingPathComponent("filter.json")
    }

    /// Hot-path read used by the extension. Cached for `ttl` seconds.
    func loadCached() -> FilterDocument {
        queue.sync {
            if let cached, Date().timeIntervalSince(cachedAt) < ttl {
                return cached
            }
            let doc = readFromDisk()
            cached = doc
            cachedAt = Date()
            return doc
        }
    }

    /// Fresh read, bypassing the cache (used by the app).
    func load() -> FilterDocument {
        queue.sync { readFromDisk() }
    }

    func save(_ doc: FilterDocument) {
        queue.sync {
            guard let data = try? JSONEncoder().encode(doc) else { return }
            try? data.write(to: fileURL, options: .atomic)
            cached = doc
            cachedAt = Date()
        }
    }

    /// Read-modify-write under the store's serial queue.
    func mutate(_ block: (inout FilterDocument) -> Void) {
        queue.sync {
            var doc = readFromDisk()
            block(&doc)
            if let data = try? JSONEncoder().encode(doc) {
                try? data.write(to: fileURL, options: .atomic)
            }
            cached = doc
            cachedAt = Date()
        }
    }

    private func readFromDisk() -> FilterDocument {
        guard
            let data = try? Data(contentsOf: fileURL),
            let doc = try? JSONDecoder().decode(FilterDocument.self, from: data)
        else { return FilterDocument() }
        return doc
    }
}
