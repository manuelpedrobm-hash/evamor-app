import Foundation

public enum AudioKind: String, Codable, CaseIterable, Sendable {
    case introduction, chanting, closing, metta
    public var title: String {
        switch self {
        case .introduction: return "Introducción"
        case .chanting: return "Chanting"
        case .closing: return "Cierre"
        case .metta: return "Metta extendido"
        }
    }
    // Bundled playback durations, kept in sync with AudioManifest.json.
    public var seconds: Double {
        switch self { case .introduction: return 259; case .chanting: return 12; case .closing: return 8; case .metta: return 72.6465306122449 }
    }
    // Chanting and closing are placeholder synthesized tones, not real
    // recordings; only introduction and metta are offered as user choices.
    public static let userSelectable: [AudioKind] = [.introduction, .metta]
}

public struct CatalogAudioReference: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var durationSeconds: Double

    public init(id: String, title: String, durationSeconds: Double) {
        self.id = id
        self.title = title
        self.durationSeconds = max(0, durationSeconds)
    }
}

public enum TimelapseCameraPosition: String, Codable, Sendable, CaseIterable {
    case front, back
    public var title: String { self == .front ? "Frontal" : "Trasera" }
}

public enum TimelapseLens: String, Codable, Sendable, CaseIterable {
    case ultraWide, wide, telephoto
    public var title: String {
        switch self {
        case .ultraWide: return "Ultra gran angular"
        case .wide: return "Gran angular"
        case .telephoto: return "Teleobjetivo"
        }
    }
}

public struct SessionConfiguration: Codable, Equatable, Sendable {
    public var minutes: Int
    public var audio: Set<AudioKind>
    public var timeLapseEnabled: Bool
    public var catalogAudio: CatalogAudioReference?
    public var timelapseOutputSeconds: Int
    public var timelapseAnalyzesMovement: Bool
    public var timelapseCameraPosition: TimelapseCameraPosition
    public var timelapseLens: TimelapseLens
    public init(
        minutes: Int = 60,
        audio: Set<AudioKind> = [],
        timeLapseEnabled: Bool = false,
        catalogAudio: CatalogAudioReference? = nil,
        timelapseOutputSeconds: Int = 30,
        timelapseAnalyzesMovement: Bool = true,
        timelapseCameraPosition: TimelapseCameraPosition = .front,
        timelapseLens: TimelapseLens = .wide
    ) {
        self.minutes = minutes
        self.audio = audio
        self.timeLapseEnabled = timeLapseEnabled
        self.catalogAudio = catalogAudio
        self.timelapseOutputSeconds = [10, 20, 30].contains(timelapseOutputSeconds) ? timelapseOutputSeconds : 30
        self.timelapseAnalyzesMovement = timelapseAnalyzesMovement
        self.timelapseCameraPosition = timelapseCameraPosition
        self.timelapseLens = timelapseLens
    }
    private enum CodingKeys: String, CodingKey {
        case minutes, audio, timeLapseEnabled, catalogAudio, timelapseOutputSeconds, timelapseAnalyzesMovement
        case timelapseCameraPosition, timelapseLens
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        minutes = try values.decode(Int.self, forKey: .minutes)
        audio = try values.decode(Set<AudioKind>.self, forKey: .audio)
        timeLapseEnabled = try values.decodeIfPresent(Bool.self, forKey: .timeLapseEnabled) ?? false
        catalogAudio = try values.decodeIfPresent(CatalogAudioReference.self, forKey: .catalogAudio)
        timelapseOutputSeconds = try values.decodeIfPresent(Int.self, forKey: .timelapseOutputSeconds) ?? 30
        timelapseAnalyzesMovement = try values.decodeIfPresent(Bool.self, forKey: .timelapseAnalyzesMovement) ?? true
        timelapseCameraPosition = try values.decodeIfPresent(TimelapseCameraPosition.self, forKey: .timelapseCameraPosition) ?? .front
        timelapseLens = try values.decodeIfPresent(TimelapseLens.self, forKey: .timelapseLens) ?? .wide
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(minutes, forKey: .minutes)
        try values.encode(audio, forKey: .audio)
        try values.encode(timeLapseEnabled, forKey: .timeLapseEnabled)
        try values.encodeIfPresent(catalogAudio, forKey: .catalogAudio)
        try values.encode(timelapseOutputSeconds, forKey: .timelapseOutputSeconds)
        try values.encode(timelapseAnalyzesMovement, forKey: .timelapseAnalyzesMovement)
        try values.encode(timelapseCameraPosition, forKey: .timelapseCameraPosition)
        try values.encode(timelapseLens, forKey: .timelapseLens)
    }
    public var minimumMinutes: Int {
        let builtIn = audio.filter { $0 != .metta }.reduce(0) { $0 + $1.seconds }
        return max(1, Int(ceil((builtIn + (catalogAudio?.durationSeconds ?? 0)) / 60)))
    }
    public static let allowedMinutes = 5...480
    public var isValid: Bool { Self.allowedMinutes.contains(minutes) && minutes >= minimumMinutes }
    public var totalSeconds: Double { Double(minutes * 60) + (audio.contains(.metta) ? AudioKind.metta.seconds : 0) }
    public var phases: [SessionPhase] {
        var result: [SessionPhase] = []
        if let catalogAudio {
            result.append(SessionPhase(audio: nil, catalogAudio: catalogAudio, seconds: catalogAudio.durationSeconds))
        }
        for kind in [AudioKind.introduction, .chanting] where audio.contains(kind) {
            result.append(SessionPhase(audio: kind, seconds: kind.seconds))
        }
        let used = audio.filter { $0 != .metta }.reduce(0) { $0 + $1.seconds } + (catalogAudio?.durationSeconds ?? 0)
        if Double(minutes * 60) > used { result.append(SessionPhase(audio: nil, seconds: Double(minutes * 60) - used)) }
        for kind in [AudioKind.closing, .metta] where audio.contains(kind) {
            result.append(SessionPhase(audio: kind, seconds: kind.seconds))
        }
        return result
    }
}

public struct TimelapsePlan: Equatable, Sendable {
    public static let framesPerSecond = 30
    public static let maximumOutputSeconds = 30
    public let sourceSeconds: Double
    public let captureInterval: Double

    public init(sourceSeconds: Double, outputSeconds: Int = maximumOutputSeconds) {
        self.sourceSeconds = max(1, sourceSeconds)
        let boundedOutput = min(Self.maximumOutputSeconds, max(1, outputSeconds))
        captureInterval = max(1, self.sourceSeconds / Double(Self.framesPerSecond * boundedOutput))
    }
    public var estimatedFrameCount: Int { max(1, Int(ceil(sourceSeconds / captureInterval))) }
    public var estimatedOutputSeconds: Double { Double(estimatedFrameCount) / Double(Self.framesPerSecond) }
}

public enum MovementBand: String, Codable, Equatable, Sendable {
    case sustainedStillness
    case gentleAdjustments
    case livingMovement
    case unavailable
}

public struct MotionSummary: Codable, Equatable, Sendable {
    public let sampleCount: Int
    public let averageJointDisplacement: Double

    public init(sampleCount: Int, averageJointDisplacement: Double) {
        self.sampleCount = max(0, sampleCount)
        self.averageJointDisplacement = max(0, averageJointDisplacement)
    }

    public var band: MovementBand {
        guard sampleCount >= 2 else { return .unavailable }
        if averageJointDisplacement <= 0.008 { return .sustainedStillness }
        if averageJointDisplacement <= 0.025 { return .gentleAdjustments }
        return .livingMovement
    }
}

public struct SessionPhase: Codable, Equatable, Sendable {
    public var audio: AudioKind?
    public var catalogAudio: CatalogAudioReference?
    public var seconds: Double
    public init(audio: AudioKind?, catalogAudio: CatalogAudioReference? = nil, seconds: Double) {
        self.audio = audio
        self.catalogAudio = catalogAudio
        self.seconds = seconds
    }
}

public protocol MeditationClock { var now: Date { get } }
public struct SystemMeditationClock: MeditationClock {
    public init() {}
    public var now: Date { Date() }
}

public struct SessionProgress: Codable, Equatable, Sendable {
    public var id: String
    public var configuration: SessionConfiguration
    public var startedAt: Date
    public var deadline: Date
    public var pausedAt: Date?
    public var localDate: String
    public var timeZoneID: String
    public var slot: String
    public var accumulatedPause: Double = 0

    public init(configuration: SessionConfiguration, now: Date, timeZone: TimeZone = .current, id: String = UUID().uuidString.lowercased()) {
        self.id = id; self.configuration = configuration; self.startedAt = now
        self.deadline = now.addingTimeInterval(configuration.totalSeconds)
        self.timeZoneID = timeZone.identifier
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        self.localDate = DayKey.make(now, timeZone: timeZone)
        self.slot = calendar.component(.hour, from: now) < 12 ? "morning" : "evening"
    }
    public func remaining(at now: Date) -> Double { max(0, deadline.timeIntervalSince(pausedAt ?? now)) }
    public func elapsed(at now: Date) -> Double {
        // Derive elapsed time directly so fractional audio durations do not
        // introduce cancellation errors at exact phase boundaries.
        if (pausedAt ?? now) >= deadline { return configuration.totalSeconds }
        return min(configuration.totalSeconds, max(0, (pausedAt ?? now).timeIntervalSince(startedAt) - accumulatedPause))
    }
    public func isComplete(at now: Date) -> Bool { pausedAt == nil && now >= deadline }
    public mutating func pause(at now: Date) {
        guard pausedAt == nil, now < deadline else { return }; pausedAt = now
    }
    public mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        let duration = max(0, now.timeIntervalSince(pausedAt))
        deadline = deadline.addingTimeInterval(duration); accumulatedPause += duration; self.pausedAt = nil
    }
    public func phase(at now: Date) -> (index: Int, phase: SessionPhase, offset: Double)? {
        let elapsed = elapsed(at: now)
        guard elapsed < configuration.totalSeconds else { return nil }
        var start = 0.0
        for (index, phase) in configuration.phases.enumerated() {
            if elapsed < start + phase.seconds { return (index, phase, elapsed - start) }
            start += phase.seconds
        }
        return nil
    }
}

public struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var startedAt: Double
    public var endedAt: Double
    public var durationSeconds: Double
    public var localDate: String
    public var timeZoneID: String
    public var slot: String
    public var configuration: SessionConfiguration
    public var shareAtCompletion: Bool
    public var imported: Bool
    public var completed: Bool
    public var plannedDurationSeconds: Double

    public init(progress: SessionProgress, share: Bool) {
        id = progress.id; startedAt = progress.startedAt.timeIntervalSince1970 * 1000
        endedAt = progress.deadline.timeIntervalSince1970 * 1000
        durationSeconds = progress.configuration.totalSeconds
        localDate = progress.localDate; timeZoneID = progress.timeZoneID; slot = progress.slot
        configuration = progress.configuration; shareAtCompletion = share; imported = false
        completed = true; plannedDurationSeconds = progress.configuration.totalSeconds
    }

    public init(progress: SessionProgress, endedEarlyAt: Date) {
        id = progress.id; startedAt = progress.startedAt.timeIntervalSince1970 * 1000
        endedAt = endedEarlyAt.timeIntervalSince1970 * 1000
        durationSeconds = progress.elapsed(at: endedEarlyAt)
        localDate = progress.localDate; timeZoneID = progress.timeZoneID; slot = progress.slot
        configuration = progress.configuration; shareAtCompletion = false; imported = false
        completed = false; plannedDurationSeconds = progress.configuration.totalSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, durationSeconds, localDate, timeZoneID, slot
        case configuration, shareAtCompletion, imported, completed, plannedDurationSeconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        startedAt = try values.decode(Double.self, forKey: .startedAt)
        endedAt = try values.decode(Double.self, forKey: .endedAt)
        durationSeconds = try values.decode(Double.self, forKey: .durationSeconds)
        localDate = try values.decode(String.self, forKey: .localDate)
        timeZoneID = try values.decode(String.self, forKey: .timeZoneID)
        slot = try values.decode(String.self, forKey: .slot)
        configuration = try values.decode(SessionConfiguration.self, forKey: .configuration)
        shareAtCompletion = try values.decodeIfPresent(Bool.self, forKey: .shareAtCompletion) ?? false
        imported = try values.decodeIfPresent(Bool.self, forKey: .imported) ?? false
        completed = try values.decodeIfPresent(Bool.self, forKey: .completed) ?? true
        plannedDurationSeconds = try values.decodeIfPresent(Double.self, forKey: .plannedDurationSeconds) ?? configuration.totalSeconds
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(startedAt, forKey: .startedAt)
        try values.encode(endedAt, forKey: .endedAt)
        try values.encode(durationSeconds, forKey: .durationSeconds)
        try values.encode(localDate, forKey: .localDate)
        try values.encode(timeZoneID, forKey: .timeZoneID)
        try values.encode(slot, forKey: .slot)
        try values.encode(configuration, forKey: .configuration)
        try values.encode(shareAtCompletion, forKey: .shareAtCompletion)
        try values.encode(imported, forKey: .imported)
        try values.encode(completed, forKey: .completed)
        try values.encode(plannedDurationSeconds, forKey: .plannedDurationSeconds)
    }
    public var startDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
}

public enum DayKey {
    public static func make(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    public static func previous(_ key: String) -> String? {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key), let previous = formatter.calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        return formatter.string(from: previous)
    }
}

public struct SocialEventCandidate: Equatable, Sendable {
    public var id: String
    public var friendID: String
    public var completedAt: Date
    public var slot: String
    public init(id: String, friendID: String, completedAt: Date, slot: String = "practice") {
        self.id = id; self.friendID = friendID; self.completedAt = completedAt; self.slot = slot
    }
}

public struct SocialFriendRule: Equatable, Sendable {
    public var id: String
    public var muted: Bool
    public var firstSeenAt: Date
    public init(id: String, muted: Bool, firstSeenAt: Date) {
        self.id = id; self.muted = muted; self.firstSeenAt = firstSeenAt
    }
}

public struct SocialNotificationBatch: Equatable, Sendable {
    public var friendID: String
    public var eventIDs: [String]
    public var slot: String
    public init(friendID: String, eventIDs: [String], slot: String = "practice") {
        self.friendID = friendID; self.eventIDs = eventIDs; self.slot = slot
    }
}

public enum SocialNotificationPolicy {
    public static func batches(receiving: Bool, events: [SocialEventCandidate], friends: [SocialFriendRule]) -> [SocialNotificationBatch] {
        guard receiving else { return [] }
        let rules = Dictionary(uniqueKeysWithValues: friends.map { ($0.id, $0) })
        let eligible = events.filter { event in
            guard let friend = rules[event.friendID], !friend.muted else { return false }
            return event.completedAt >= friend.firstSeenAt
        }
        return Dictionary(grouping: eligible, by: \.friendID).keys.sorted().map { friendID in
            let ids = eligible.filter { $0.friendID == friendID }
                .sorted { ($0.completedAt, $0.id) < ($1.completedAt, $1.id) }.map(\.id)
            let latest = eligible.filter { $0.friendID == friendID }.max { $0.completedAt < $1.completedAt }
            return SocialNotificationBatch(friendID: friendID, eventIDs: ids, slot: latest?.slot ?? "practice")
        }
    }
}

public struct MeditationStatistics: Equatable, Sendable {
    public var sessions: Int
    public var partialSessions: Int
    public var minutes: Int
    public var dailyStreak: Int
    public var twiceDailyStreak: Int
    public var weeklySessions: Int
    public var weeklyMinutes: Int
    public var nextMilestone: Int
    public var sessionsToNextMilestone: Int
    public var continuity: PracticeContinuity
    public init(records: [SessionRecord], now: Date = Date(), timeZone: TimeZone = .current) {
        let allUnique = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        let unique = allUnique.filter(\.completed)
        sessions = unique.count
        partialSessions = allUnique.filter { !$0.completed }.count
        minutes = Int(allUnique.reduce(0) { $0 + $1.durationSeconds } / 60)
        var days: [String: Set<String>] = [:]
        for record in unique { days[record.localDate, default: []].insert(record.slot) }
        let today = DayKey.make(now, timeZone: timeZone)
        func streak(_ qualifies: (Set<String>) -> Bool) -> Int {
            var key = qualifies(days[today] ?? []) ? today : DayKey.previous(today)
            var count = 0
            while let day = key, qualifies(days[day] ?? []) { count += 1; key = DayKey.previous(day) }
            return count
        }
        dailyStreak = streak { !$0.isEmpty }
        twiceDailyStreak = streak { $0.contains("morning") && $0.contains("evening") }
        continuity = PracticeContinuity(records: Array(unique), now: now, timeZone: timeZone)
        var recentKeys: Set<String> = []
        var recent: String? = today
        for _ in 0..<7 {
            guard let key = recent else { break }
            recentKeys.insert(key)
            recent = DayKey.previous(key)
        }
        let weekly = unique.filter { recentKeys.contains($0.localDate) }
        let allWeekly = allUnique.filter { recentKeys.contains($0.localDate) }
        weeklySessions = weekly.count
        weeklyMinutes = Int(allWeekly.reduce(0) { $0 + $1.durationSeconds } / 60)
        let milestones = [1, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]
        let sessionCount = unique.count
        let upcomingMilestone = milestones.first(where: { $0 > sessionCount }) ?? ((sessionCount / 1_000) + 1) * 1_000
        nextMilestone = upcomingMilestone
        sessionsToNextMilestone = max(0, upcomingMilestone - sessionCount)
    }
}

public struct PracticeContinuity: Equatable, Sendable {
    public var activeDays: Int
    public var linkedSessions: Int
    public var pauseUsed: Bool
    public var practicedToday: Bool
    public var needsRecoveryToday: Bool

    public init(records: [SessionRecord], now: Date = Date(), timeZone: TimeZone = .current) {
        let unique = Dictionary(records.filter(\.completed).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        let grouped = Dictionary(grouping: unique, by: \.localDate)
        let today = DayKey.make(now, timeZone: timeZone)
        let yesterday = DayKey.previous(today)
        practicedToday = !(grouped[today] ?? []).isEmpty

        var cursor: String? = practicedToday ? today : yesterday
        var includedDays: [String] = []
        var pendingPause = false
        var committedPause = false

        while let day = cursor {
            if !(grouped[day] ?? []).isEmpty {
                if pendingPause {
                    committedPause = true
                    pendingPause = false
                }
                includedDays.append(day)
            } else if !committedPause && !pendingPause {
                pendingPause = true
            } else {
                break
            }
            cursor = DayKey.previous(day)
        }

        activeDays = includedDays.count
        linkedSessions = includedDays.reduce(0) { $0 + (grouped[$1]?.count ?? 0) }
        pauseUsed = committedPause
        needsRecoveryToday = !practicedToday && committedPause && activeDays > 0
    }
}

public struct ReminderSettings: Codable, Equatable, Sendable {
    public var morningEnabled = false
    public var eveningEnabled = false
    public var morningMinute = 7 * 60
    public var eveningMinute = 21 * 60
    public var continuityEnabled = false
    public var continuityMinute = 20 * 60
    public var sound = true
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case morningEnabled, eveningEnabled, morningMinute, eveningMinute, continuityEnabled, continuityMinute, sound
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        morningEnabled = try values.decodeIfPresent(Bool.self, forKey: .morningEnabled) ?? false
        eveningEnabled = try values.decodeIfPresent(Bool.self, forKey: .eveningEnabled) ?? false
        morningMinute = try values.decodeIfPresent(Int.self, forKey: .morningMinute) ?? 7 * 60
        eveningMinute = try values.decodeIfPresent(Int.self, forKey: .eveningMinute) ?? 21 * 60
        continuityEnabled = try values.decodeIfPresent(Bool.self, forKey: .continuityEnabled) ?? false
        continuityMinute = try values.decodeIfPresent(Int.self, forKey: .continuityMinute) ?? 20 * 60
        sound = try values.decodeIfPresent(Bool.self, forKey: .sound) ?? true
    }
}
