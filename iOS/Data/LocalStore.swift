import Foundation
import SwiftData
import MeditationCore

@Model final class MeditationSession {
    @Attribute(.unique) var key: String
    var owner: String
    var startedAt: Date
    var payload: Data
    init(owner: String, record: SessionRecord) throws {
        self.key = owner + ":" + record.id; self.owner = owner
        self.startedAt = record.startDate; self.payload = try JSONEncoder().encode(record)
    }
    func record() throws -> SessionRecord { try JSONDecoder().decode(SessionRecord.self, from: payload) }
}

@Model final class ActiveSession {
    @Attribute(.unique) var key: String
    var owner: String
    var payload: Data
    init(owner: String, progress: SessionProgress) throws {
        key = "active"; self.owner = owner; payload = try JSONEncoder().encode(progress)
    }
}

@Model final class Preferences {
    @Attribute(.unique) var owner: String
    var configurationData: Data
    var reminderData: Data
    var shareSessions: Bool
    var socialNotifications: Bool
    var displayName: String
    init(owner: String) throws {
        self.owner = owner
        configurationData = try JSONEncoder().encode(SessionConfiguration())
        reminderData = try JSONEncoder().encode(ReminderSettings())
        shareSessions = false; socialNotifications = false; displayName = ""
    }
    func configuration() throws -> SessionConfiguration { try JSONDecoder().decode(SessionConfiguration.self, from: configurationData) }
    func reminders() throws -> ReminderSettings { try JSONDecoder().decode(ReminderSettings.self, from: reminderData) }
}

@Model final class SyncOperation {
    @Attribute(.unique) var id: String
    var owner: String
    var kind: String
    var payload: Data
    var batchID: String?
    var createdAt: Date
    var attempts: Int
    init(owner: String, kind: String, payload: Data, id: String = UUID().uuidString.lowercased()) {
        self.id = id; self.owner = owner; self.kind = kind; self.payload = payload
        createdAt = Date(); attempts = 0
    }
}

@Model final class FriendSnapshot {
    @Attribute(.unique) var key: String
    var owner: String
    var friendID: String
    var name: String
    var status: String
    var direction: String
    var muted: Bool
    var firstSeenAt: Date
    var cloudIdentifier: String
    init(owner: String, friend: RemoteFriend) {
        key = owner + ":" + friend.id; self.owner = owner; friendID = friend.id
        name = friend.name; status = friend.status; direction = friend.direction.rawValue
        muted = friend.muted; firstSeenAt = friend.firstSeenAt; cloudIdentifier = friend.cloudIdentifier
    }
    var remote: RemoteFriend {
        .init(id: friendID, name: name, status: status,
              direction: RemoteFriend.Direction(rawValue: direction) ?? .incoming,
              muted: muted, firstSeenAt: firstSeenAt, cloudIdentifier: cloudIdentifier)
    }
}

@Model final class SocialReceipt {
    @Attribute(.unique) var id: String
    var receivedAt: Date
    init(id: String) { self.id = id; receivedAt = .now }
}

@MainActor protocol SessionRepository {
    func saveActive(_ progress: SessionProgress, owner: String) throws
    func loadActive() throws -> (String, SessionProgress)?
    func discardActive() throws
    func complete(_ progress: SessionProgress, owner: String, share: Bool) throws
    func finishEarly(_ progress: SessionProgress, endedAt: Date, owner: String) throws
    func records(owner: String) throws -> [SessionRecord]
}

@MainActor final class LocalStore: SessionRepository {
    let context: ModelContext
    init(container: ModelContainer) { context = ModelContext(container); context.autosaveEnabled = false }
    func commit() throws {
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func preferences(owner: String) throws -> Preferences {
        let items = try context.fetch(FetchDescriptor<Preferences>())
        if let item = items.first(where: { $0.owner == owner }) { return item }
        let item = try Preferences(owner: owner); context.insert(item); try commit(); return item
    }
    func saveActive(_ progress: SessionProgress, owner: String) throws {
        if let active = try context.fetch(FetchDescriptor<ActiveSession>()).first {
            active.owner = owner; active.payload = try JSONEncoder().encode(progress)
        } else { context.insert(try ActiveSession(owner: owner, progress: progress)) }
        try commit()
    }
    func loadActive() throws -> (String, SessionProgress)? {
        guard let item = try context.fetch(FetchDescriptor<ActiveSession>()).first else { return nil }
        return (item.owner, try JSONDecoder().decode(SessionProgress.self, from: item.payload))
    }
    func discardActive() throws {
        for item in try context.fetch(FetchDescriptor<ActiveSession>()) { context.delete(item) }
        try commit()
    }
    func complete(_ progress: SessionProgress, owner: String, share: Bool) throws {
        let record = SessionRecord(progress: progress, share: share)
        try saveFinished(record, owner: owner)
    }
    func finishEarly(_ progress: SessionProgress, endedAt: Date, owner: String) throws {
        let record = SessionRecord(progress: progress, endedEarlyAt: endedAt)
        try saveFinished(record, owner: owner)
    }
    private func saveFinished(_ record: SessionRecord, owner: String) throws {
        let key = owner + ":" + record.id
        if !(try context.fetch(FetchDescriptor<MeditationSession>())).contains(where: { $0.key == key }) {
            context.insert(try MeditationSession(owner: owner, record: record))
            context.insert(SyncOperation(owner: owner, kind: "session", payload: try JSONEncoder().encode(record), id: key))
        }
        for item in try context.fetch(FetchDescriptor<ActiveSession>()) { context.delete(item) }
        try commit() // Session, outbox entry and active-session removal are atomic.
    }
    func records(owner: String) throws -> [SessionRecord] {
        try context.fetch(FetchDescriptor<MeditationSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
            .filter { $0.owner == owner }.map { try $0.record() }
    }
    func deleteHistory(owner: String) throws {
        for session in try context.fetch(FetchDescriptor<MeditationSession>()) where session.owner == owner {
            context.delete(session)
        }
        let operations = try context.fetch(FetchDescriptor<SyncOperation>()).filter { $0.owner == owner }
        for operation in operations where operation.kind == "session" { context.delete(operation) }
        if !operations.contains(where: { $0.kind == "deleteHistory" }) {
            context.insert(SyncOperation(owner: owner, kind: "deleteHistory", payload: Data(), id: owner + ":deleteHistory"))
        }
        try commit()
    }
    func merge(_ records: [SessionRecord], owner: String) throws {
        let keys = Set(try context.fetch(FetchDescriptor<MeditationSession>()).map(\.key))
        for record in records where !keys.contains(owner + ":" + record.id) { context.insert(try MeditationSession(owner: owner, record: record)) }
        try commit()
    }
    func operations(owner: String) throws -> [SyncOperation] {
        try context.fetch(FetchDescriptor<SyncOperation>(sortBy: [SortDescriptor(\.createdAt)] )).filter { $0.owner == owner }
    }
    func acknowledge(_ operations: [SyncOperation]) throws { operations.forEach(context.delete); try commit() }
    func friends(owner: String) throws -> [RemoteFriend] {
        try context.fetch(FetchDescriptor<FriendSnapshot>()).filter { $0.owner == owner }.map(\.remote)
    }
    func replaceFriends(_ friends: [RemoteFriend], owner: String) throws {
        let existing = try context.fetch(FetchDescriptor<FriendSnapshot>()).filter { $0.owner == owner }
        let preferences = Dictionary(uniqueKeysWithValues: existing.map { ($0.friendID, ($0.muted, $0.firstSeenAt)) })
        existing.forEach(context.delete)
        for var friend in friends {
            if let saved = preferences[friend.id] { friend.muted = saved.0; friend.firstSeenAt = saved.1 }
            context.insert(FriendSnapshot(owner: owner, friend: friend))
        }
        try commit()
    }
    func setMuted(_ muted: Bool, friendID: String, owner: String) throws {
        guard let item = try context.fetch(FetchDescriptor<FriendSnapshot>()).first(where: { $0.owner == owner && $0.friendID == friendID }) else { return }
        item.muted = muted; try commit()
    }
    func claim(_ signals: [SocialSignal]) throws -> [SocialSignal] {
        let known = Set(try context.fetch(FetchDescriptor<SocialReceipt>()).map(\.id))
        let fresh = signals.filter { !known.contains($0.id) }
        fresh.forEach { context.insert(SocialReceipt(id: $0.id)) }
        try commit()
        return fresh
    }
}
