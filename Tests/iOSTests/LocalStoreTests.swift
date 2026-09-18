import XCTest
import SwiftData
import MeditationCore
import AVFoundation
@testable import Meditacion

@MainActor private func makeTestStore() throws -> LocalStore {
    let schema = Schema([MeditationSession.self, ActiveSession.self, Preferences.self, SyncOperation.self, FriendSnapshot.self, SocialReceipt.self, MeditationMedia.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return LocalStore(container: try ModelContainer(for: schema, configurations: configuration))
}

@MainActor final class LocalStoreTests: XCTestCase {
    func testQuickDurationsPersistAndPreserveAudioAndTimelapse() throws {
        let store = try makeTestStore()
        let model = AppModel(container: store.context.container)
        model.saveConfiguration(.init(minutes: 60, audio: [.introduction, .metta], timeLapseEnabled: true))
        for minutes in [5, 15, 30, 60, 5] {
            model.setQuickDuration(minutes)
            model.reload()
            XCTAssertEqual(model.configuration.minutes, minutes)
            XCTAssertEqual(model.configuration.audio, [.introduction, .metta])
            XCTAssertTrue(model.configuration.timeLapseEnabled)
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
        let configuration = SessionConfiguration(minutes: 30, audio: [.metta], timeLapseEnabled: true, timelapseOutputSeconds: 20)
        catalog.saveProfile(name: " Tarde ", configuration: configuration)
        catalog = AudioCatalogService(defaults: defaults)
        XCTAssertEqual(catalog.savedProfiles.count, 1)
        XCTAssertEqual(catalog.savedProfiles.first?.name, "Tarde")
        XCTAssertEqual(catalog.savedProfiles.first?.configuration, configuration)
        catalog.deleteProfile(id: catalog.savedProfiles[0].id)
        XCTAssertTrue(AudioCatalogService(defaults: defaults).savedProfiles.isEmpty)
    }

    func testTimelapseBulkDeletionKeepsMeditationHistory() throws {
        let store = try makeTestStore()
        let progress = SessionProgress(configuration: .init(minutes: 5), now: Date().addingTimeInterval(-400))
        try store.complete(progress, owner: "local", share: false)
        try store.saveMedia(sessionID: progress.id, owner: "local", filename: "clip.mp4")
        try store.deleteAllMedia(owner: "local")
        XCTAssertNil(try store.mediaFilename(sessionID: progress.id, owner: "local"))
        XCTAssertEqual(try store.records(owner: "local").count, 1)
    }

    func testPaliQuoteSelectionIsStableAndVariesAcrossFiles() {
        let first = PaliQuote.forTimelapse(URL(fileURLWithPath: "/tmp/evamor-a.mp4"))
        XCTAssertEqual(first, PaliQuote.forTimelapse(URL(fileURLWithPath: "/tmp/evamor-a.mp4")))
        let choices = (0..<30).map { PaliQuote.forTimelapse(URL(fileURLWithPath: "/tmp/evamor-\($0).mp4")).id }
        XCTAssertGreaterThan(Set(choices).count, 1)
        XCTAssertEqual(PaliQuote.collection.count, 22)
        XCTAssertEqual(Set(PaliQuote.collection.map(\.id)).count, 22)
        XCTAssertTrue(PaliQuote.collection.allSatisfy { !$0.pali.isEmpty && !$0.translation.isEmpty && $0.source.hasPrefix("Dhammapada") })
    }

    func testBundledCatalogSessionsArePlayableAndProfilesFit() throws {
        let catalog = AudioCatalogService(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(catalog.tracks.count, 2)
        XCTAssertEqual(catalog.catalogProfiles.count, 2)
        for profile in catalog.catalogProfiles {
            let track = try XCTUnwrap(profile.trackID.flatMap { catalog.track(id: $0) })
            let url = try XCTUnwrap(catalog.localURL(for: track.id))
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertEqual(player.duration, track.durationSeconds, accuracy: 0.05)
            let configuration = SessionConfiguration(minutes: profile.minutes, catalogAudio: track.reference)
            XCTAssertTrue(configuration.isValid)
            XCTAssertEqual(configuration.phases.first?.catalogAudio?.id, track.id)
            XCTAssertEqual(configuration.phases.reduce(0) { $0 + $1.seconds }, configuration.totalSeconds, accuracy: 0.001)
        }
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

    func testTimelapseMetadataIsLocalAndDeletedWithHistory() throws {
        let store = try makeTestStore()
        let motion = MotionSummary(sampleCount: 20, averageJointDisplacement: 0.012)
        try store.saveMedia(sessionID: "session", owner: "local", filename: "clip.mp4", motion: motion)
        XCTAssertEqual(try store.mediaFilename(sessionID: "session", owner: "local"), "clip.mp4")
        XCTAssertEqual(try store.motionSummary(sessionID: "session", owner: "local"), motion)
        XCTAssertTrue(try store.operations(owner: "local").isEmpty)
        try store.deleteHistory(owner: "local")
        XCTAssertNil(try store.mediaFilename(sessionID: "session", owner: "local"))
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
