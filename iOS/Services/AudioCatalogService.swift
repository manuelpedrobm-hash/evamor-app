import AVFoundation
import CryptoKit
import Foundation
import Observation
import MeditationCore

struct AudioCatalogDocument: Codable, Equatable {
    var schemaVersion: Int
    var revision: String
    var tracks: [AudioCatalogTrack]
    var profiles: [CatalogSessionProfile]
}

struct AudioCatalogTrack: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var durationSeconds: Double
    var sha256: String
    var byteCount: Int
    var bundledResource: String?
    var downloadURL: URL?
    /// A standalone track (e.g. a full Group Sitting recording) already contains
    /// everything it needs: the session duration and built-in audio toggles are
    /// locked to match it instead of being offered as separate choices.
    var standalone: Bool?

    var reference: CatalogAudioReference {
        CatalogAudioReference(id: id, title: title, durationSeconds: durationSeconds)
    }
}

struct CatalogSessionProfile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var detail: String
    var minutes: Int
    var trackID: String?
    var builtInAudio: Set<AudioKind>?
}

struct SavedSessionProfile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var configuration: SessionConfiguration
}

enum AudioCatalogError: LocalizedError {
    case invalidCatalog, insecureURL, trackUnavailable, invalidDownload, checksumMismatch, invalidDuration

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: return "El catálogo de audios no es válido."
        case .insecureURL: return "El catálogo y los audios deben usar HTTPS."
        case .trackUnavailable: return "Este audio todavía no está disponible sin conexión."
        case .invalidDownload: return "El archivo descargado no es un audio válido."
        case .checksumMismatch: return "El audio descargado no coincide con el catálogo y se ha descartado."
        case .invalidDuration: return "La duración del audio descargado no coincide con el catálogo."
        }
    }
}

@MainActor @Observable final class AudioCatalogService {
    private(set) var document: AudioCatalogDocument
    private(set) var isRefreshing = false
    private(set) var isDownloading: Set<String> = []
    private(set) var lastUpdated: Date?
    private(set) var savedProfiles: [SavedSessionProfile]
    var message: String?
    var endpoint: String
    private var previewPlayer: AVAudioPlayer?
    @ObservationIgnored private var validatedURLs: [String: (hash: String, url: URL)] = [:]

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private static let endpointKey = "audioCatalogEndpoint"
    private static let profilesKey = "savedSessionProfiles"

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        endpoint = defaults.string(forKey: Self.endpointKey)
            ?? (Bundle.main.object(forInfoDictionaryKey: "EvamorAudioCatalogURL") as? String ?? "")
        if let data = defaults.data(forKey: Self.profilesKey),
           let profiles = try? JSONDecoder().decode([SavedSessionProfile].self, from: data) {
            savedProfiles = profiles
        } else {
            savedProfiles = []
        }
        document = Self.loadBundledCatalog()
        if let cached = try? Data(contentsOf: Self.cachedCatalogURL(fileManager: fileManager)),
           let decoded = try? JSONDecoder().decode(AudioCatalogDocument.self, from: cached),
           Self.isValid(decoded) {
            document = Self.merged(bundled: document, remote: decoded)
        }
    }

    var tracks: [AudioCatalogTrack] { document.tracks }
    var catalogProfiles: [CatalogSessionProfile] { document.profiles }
    func track(id: String) -> AudioCatalogTrack? { tracks.first { $0.id == id } }

    func localURL(for id: String) -> URL? {
        guard let track = track(id: id) else { return nil }
        if let validated = validatedURLs[id], validated.hash == track.sha256.lowercased(),
           fileManager.fileExists(atPath: validated.url.path) { return validated.url }
        if let cached = try? cachedAudioURL(for: track), fileManager.fileExists(atPath: cached.path),
           Self.sha256(cached) == track.sha256.lowercased() {
            validatedURLs[id] = (track.sha256.lowercased(), cached)
            return cached
        }
        guard let resource = track.bundledResource else { return nil }
        let name = (resource as NSString).deletingPathExtension
        let ext = (resource as NSString).pathExtension
        guard let bundled = Bundle.main.url(forResource: name, withExtension: ext),
              Self.sha256(bundled) == track.sha256.lowercased() else { return nil }
        validatedURLs[id] = (track.sha256.lowercased(), bundled)
        return bundled
    }

    func isAvailable(_ track: AudioCatalogTrack) -> Bool { localURL(for: track.id) != nil }

    func saveEndpoint(_ value: String) {
        endpoint = value.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(endpoint, forKey: Self.endpointKey)
    }

    func refresh() async {
        guard !endpoint.isEmpty else {
            message = "Añade una dirección HTTPS para recibir audios nuevos sin actualizar la app."
            return
        }
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https" else {
            message = AudioCatalogError.insecureURL.localizedDescription
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard data.count <= 2_000_000,
                  (response as? HTTPURLResponse)?.statusCode == 200 else { throw AudioCatalogError.invalidCatalog }
            let remote = try JSONDecoder().decode(AudioCatalogDocument.self, from: data)
            guard Self.isValid(remote) else { throw AudioCatalogError.invalidCatalog }
            for track in remote.tracks {
                if let downloadURL = track.downloadURL, downloadURL.scheme?.lowercased() != "https" {
                    throw AudioCatalogError.insecureURL
                }
            }
            let destination = Self.cachedCatalogURL(fileManager: fileManager)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            document = Self.merged(bundled: Self.loadBundledCatalog(), remote: remote)
            lastUpdated = .now
            message = "Catálogo actualizado · \(remote.revision)"
        } catch {
            message = "No se pudo actualizar el catálogo. Se mantienen los audios disponibles. \(error.localizedDescription)"
        }
    }

    @discardableResult func download(_ track: AudioCatalogTrack) async throws -> URL {
        if let local = localURL(for: track.id) { return local }
        guard let source = track.downloadURL, source.scheme?.lowercased() == "https" else {
            throw AudioCatalogError.trackUnavailable
        }
        isDownloading.insert(track.id)
        defer { isDownloading.remove(track.id) }
        let (temporary, response) = try await URLSession.shared.download(from: source)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AudioCatalogError.invalidDownload }
        let values = try temporary.resourceValues(forKeys: [.fileSizeKey])
        guard values.fileSize == track.byteCount, Self.sha256(temporary) == track.sha256.lowercased() else {
            throw AudioCatalogError.checksumMismatch
        }
        let asset = AVURLAsset(url: temporary)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, abs(duration - track.durationSeconds) < 1 else { throw AudioCatalogError.invalidDuration }
        let destination = try cachedAudioURL(for: track)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: temporary, to: destination)
        validatedURLs[track.id] = (track.sha256.lowercased(), destination)
        return destination
    }

    func togglePreview(_ track: AudioCatalogTrack) async {
        if previewPlayer?.isPlaying == true { stopPreview(); return }
        do {
            let url = try await download(track)
            try await AudioSessionSupport.activate(mode: .spokenAudio)
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.currentTime = 0
            previewPlayer?.prepareToPlay()
            previewPlayer?.play()
        } catch { message = error.localizedDescription }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        AudioSessionSupport.deactivate()
    }

    func saveProfile(name: String, configuration: SessionConfiguration) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedProfiles.append(.init(id: UUID().uuidString.lowercased(), name: String(trimmed.prefix(60)), configuration: configuration))
        persistSavedProfiles()
    }

    func deleteProfile(id: String) {
        savedProfiles.removeAll { $0.id == id }
        persistSavedProfiles()
    }

    private func persistSavedProfiles() {
        guard let data = try? JSONEncoder().encode(savedProfiles) else { return }
        defaults.set(data, forKey: Self.profilesKey)
    }

    private func cachedAudioURL(for track: AudioCatalogTrack) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let ext = track.downloadURL?.pathExtension.nonEmpty ?? "m4a"
        return base.appendingPathComponent("AudioCatalog", isDirectory: true)
            .appendingPathComponent("\(track.id).\(ext)")
    }

    private static func cachedCatalogURL(fileManager: FileManager) -> URL {
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("AudioCatalog/catalog.json")
    }

    private static func loadBundledCatalog() -> AudioCatalogDocument {
        guard let url = Bundle.main.url(forResource: "AudioCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(AudioCatalogDocument.self, from: data) else {
            return .init(schemaVersion: 1, revision: "bundled-empty", tracks: [], profiles: [])
        }
        return value
    }

    private static func isValid(_ document: AudioCatalogDocument) -> Bool {
        guard document.schemaVersion == 1, !document.revision.isEmpty else { return false }
        let ids = document.tracks.map(\.id)
        guard Set(ids).count == ids.count else { return false }
        return document.tracks.allSatisfy {
            !$0.id.isEmpty && !$0.title.isEmpty && $0.durationSeconds > 0 &&
            $0.byteCount > 0 && $0.sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil
        } && document.profiles.allSatisfy { profile in
            (5...480).contains(profile.minutes) && (profile.trackID == nil || ids.contains(profile.trackID!))
        }
    }

    private static func merged(bundled: AudioCatalogDocument, remote: AudioCatalogDocument) -> AudioCatalogDocument {
        var tracks = Dictionary(uniqueKeysWithValues: bundled.tracks.map { ($0.id, $0) })
        for remoteTrack in remote.tracks {
            var value = remoteTrack
            if value.bundledResource == nil { value.bundledResource = tracks[value.id]?.bundledResource }
            tracks[value.id] = value
        }
        let profiles = Dictionary((bundled.profiles + remote.profiles).map { ($0.id, $0) }, uniquingKeysWith: { _, remote in remote })
        return .init(
            schemaVersion: 1,
            revision: remote.revision,
            tracks: tracks.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending },
            profiles: profiles.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        )
    }

    private static func sha256(_ url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open(); defer { stream.close() }
        var hasher = SHA256()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_048_576)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1_048_576)
            if count < 0 { return nil }
            if count == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
