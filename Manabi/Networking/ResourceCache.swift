import Foundation
import Network
import Observation
import CryptoKit
import UniformTypeIdentifiers

struct MediaResource: Codable, Sendable, Equatable {
    let id: String
    let kind: String
    let url: String
    let mimeType: String
    let byteSize: Int64
    let sha256: String
}

struct ExamResources: Decodable, Sendable {
    let examId: String
    let items: [MediaResource]
    let resourceCount: Int
    let totalBytes: Int64
}

enum ResourceCacheError: Error {
    case invalidResource, invalidResponse, checksumMismatch, http(Int)
}

/// Shared automatic media cache. The support directory contains only the durable index;
/// legacy explicit downloads are moved to the cache directory during preparation.
actor ResourceCache {
    static let shared: ResourceCache = {
        let fm = FileManager.default
        return ResourceCache(
            automaticDirectory: fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ManabiMedia"),
            persistentDirectory: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ManabiMedia"),
            prefetchDownloader: ResourceCache.downloadWiFi)
    }()

    typealias Downloader = @Sendable (URL) async throws -> (URL, HTTPURLResponse)
    struct Usage: Sendable {
        let totalBytes: Int64
        var audioBytes: Int64 = 0
        var imageBytes: Int64 = 0
    }
    private struct Entry: Codable {
        var resource: MediaResource
        var owners: Set<String>? = nil // Legacy download migration only.
        var lastAccess: Date
        var retained: Bool? = nil
    }
    private let automaticDirectory: URL
    private let persistentDirectory: URL
    private let downloader: Downloader
    private let prefetchDownloader: Downloader
    private var entries: [String: Entry] = [:]
    private var loaded = false
    private var pending: [String: Task<URL, Error>] = [:]

    private var foreground = Set<String>()
    private var scopes: [String: Set<UUID>] = [:]
    private var active = Set<String>()
    private var waiting: [(String, CheckedContinuation<Void, Error>)] = []
    private var protections: [UUID: (URL, Set<String>)] = [:]
    private var grace: [String: Date] = [:]

    init(automaticDirectory: URL, persistentDirectory: URL,
         prefetchDownloader: Downloader? = nil,
         downloader: @escaping Downloader = ResourceCache.download) {
        self.automaticDirectory = automaticDirectory
        self.persistentDirectory = persistentDirectory
        self.downloader = downloader
        self.prefetchDownloader = prefetchDownloader ?? downloader
    }

    private static func download(_ url: URL) async throws -> (URL, HTTPURLResponse) {
        try await transfer(url, wifiOnly: false)
    }

    private static func downloadWiFi(_ url: URL) async throws -> (URL, HTTPURLResponse) {
        try await transfer(url, wifiOnly: true)
    }

    private static func transfer(_ url: URL, wifiOnly: Bool) async throws -> (URL, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 60
        if wifiOnly {
            request.allowsCellularAccess = false
            request.allowsExpensiveNetworkAccess = false
            request.allowsConstrainedNetworkAccess = false
        }
        let (file, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: file)
            throw ResourceCacheError.invalidResponse
        }
        return (file, http)
    }

    private func prepare() throws {
        guard !loaded else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: automaticDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: persistentDirectory, withIntermediateDirectories: true)
        var directory = persistentDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let index = persistentDirectory.appendingPathComponent("index.json")
        if fm.fileExists(atPath: index.path) {
            // Preserve index errors rather than silently losing track of existing files.
            entries = try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: index))
        }
        var migrated = false
        for (key, var entry) in entries {
            let destination = file(key, entry)
            let oldDirectory = entry.owners?.isEmpty == false || entry.retained == true ? persistentDirectory : automaticDirectory
            let candidates = [oldDirectory.appendingPathComponent(destination.lastPathComponent), oldDirectory.appendingPathComponent(key)]
            for old in candidates where old != destination && fm.fileExists(atPath: old.path) {
                if fm.fileExists(atPath: destination.path) {
                    // A previous interrupted migration may already have copied the same file.
                    if (try? Self.verify(destination, resource: entry.resource)) != nil {
                        try fm.removeItem(at: old)
                    } else {
                        try fm.removeItem(at: destination)
                        try fm.moveItem(at: old, to: destination)
                    }
                } else { try fm.moveItem(at: old, to: destination) }
            }
            if entry.owners != nil || entry.retained != nil {
                entry.owners = nil; entry.retained = nil; entries[key] = entry; migrated = true
            }
        }
        if migrated { try save() }
        loaded = true
    }

    private func save() throws {
        try JSONEncoder().encode(entries).write(to: persistentDirectory.appendingPathComponent("index.json"), options: .atomic)
    }

    private func identity(_ resource: MediaResource, baseURL: URL) throws -> (String, URL) {
        let base = try APIClient.validatedURL(baseURL.absoluteString)
        guard ["audio", "image"].contains(resource.kind), resource.byteSize > 0,
              resource.sha256.count == 64,
              resource.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              let url = URL(string: resource.url, relativeTo: base)?.absoluteURL,
              url.scheme == base.scheme, url.host == base.host, url.port == base.port,
              url.user == nil, url.password == nil, url.fragment == nil,
              url.path == "/api/v1/assets/\(resource.id)" else { throw ResourceCacheError.invalidResource }
        let bytes = Data("\(base.absoluteString)|\(resource.id)|\(resource.sha256)".utf8)
        let key = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return (key, url)
    }

    private func file(_ key: String, _ entry: Entry) -> URL {
        let suffix: String
        switch entry.resource.mimeType.lowercased() {
        case "audio/x-caf", "audio/caf": suffix = "caf"
        case "audio/mpeg": suffix = "mp3"
        default: suffix = UTType(mimeType: entry.resource.mimeType)?.preferredFilenameExtension ?? "bin"
        }
        return automaticDirectory.appendingPathComponent(key).appendingPathExtension(suffix)
    }

    private static func verify(_ file: URL, resource: MediaResource) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: Int64 = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            size += Int64(data.count)
            guard size <= resource.byteSize else { throw ResourceCacheError.checksumMismatch }
            hash.update(data: data)
        }
        guard size == resource.byteSize,
              hash.finalize().map({ String(format: "%02x", $0) }).joined() == resource.sha256 else {
            throw ResourceCacheError.checksumMismatch
        }
    }

    func localURL(for resource: MediaResource, baseURL: URL) throws -> URL? {
        try prepare()
        let (key, _) = try identity(resource, baseURL: baseURL)
        guard var entry = entries[key] else { return nil }
        let url = file(key, entry)
        do { try Self.verify(url, resource: resource) }
        catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        entry.lastAccess = Date()
        entries[key] = entry
        try save()
        return url
    }

    /// Foreground requests share existing work; speculative scopes can cancel independently.
    func fetch(_ resource: MediaResource, baseURL: URL, prefetchScope: UUID? = nil) async throws -> URL {
        try Task.checkCancellation()
        try prepare()
        let (key, remote) = try identity(resource, baseURL: baseURL)
        if prefetchScope == nil { grace[key] = Date().addingTimeInterval(120) }
        if try localURL(for: resource, baseURL: baseURL) == nil {
            if let prefetchScope { scopes[key, default: []].insert(prefetchScope) }
            if prefetchScope == nil { foreground.insert(key); pump() }
            let task: Task<URL, Error>
            if let existing = pending[key] { task = existing }
            else {
                task = Task { try await self.retrieve(resource, key: key, remote: remote) }
                pending[key] = task
            }
            _ = try await task.value
        }
        try Task.checkCancellation()
        guard let entry = entries[key] else { throw ResourceCacheError.invalidResource }
        return file(key, entry)
    }

    private func retrieve(_ resource: MediaResource, key: String, remote: URL) async throws -> URL {
        defer {
            pending[key] = nil; scopes[key] = nil; foreground.remove(key)
            active.remove(key); pump()
        }
        try await acquire(key)
        try Task.checkCancellation()
        for attempt in 0..<3 {
            do {
                let transfer = foreground.contains(key) ? downloader : prefetchDownloader
                let (temporary, response) = try await transfer(remote)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Task.checkCancellation()
                guard response.statusCode == 200 else { throw ResourceCacheError.http(response.statusCode) }
                try Self.verify(temporary, resource: resource)
                let entry = Entry(resource: resource, lastAccess: Date())
                let destination = file(key, entry)
                // Staging on the destination volume keeps final publication atomic.
                let staging = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".partial")
                defer { try? FileManager.default.removeItem(at: staging) }
                try FileManager.default.copyItem(at: temporary, to: staging)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: staging, to: destination)
                let previous = entries[key]
                entries[key] = entry
                do { try save() }
                catch { entries[key] = previous; try? FileManager.default.removeItem(at: destination); throw error }
                return destination
            } catch {
                let retryable: Bool
                if case ResourceCacheError.http(let code) = error { retryable = (500...599).contains(code) }
                else if let network = error as? URLError { retryable = [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(network.code) }
                else { retryable = false }
                guard attempt < 2, retryable else { throw error }
                try await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
            }
        }
        throw ResourceCacheError.invalidResponse
    }

    // Two media transfers total; at most one speculative transfer. Waiting foreground
    // work is admitted first, reserving bandwidth for the currently visible question.
    private func acquire(_ key: String) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waiting.append((key, continuation))
                pump()
            }
        } onCancel: { Task { await self.cancelWaiting(key) } }
    }

    private func cancelWaiting(_ key: String) {
        if let index = waiting.firstIndex(where: { $0.0 == key }) {
            waiting.remove(at: index).1.resume(throwing: CancellationError())
        }
        pump()
    }

    private func pump() {
        while active.count < 2 {
            let index = waiting.firstIndex(where: { foreground.contains($0.0) })
                ?? (active.contains(where: { !foreground.contains($0) }) ? nil : waiting.indices.first)
            guard let index else { return }
            let (key, continuation) = waiting.remove(at: index)
            active.insert(key)
            continuation.resume()
        }
    }

    func cancelPrefetch(scope: UUID) {
        for (key, values) in scopes where values.contains(scope) {
            scopes[key]?.remove(scope)
            if scopes[key]?.isEmpty == true && !foreground.contains(key) { pending[key]?.cancel() }
        }
    }

    func protect(scope: UUID, baseURL: URL, paths: Set<String>) {
        protections[scope] = (baseURL, paths)
    }

    func releaseProtection(scope: UUID) { protections[scope] = nil }

    private func protected(_ key: String, entry: Entry) -> Bool {
        if pending[key] != nil || (grace[key] ?? .distantPast) > Date() { return true }
        return protections.values.contains { base, paths in
            guard let (expected, url) = try? identity(entry.resource, baseURL: base) else { return false }
            return expected == key && paths.contains(url.path)
        }
    }

    /// Offline fallback for an already opened question whose API URL has no version.
    func existingURL(for remote: URL, baseURL: URL) throws -> URL? {
        try prepare()
        guard remote.scheme == baseURL.scheme, remote.host == baseURL.host,
              remote.port == baseURL.port else { throw ResourceCacheError.invalidResource }
        for entry in entries.values.sorted(by: { $0.lastAccess > $1.lastAccess }) {
            guard let resolved = URL(string: entry.resource.url, relativeTo: baseURL)?.absoluteURL,
                  resolved.path == remote.path,
                  let (key, _) = try? identity(entry.resource, baseURL: baseURL), entries[key] != nil else { continue }
            if let local = try localURL(for: entry.resource, baseURL: baseURL) { return local }
        }
        return nil
    }

    func clearAutomatic() throws {
        try prepare()
        for (key, entry) in entries where !protected(key, entry: entry) {
            let path = file(key, entry)
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
            entries[key] = nil; grace[key] = nil
        }
        try save()
    }

    func usage() throws -> Usage {
        try prepare()
        var total: Int64 = 0
        var audio: Int64 = 0
        var images: Int64 = 0
        for (key, entry) in entries where FileManager.default.fileExists(atPath: file(key, entry).path) {
            total += entry.resource.byteSize
            if entry.resource.kind == "audio" { audio += entry.resource.byteSize }
            else { images += entry.resource.byteSize }
        }
        return Usage(totalBytes: total, audioBytes: audio, imageBytes: images)
    }
}


@MainActor @Observable
final class MediaNetwork {
    static let shared = MediaNetwork()
    private(set) var permitsPrefetch = false
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let allowed = path.status == .satisfied && path.usesInterfaceType(.wifi)
                && !path.isExpensive && !path.isConstrained
            Task { @MainActor [weak self] in self?.permitsPrefetch = allowed }
        }
        monitor.start(queue: DispatchQueue(label: "app.manabi.media-network"))
    }
}
