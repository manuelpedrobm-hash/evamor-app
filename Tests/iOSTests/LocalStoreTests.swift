import XCTest
import SwiftData
import MeditationCore
import AVFoundation
@testable import Meditacion

@MainActor private func makeTestStore() throws -> LocalStore {
    let schema = Schema([MeditationSession.self, ActiveSession.self, Preferences.self, SyncOperation.self, FriendSnapshot.self, SocialReceipt.self, TimelapseMedia.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return LocalStore(container: try ModelContainer(for: schema, configurations: configuration))
}

@MainActor private final class SilentTestAudioPlayer: MeditationAudioPlayer {
    func play(_ phase: SessionPhase, offset: Double) async throws {}
    func stop() {}
}

@MainActor final class LocalStoreTests: XCTestCase {
    func testQuickDurationsPersistAndPreserveAudio() throws {
        let store = try makeTestStore()
        let model = AppModel(container: store.context.container)
        model.saveConfiguration(.init(minutes: 60, audio: [.introduction, .metta]))
        for minutes in [5, 15, 30, 60, 5] {
            model.setQuickDuration(minutes)
            model.reload()
            XCTAssertEqual(model.configuration.minutes, minutes)
            XCTAssertEqual(model.configuration.audio, [.introduction, .metta])
        }
    }

    func testBundledAudioDecodesAndPlaysFromBeginningMiddleAndEnd() async throws {
        let service = AudioService()
        defer { service.stop() }
        for kind in AudioKind.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: kind.rawValue, withExtension: "wav"))
            let decoded = try AVAudioPlayer(contentsOf: url)
            XCTAssertEqual(decoded.duration, kind.seconds, accuracy: 0.02)
            for offset in [0, kind.seconds / 2, kind.seconds - 1] {
                service.stop()
                try await service.play(.init(audio: kind, seconds: kind.seconds), offset: offset)
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertTrue(service.isPlaying, "\(kind) at \(offset)")
            }
        }
    }

    func testRapidAudioCancellationDoesNotSilenceNextPlayback() async throws {
        let service = AudioService()
        defer { service.stop() }
        for _ in 0..<5 {
            let opening = Task { try await service.play(.init(audio: .introduction, seconds: AudioKind.introduction.seconds), offset: 0) }
            await Task.yield()
            opening.cancel()
            service.stop()
            try await service.play(.init(audio: .metta, seconds: AudioKind.metta.seconds), offset: 0)
            _ = await opening.result
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertTrue(service.isPlaying)
        }
    }

    func testCompletionIsAtomicIdempotentAndQueuedOffline() throws {
        let store = try makeTestStore()
        let progress = SessionProgress(configuration: .init(minutes: 5), now: Date().addingTimeInterval(-400))
        try store.saveActive(progress, owner: "local")
        try store.complete(progress, owner: "local", share: true)
        try store.complete(progress, owner: "local", share: true)
        XCTAssertEqual(try store.records(owner: "local").count, 1)
        XCTAssertEqual(try store.operations(owner: "local").count, 1)
        XCTAssertNil(try store.loadActive())
    }

    func testRestorePausedStateAndCancelDoesNotAddStatistics() throws {
        let store = try makeTestStore()
        var progress = SessionProgress(configuration: .init(minutes: 5), now: Date())
        progress.pause(at: progress.startedAt.addingTimeInterval(15))
        try store.saveActive(progress, owner: "local")
        XCTAssertEqual(try XCTUnwrap(store.loadActive()).1, progress)
        try store.discardActive()
        XCTAssertEqual(try store.records(owner: "local").count, 0)
    }

    func testFinishingEarlyStoresPrivatePartialPracticeAtomically() throws {
        let store = try makeTestStore()
        let start = Date().addingTimeInterval(-125)
        let progress = SessionProgress(configuration: .init(minutes: 5), now: start)
        try store.saveActive(progress, owner: "local")
        try store.finishEarly(progress, endedAt: start.addingTimeInterval(125), owner: "local")

        let record = try XCTUnwrap(store.records(owner: "local").first)
        XCTAssertFalse(record.completed)
        XCTAssertFalse(record.shareAtCompletion)
        XCTAssertEqual(record.durationSeconds, 125, accuracy: 0.001)
        XCTAssertEqual(record.plannedDurationSeconds, 300, accuracy: 0.001)
        XCTAssertNil(try store.loadActive())
        XCTAssertEqual(try store.operations(owner: "local").count, 1)
    }

    func testFriendMuteSurvivesRefreshAndSignalsAreClaimedOnce() throws {
        let store = try makeTestStore()
        let friend = RemoteFriend(id: "incoming|a|z", name: "Ana", status: "accepted", direction: .incoming, muted: false, firstSeenAt: .now, cloudIdentifier: "a|z")
        try store.replaceFriends([friend], owner: "local")
        try store.setMuted(true, friendID: friend.id, owner: "local")
        try store.replaceFriends([friend], owner: "local")
        XCTAssertTrue(try XCTUnwrap(store.friends(owner: "local").first).muted)
        let signal = SocialSignal(id: "event", friendID: friend.id, completedAt: .now, slot: "morning")
        XCTAssertEqual(try store.claim([signal]), [signal])
        XCTAssertTrue(try store.claim([signal]).isEmpty)
    }

    func testOldStudentCredentialsAndSocialMessages() {
        XCTAssertTrue(OldStudentAccess.verify(username: " oldstudent ", password: "behappy"))
        XCTAssertFalse(OldStudentAccess.verify(username: "oldstudent", password: "BEHAPPY"))
        XCTAssertFalse(OldStudentAccess.verify(username: "alumno", password: "behappy"))
        XCTAssertEqual(NotificationService.socialMessage(count: 1, slot: "morning"), "Un amigo ha completado su meditación matutina y te envía metta.")
        XCTAssertEqual(NotificationService.socialMessage(count: 1, slot: "evening"), "Un amigo ha completado su meditación de la tarde y te envía metta.")
        XCTAssertEqual(NotificationService.socialMessage(count: 2, slot: "morning"), "Un amigo ha completado 2 meditaciones y te envía metta.")
    }

    func testSavedProfilesPersistAndDelete() {
        let suite = "profiles-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var catalog = AudioCatalogService(defaults: defaults)
        let configuration = SessionConfiguration(minutes: 30, audio: [.metta])
        catalog.saveProfile(name: " Tarde ", configuration: configuration)
        catalog = AudioCatalogService(defaults: defaults)
        XCTAssertEqual(catalog.savedProfiles.count, 1)
        XCTAssertEqual(catalog.savedProfiles.first?.name, "Tarde")
        XCTAssertEqual(catalog.savedProfiles.first?.configuration, configuration)
        catalog.deleteProfile(id: catalog.savedProfiles[0].id)
        XCTAssertTrue(AudioCatalogService(defaults: defaults).savedProfiles.isEmpty)
    }

    func testBundledCatalogContainsOnlyTheTwoOfflineSittings() throws {
        let catalog = AudioCatalogService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(Set(catalog.tracks.map(\.id)), ["group-long", "group-short"])
        XCTAssertEqual(Set(catalog.catalogProfiles.map(\.id)), ["sitting-long", "sitting-short"])
        XCTAssertTrue(catalog.tracks.allSatisfy { $0.downloadURL == nil && $0.bundledResource != nil })
        XCTAssertTrue(catalog.tracks.allSatisfy { catalog.localURL(for: $0.id) != nil })
    }

    func testDeletingHistoryIsImmediateAndQueuesRemoteDeletion() throws {
        let store = try makeTestStore()
        let progress = SessionProgress(configuration: .init(minutes: 5), now: Date().addingTimeInterval(-400))
        try store.complete(progress, owner: "local", share: true)
        try store.deleteHistory(owner: "local")
        try store.deleteHistory(owner: "local")
        XCTAssertTrue(try store.records(owner: "local").isEmpty)
        let operations = try store.operations(owner: "local")
        XCTAssertEqual(operations.filter { $0.kind == "deleteHistory" }.count, 1)
        XCTAssertTrue(operations.filter { $0.kind == "session" }.isEmpty)
    }

    func testTimelapseMetadataCanBeSavedAndDeletedWithoutDeletingHistory() throws {
        let store = try makeTestStore()
        let progress = SessionProgress(configuration: .init(minutes: 5), now: Date().addingTimeInterval(-400))
        try store.complete(progress, owner: "local", share: false)
        let url = URL(fileURLWithPath: "/tmp/example-timelapse.mp4")
        try store.saveTimelapse(
            sessionID: progress.id,
            owner: "local",
            result: TimelapseResult(url: url, frameCount: 240, duration: 10)
        )

        let media = try XCTUnwrap(store.timelapseMedia(sessionID: progress.id, owner: "local"))
        XCTAssertEqual(media.filename, "example-timelapse.mp4")
        XCTAssertEqual(media.frameCount, 240)
        try store.deleteTimelapse(sessionID: progress.id, owner: "local")
        XCTAssertNil(try store.timelapseMedia(sessionID: progress.id, owner: "local"))
        XCTAssertEqual(try store.records(owner: "local").count, 1)
        try store.saveTimelapse(
            sessionID: progress.id,
            owner: "local",
            result: TimelapseResult(url: url, frameCount: 240, duration: 10)
        )
        try store.deleteAllTimelapses(owner: "local")
        XCTAssertNil(try store.timelapseMedia(sessionID: progress.id, owner: "local"))
        XCTAssertEqual(try store.records(owner: "local").count, 1)
    }

    func testSittingCompletesWhenAudioEndsWithoutWaitingForForegroundTimer() throws {
        let store = try makeTestStore()
        let track = CatalogAudioReference(id: "sitting", title: "Sitting", durationSeconds: 3_872.715465)
        let engine = SessionEngine(repository: store, audio: SilentTestAudioPlayer(), notifications: NotificationService())
        engine.start(.init(minutes: 65, catalogAudio: track), owner: "local")

        XCTAssertNotNil(engine.progress)
        engine.audioDidFinish(successfully: true)

        XCTAssertNil(engine.progress)
        XCTAssertNil(try store.loadActive())
        let record = try XCTUnwrap(store.records(owner: "local").first)
        XCTAssertTrue(record.completed)
        XCTAssertEqual(record.durationSeconds, track.durationSeconds, accuracy: 0.001)
    }

}

@MainActor final class MockCloud: CloudGateway {
    var enabled = true
    var uploaded: [(String, Bool)] = []
    var remoteSessions: [SessionRecord] = []
    var deletedHistory = false
    var available: Bool { get async { enabled } }
    func upload(_ record: SessionRecord, share: Bool) async throws { uploaded.append((record.id, share)); remoteSessions.append(record) }
    func sessions() async throws -> [SessionRecord] { remoteSessions }
    func friends() async throws -> [RemoteFriend] { [] }
    func incomingSignals() async throws -> [SocialSignal] { [] }
    func setReceiving(_ enabled: Bool) async throws {}
    func deleteHistory() async throws { deletedHistory = true; remoteSessions = [] }
}

@MainActor final class SyncTests: XCTestCase {
    func testSyncUploadsOnceAndHonorsCurrentSharingPreference() async throws {
        let store = try makeTestStore()
        let cloud = MockCloud(); let sync = SyncService(store: store, cloud: cloud)
        let progress = SessionProgress(configuration: .init(minutes: 5), now: Date().addingTimeInterval(-400))
        let preferences = try store.preferences(owner: "local"); preferences.shareSessions = false; try store.commit()
        try store.complete(progress, owner: "local", share: true)
        await sync.sync(); await sync.sync()
        XCTAssertEqual(cloud.uploaded.count, 1)
        XCTAssertEqual(cloud.uploaded.first?.1, false)
        XCTAssertEqual(try store.operations(owner: "local").count, 0)
    }
    func testPartialPracticeSyncsPrivatelyWhenSharingIsEnabled() async throws {
        let store = try makeTestStore()
        let cloud = MockCloud(); let sync = SyncService(store: store, cloud: cloud)
        let start = Date().addingTimeInterval(-90)
        let progress = SessionProgress(configuration: .init(minutes: 5), now: start)
        let preferences = try store.preferences(owner: "local"); preferences.shareSessions = true; try store.commit()
        try store.finishEarly(progress, endedAt: start.addingTimeInterval(90), owner: "local")
        await sync.sync()
        XCTAssertEqual(cloud.uploaded.count, 1)
        XCTAssertEqual(cloud.uploaded.first?.1, false)
        XCTAssertFalse(try XCTUnwrap(cloud.remoteSessions.first).completed)
    }
    func testEveryCompletedPracticeRequestsItsOwnSocialSignal() async throws {
        let store = try makeTestStore()
        let cloud = MockCloud(); let sync = SyncService(store: store, cloud: cloud)
        let preferences = try store.preferences(owner: "local"); preferences.shareSessions = true; try store.commit()
        let first = SessionProgress(configuration: .init(minutes: 5), now: Date().addingTimeInterval(-700), id: "first-complete")
        let second = SessionProgress(configuration: .init(minutes: 5), now: Date().addingTimeInterval(-350), id: "second-complete")
        try store.complete(first, owner: "local", share: true)
        try store.complete(second, owner: "local", share: true)

        await sync.sync()
        XCTAssertEqual(Set(cloud.uploaded.map(\.0)), ["first-complete", "second-complete"])
        XCTAssertTrue(cloud.uploaded.allSatisfy(\.1))
        XCTAssertEqual(try store.operations(owner: "local").count, 0)
    }
    func testQueuedDeletionRunsBeforeLaterSessions() async throws {
        let store = try makeTestStore()
        let cloud = MockCloud(); let sync = SyncService(store: store, cloud: cloud)
        try store.deleteHistory(owner: "local")
        let progress = SessionProgress(configuration: .init(minutes: 5), now: Date().addingTimeInterval(-400))
        try store.complete(progress, owner: "local", share: false)
        await sync.sync()
        XCTAssertTrue(cloud.deletedHistory)
        XCTAssertEqual(cloud.uploaded.count, 1)
        XCTAssertEqual(try store.records(owner: "local").count, 1)
        XCTAssertTrue(try store.operations(owner: "local").isEmpty)
    }
}

final class TimelapseVideoWriterTests: XCTestCase {
    func testWriterProducesPlayableVideoFromSyntheticCameraFrames() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("timelapse-writer-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try TimelapseVideoWriter(url: url, framesPerSecond: 24)
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        var appended = 0
        var attempts = 0
        while appended < 48, attempts < 500 {
            attempts += 1
            var buffer: CVPixelBuffer?
            XCTAssertEqual(
                CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA, attributes, &buffer),
                kCVReturnSuccess
            )
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, Int32(appended % 255), CVPixelBufferGetDataSize(pixelBuffer))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            if try writer.append(pixelBuffer) {
                appended += 1
            } else {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        XCTAssertEqual(appended, 48)

        let result = try await withCheckedThrowingContinuation { continuation in
            writer.finish { continuation.resume(with: $0) }
        }
        XCTAssertEqual(result.frameCount, 48)
        XCTAssertEqual(result.duration, 2, accuracy: 0.001)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        let assetDuration = try await AVURLAsset(url: result.url).load(.duration).seconds
        XCTAssertEqual(assetDuration, 2, accuracy: 0.1)
    }
}
