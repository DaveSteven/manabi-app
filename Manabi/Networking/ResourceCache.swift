import Foundation
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

/// One shared instance owns these directories. Media is public content; ownership labels
/// should include account + paper identifiers, never tokens. No study records are stored here.
actor ResourceCache {
    static let shared: ResourceCache = {
        let fm = FileManager.default
        return ResourceCache(
            automaticDirectory: fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ManabiMedia"),
            persistentDirectory: fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ManabiMedia"))
    }()

    typealias Downloader = @Sendable (URL) async throws -> (URL, HTTPURLResponse)
    struct Usage: Sendable { let automaticBytes: Int64; let downloadedBytes: Int64 }
    private struct Entry: Codable {
        var resource: MediaResource
        var owners: Set<String>
        var lastAccess: Date
    }
    private let automaticDirectory: URL
    private let persistentDirectory: URL
    private let downloader: Downloader
    private var entries: [String: Entry] = [:]
    private var loaded = false
    private var pending: [String: Task<URL, Error>] = [:]

    init(automaticDirectory: URL, persistentDirectory: URL,
         downloader: @escaping Downloader = ResourceCache.download) {
        self.automaticDirectory = automaticDirectory
        self.persistentDirectory = persistentDirectory
        self.downloader = downloader
    }

    private static func download(_ url: URL) async throws -> (URL, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 60
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
            // Do not silently discard ownership when the index cannot be read.
            entries = try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: index))
        }
        for (key, entry) in entries {
            let legacy = (entry.owners.isEmpty ? automaticDirectory : persistentDirectory).appendingPathComponent(key)
            let destination = file(key, entry)
            if legacy != destination, fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: destination.path) {
                try fm.moveItem(at: legacy, to: destination)
            }
        }
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
        return (entry.owners.isEmpty ? automaticDirectory : persistentDirectory).appendingPathComponent(key).appendingPathExtension(suffix)
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
            // Preserve download ownership so a repair returns to persistent storage.
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        entry.lastAccess = Date()
        entries[key] = entry
        try save()
        return url
    }

    /// Cancellation of one caller never cancels another caller's shared download.
    /// A cancelled caller receives no URL; a completed file may remain as automatic cache.
    func fetch(_ resource: MediaResource, baseURL: URL, owner: String? = nil) async throws -> URL {
        try Task.checkCancellation()
        try prepare()
        let (key, remote) = try identity(resource, baseURL: baseURL)
        if try localURL(for: resource, baseURL: baseURL) == nil {
            let task: Task<URL, Error>
            if let existing = pending[key] { task = existing }
            else {
                task = Task { try await self.retrieve(resource, key: key, remote: remote) }
                pending[key] = task
            }
            _ = try await task.value
        }
        try Task.checkCancellation()
        guard var entry = entries[key] else { throw ResourceCacheError.invalidResource }
        if let owner, !owner.isEmpty, !entry.owners.contains(owner) {
            let old = file(key, entry)
            let wasAutomatic = entry.owners.isEmpty
            entry.owners.insert(owner)
            let destination = file(key, entry)
            if wasAutomatic {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: old, to: destination)
            }
            let previous = entries[key]
            entries[key] = entry
            do { try save() }
            catch { entries[key] = previous; throw error }
            if wasAutomatic { try? FileManager.default.removeItem(at: old) }
        }
        return file(key, entry)
    }

    private func retrieve(_ resource: MediaResource, key: String, remote: URL) async throws -> URL {
        defer { pending[key] = nil }
        for attempt in 0..<3 {
            do {
                let (temporary, response) = try await downloader(remote)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard response.statusCode == 200 else { throw ResourceCacheError.http(response.statusCode) }
                try Self.verify(temporary, resource: resource)
                let entry = Entry(resource: resource, owners: entries[key]?.owners ?? [], lastAccess: Date())
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

    func usage() throws -> Usage {
        try prepare()
        var automatic: Int64 = 0
        var downloaded: Int64 = 0
        for (key, entry) in entries where FileManager.default.fileExists(atPath: file(key, entry).path) {
            if entry.owners.isEmpty { automatic += entry.resource.byteSize }
            else { downloaded += entry.resource.byteSize }
        }
        return Usage(automaticBytes: automatic, downloadedBytes: downloaded)
    }
}
