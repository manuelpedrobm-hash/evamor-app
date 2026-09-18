import XCTest
@testable import MeditationCore

final class SessionTests: XCTestCase {
    let utc = TimeZone(secondsFromGMT: 0)!
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func record(_ value: String, zone: TimeZone? = nil, minutes: Int = 60) -> SessionRecord {
        SessionRecord(progress: SessionProgress(configuration: .init(minutes: minutes), now: date(value), timeZone: zone ?? utc), share: false)
    }
    func testDefaultAndEveryAudioCombinationPreservesDuration() {
        XCTAssertEqual(SessionConfiguration().minutes, 60)
        XCTAssertFalse(SessionConfiguration().timeLapseEnabled)
        for mask in 0..<16 {
            let audio = Set(AudioKind.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            let config = SessionConfiguration(minutes: 5, audio: audio)
            XCTAssertTrue(config.isValid)
            XCTAssertEqual(config.phases.reduce(0) { $0 + $1.seconds }, config.totalSeconds)
            XCTAssertEqual(config.totalSeconds, audio.contains(.metta) ? 300 + AudioKind.metta.seconds : 300)
        }
        XCTAssertFalse(SessionConfiguration(minutes: 4).isValid)
        XCTAssertTrue(SessionConfiguration(minutes: 480).isValid)
        XCTAssertFalse(SessionConfiguration(minutes: 481).isValid)
    }
    func testLegacyConfigurationAndTimelapsePlan() throws {
        let legacy = Data(#"{"minutes":60,"audio":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(SessionConfiguration.self, from: legacy)
        XCTAssertFalse(decoded.timeLapseEnabled)

        let short = TimelapsePlan(sourceSeconds: 300)
        XCTAssertEqual(short.captureInterval, 1)
        XCTAssertEqual(short.estimatedOutputSeconds, 10)
        let hour = TimelapsePlan(sourceSeconds: 3_600)
        XCTAssertEqual(hour.captureInterval, 4)
        XCTAssertLessThanOrEqual(hour.estimatedOutputSeconds, 30)
        let eightHours = TimelapsePlan(sourceSeconds: 28_800)
        XCTAssertEqual(eightHours.captureInterval, 32)
        XCTAssertLessThanOrEqual(eightHours.estimatedOutputSeconds, 30)
        let shortVideo = TimelapsePlan(sourceSeconds: 3_600, outputSeconds: 10)
        XCTAssertEqual(shortVideo.captureInterval, 12)
        XCTAssertLessThanOrEqual(shortVideo.estimatedOutputSeconds, 10)
    }
    func testDynamicCatalogAudioFitsAndLeavesExactSilence() {
        let track = CatalogAudioReference(id: "guided", title: "Guided", durationSeconds: 3_872.715465)
        let valid = SessionConfiguration(minutes: 65, catalogAudio: track)
        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(valid.minimumMinutes, 65)
        XCTAssertEqual(valid.phases.first?.catalogAudio, track)
        XCTAssertEqual(valid.phases.reduce(0) { $0 + $1.seconds }, 3_900, accuracy: 0.001)
        XCTAssertFalse(SessionConfiguration(minutes: 64, catalogAudio: track).isValid)
        let encoded = try! JSONEncoder().encode(valid)
        XCTAssertEqual(try! JSONDecoder().decode(SessionConfiguration.self, from: encoded), valid)
    }
    func testAudioTimelineForEveryAllowedMinuteAndCombination() {
        let start = date("2026-09-17T10:00:00Z")
        for minutes in SessionConfiguration.allowedMinutes {
            for mask in 0..<16 {
                let audio = Set(AudioKind.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
                let config = SessionConfiguration(minutes: minutes, audio: audio)
                XCTAssertTrue(config.isValid)
                XCTAssertEqual(config.phases.reduce(0) { $0 + $1.seconds }, config.totalSeconds)
                let progress = SessionProgress(configuration: config, now: start)
                var cursor = 0.0
                for phase in config.phases {
                    XCTAssertTrue(phase.seconds > 0)
                    let midway = progress.phase(at: start.addingTimeInterval(cursor + phase.seconds / 2))
                    XCTAssertEqual(midway?.phase.audio, phase.audio)
                    XCTAssertTrue(abs((midway?.offset ?? -1) - phase.seconds / 2) < 0.001)
                    cursor += phase.seconds
                }
                XCTAssertTrue(progress.isComplete(at: progress.deadline))
                XCTAssertNil(progress.phase(at: progress.deadline))
            }
        }
    }
    func testMovementBandsAreDescriptiveAndNeverScores() {
        XCTAssertEqual(MotionSummary(sampleCount: 1, averageJointDisplacement: 0).band, .unavailable)
        XCTAssertEqual(MotionSummary(sampleCount: 10, averageJointDisplacement: 0.004).band, .sustainedStillness)
        XCTAssertEqual(MotionSummary(sampleCount: 10, averageJointDisplacement: 0.015).band, .gentleAdjustments)
        XCTAssertEqual(MotionSummary(sampleCount: 10, averageJointDisplacement: 0.08).band, .livingMovement)
    }
    func testPauseAndResumeSurviveSerialization() throws {
        let start = date("2026-09-14T10:00:00Z")
        var progress = SessionProgress(configuration: .init(minutes: 5), now: start, timeZone: utc)
        progress.pause(at: start.addingTimeInterval(20))
        XCTAssertEqual(progress.remaining(at: start.addingTimeInterval(500)), 280)
        XCTAssertFalse(progress.isComplete(at: start.addingTimeInterval(500)))
        progress = try JSONDecoder().decode(SessionProgress.self, from: JSONEncoder().encode(progress))
        progress.resume(at: start.addingTimeInterval(100))
        XCTAssertEqual(progress.remaining(at: start.addingTimeInterval(110)), 270)
        XCTAssertTrue(progress.isComplete(at: start.addingTimeInterval(380)))
    }
    func testReopeningExpiredSessionDoesNotDependOnTicks() throws {
        let start = date("2026-09-14T23:59:00Z")
        let progress = SessionProgress(configuration: .init(), now: start, timeZone: utc)
        let restored = try JSONDecoder().decode(SessionProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertTrue(restored.isComplete(at: start.addingTimeInterval(7200)))
        let completed = SessionRecord(progress: restored, share: true)
        XCTAssertEqual(completed.localDate, "2026-09-14")
        XCTAssertEqual(completed.endedAt, start.addingTimeInterval(3600).timeIntervalSince1970 * 1000)
    }
    func testPartialPracticeKeepsElapsedTimeWithoutAffectingCompletionProgress() throws {
        let start = date("2026-09-17T07:00:00Z")
        let progress = SessionProgress(configuration: .init(minutes: 5), now: start, timeZone: utc)
        let partial = SessionRecord(progress: progress, endedEarlyAt: start.addingTimeInterval(125))

        XCTAssertFalse(partial.completed)
        XCTAssertFalse(partial.shareAtCompletion)
        XCTAssertEqual(partial.durationSeconds, 125)
        XCTAssertEqual(partial.plannedDurationSeconds, 300)

        let decoded = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(partial))
        XCTAssertEqual(decoded, partial)
        let statistics = MeditationStatistics(records: [partial], now: start.addingTimeInterval(180), timeZone: utc)
        XCTAssertEqual(statistics.sessions, 0)
        XCTAssertEqual(statistics.partialSessions, 1)
        XCTAssertEqual(statistics.minutes, 2)
        XCTAssertEqual(statistics.weeklySessions, 0)
        XCTAssertEqual(statistics.weeklyMinutes, 2)
        XCTAssertEqual(statistics.dailyStreak, 0)
        XCTAssertFalse(statistics.continuity.practicedToday)
    }
    func testLegacySessionRecordDefaultsToComplete() throws {
        let complete = record("2026-09-17T07:00:00Z", minutes: 30)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(complete)) as! [String: Any]
        object.removeValue(forKey: "completed")
        object.removeValue(forKey: "plannedDurationSeconds")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: legacy)
        XCTAssertTrue(decoded.completed)
        XCTAssertEqual(decoded.plannedDurationSeconds, 1_800)
    }
    func testPhaseBoundariesAndSeekAfterBackground() {
        let start = date("2026-09-14T10:00:00Z")
        let progress = SessionProgress(configuration: .init(minutes: 5, audio: Set(AudioKind.allCases)), now: start)
        XCTAssertEqual(progress.phase(at: start)?.phase.audio, .introduction)
        XCTAssertEqual(progress.phase(at: start.addingTimeInterval(258.9))?.phase.audio, .introduction)
        XCTAssertEqual(progress.phase(at: start.addingTimeInterval(259))?.phase.audio, .chanting)
        XCTAssertNil(progress.phase(at: start.addingTimeInterval(271))?.phase.audio)
        XCTAssertEqual(progress.phase(at: start.addingTimeInterval(295))?.phase.audio, .closing)
        XCTAssertEqual(progress.phase(at: start.addingTimeInterval(295))?.offset, 3)
        XCTAssertEqual(progress.phase(at: start.addingTimeInterval(300))?.phase.audio, .metta)
        XCTAssertNil(progress.phase(at: start.addingTimeInterval(300 + AudioKind.metta.seconds)))
    }
    func testStreakCountsYesterdayUntilTodayQualifiesAndDeduplicates() {
        let yesterdayAM = record("2026-09-13T07:00:00Z")
        let rows = [record("2026-09-12T07:00:00Z"), record("2026-09-12T21:00:00Z"), yesterdayAM, yesterdayAM,
                    record("2026-09-13T21:00:00Z"), record("2026-09-14T07:00:00Z")]
        let stats = MeditationStatistics(records: rows, now: date("2026-09-14T10:00:00Z"), timeZone: utc)
        XCTAssertEqual(stats.sessions, 5); XCTAssertEqual(stats.minutes, 300)
        XCTAssertEqual(stats.dailyStreak, 3); XCTAssertEqual(stats.twiceDailyStreak, 2)
        let tomorrow = MeditationStatistics(records: rows, now: date("2026-09-15T10:00:00Z"), timeZone: utc)
        XCTAssertEqual(tomorrow.dailyStreak, 3); XCTAssertEqual(tomorrow.twiceDailyStreak, 0)
    }
    func testNoonMidnightAndTwoMorningSessions() {
        XCTAssertEqual(record("2026-09-14T11:59:59Z").slot, "morning")
        XCTAssertEqual(record("2026-09-14T12:00:00Z").slot, "evening")
        let rows = [record("2026-09-14T07:00:00Z"), record("2026-09-14T09:00:00Z")]
        XCTAssertEqual(MeditationStatistics(records: rows, now: date("2026-09-14T22:00:00Z"), timeZone: utc).twiceDailyStreak, 0)
    }
    func testGentleContinuityKeepsOneRecoverablePause() {
        let earlier = [record("2026-09-12T07:00:00Z"), record("2026-09-13T07:00:00Z"), record("2026-09-14T07:00:00Z")]
        var continuity = MeditationStatistics(records: earlier, now: date("2026-09-16T10:00:00Z"), timeZone: utc).continuity
        XCTAssertEqual(continuity.activeDays, 3)
        XCTAssertEqual(continuity.linkedSessions, 3)
        XCTAssertTrue(continuity.pauseUsed)
        XCTAssertTrue(continuity.needsRecoveryToday)
        XCTAssertFalse(continuity.practicedToday)

        let resumed = earlier + [record("2026-09-16T07:00:00Z"), record("2026-09-16T20:00:00Z")]
        continuity = MeditationStatistics(records: resumed, now: date("2026-09-16T21:00:00Z"), timeZone: utc).continuity
        XCTAssertEqual(continuity.activeDays, 4)
        XCTAssertEqual(continuity.linkedSessions, 5)
        XCTAssertTrue(continuity.pauseUsed)
        XCTAssertTrue(continuity.practicedToday)
        XCTAssertFalse(continuity.needsRecoveryToday)
    }
    func testGentleContinuityBreaksAtSecondPause() {
        let rows = [record("2026-09-10T07:00:00Z"), record("2026-09-11T07:00:00Z"),
                    record("2026-09-13T07:00:00Z"), record("2026-09-14T07:00:00Z"), record("2026-09-16T07:00:00Z")]
        let continuity = MeditationStatistics(records: rows, now: date("2026-09-16T10:00:00Z"), timeZone: utc).continuity
        XCTAssertEqual(continuity.activeDays, 3)
        XCTAssertEqual(continuity.linkedSessions, 3)
        XCTAssertTrue(continuity.pauseUsed)
    }
    func testWeeklySummaryMilestonesAndLegacyReminderDecoding() throws {
        let rows = [record("2026-09-09T07:00:00Z", minutes: 30),
                    record("2026-09-10T07:00:00Z", minutes: 30),
                    record("2026-09-15T07:00:00Z", minutes: 60),
                    record("2026-09-16T07:00:00Z", minutes: 45)]
        let statistics = MeditationStatistics(records: rows, now: date("2026-09-16T12:00:00Z"), timeZone: utc)
        XCTAssertEqual(statistics.weeklySessions, 3)
        XCTAssertEqual(statistics.weeklyMinutes, 135)
        XCTAssertEqual(statistics.nextMilestone, 10)
        XCTAssertEqual(statistics.sessionsToNextMilestone, 6)

        let legacy = Data(#"{"morningEnabled":true,"eveningEnabled":false,"morningMinute":420,"eveningMinute":1260,"sound":true}"#.utf8)
        let reminders = try JSONDecoder().decode(ReminderSettings.self, from: legacy)
        XCTAssertTrue(reminders.morningEnabled)
        XCTAssertFalse(reminders.continuityEnabled)
        XCTAssertEqual(reminders.continuityMinute, 1_200)
    }
    func testSocialNotificationPolicyFiltersAndGroups() {
        let joined = date("2026-09-15T10:00:00Z")
        let friends = [
            SocialFriendRule(id: "ana", muted: false, firstSeenAt: joined),
            SocialFriendRule(id: "bea", muted: true, firstSeenAt: joined)
        ]
        let events = [
            SocialEventCandidate(id: "old", friendID: "ana", completedAt: joined.addingTimeInterval(-1)),
            SocialEventCandidate(id: "a2", friendID: "ana", completedAt: joined.addingTimeInterval(20), slot: "evening"),
            SocialEventCandidate(id: "a1", friendID: "ana", completedAt: joined.addingTimeInterval(10), slot: "morning"),
            SocialEventCandidate(id: "muted", friendID: "bea", completedAt: joined.addingTimeInterval(10)),
            SocialEventCandidate(id: "unknown", friendID: "carla", completedAt: joined.addingTimeInterval(10))
        ]
        XCTAssertEqual(SocialNotificationPolicy.batches(receiving: false, events: events, friends: friends), [])
        XCTAssertEqual(SocialNotificationPolicy.batches(receiving: true, events: events, friends: friends), [
            SocialNotificationBatch(friendID: "ana", eventIDs: ["a1", "a2"], slot: "evening")
        ])
    }
    func testCalendarDaysAcrossDSTLeapDayAndTravel() {
        XCTAssertEqual(DayKey.previous("2024-03-01"), "2024-02-29")
        let madrid = TimeZone(identifier: "Europe/Madrid")!
        let rows = [record("2026-03-28T22:30:00Z", zone: madrid), record("2026-03-29T21:30:00Z", zone: madrid)]
        XCTAssertEqual(MeditationStatistics(records: rows, now: date("2026-03-30T07:00:00Z"), timeZone: madrid).dailyStreak, 2)
        let traveled = record("2026-09-14T23:30:00Z", zone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(traveled.localDate, "2026-09-15")
        XCTAssertEqual(traveled.slot, "morning")
        XCTAssertEqual(traveled.timeZoneID, "Asia/Tokyo")
    }
}
