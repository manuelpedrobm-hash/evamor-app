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
    case trackUnavailable

    var errorDescription: String? {
        "Este audio no está disponible en la instalación."
    }
}

@MainActor @Observable final class AudioCatalogService {
    private(set) var document: AudioCatalogDocument
    private(set) var savedProfiles: [SavedSessionProfile]
    var message: String?
    private var previewPlayer: AVAudioPlayer?
    @ObservationIgnored private var validatedURLs: [String: (hash: String, url: URL)] = [:]

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private static let profilesKey = "savedSessionProfiles"

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        if let data = defaults.data(forKey: Self.profilesKey),
           let profiles = try? JSONDecoder().decode([SavedSessionProfile].self, from: data) {
            savedProfiles = profiles
        } else {
            savedProfiles = []
        }
        document = Self.loadBundledCatalog()
    }

    var tracks: [AudioCatalogTrack] { document.tracks }
    var catalogProfiles: [CatalogSessionProfile] { document.profiles }
    func track(id: String) -> AudioCatalogTrack? { tracks.first { $0.id == id } }

    func localURL(for id: String) -> URL? {
        guard let track = track(id: id) else { return nil }
        if let validated = validatedURLs[id], validated.hash == track.sha256.lowercased(),
           fileManager.fileExists(atPath: validated.url.path) { return validated.url }
        guard let resource = track.bundledResource else { return nil }
        let name = (resource as NSString).deletingPathExtension
        let ext = (resource as NSString).pathExtension
        guard let bundled = Bundle.main.url(forResource: name, withExtension: ext),
              Self.sha256(bundled) == track.sha256.lowercased() else { return nil }
        validatedURLs[id] = (track.sha256.lowercased(), bundled)
        return bundled
    }

    func isAvailable(_ track: AudioCatalogTrack) -> Bool { localURL(for: track.id) != nil }

    func refresh() async {
        document = Self.loadBundledCatalog()
        message = nil
    }

    @discardableResult func download(_ track: AudioCatalogTrack) async throws -> URL {
        if let local = localURL(for: track.id) { return local }
        throw AudioCatalogError.trackUnavailable
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

    private static func loadBundledCatalog() -> AudioCatalogDocument {
        guard let url = Bundle.main.url(forResource: "AudioCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(AudioCatalogDocument.self, from: data) else {
            return .init(schemaVersion: 1, revision: "bundled-empty", tracks: [], profiles: [])
        }
        return value
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
