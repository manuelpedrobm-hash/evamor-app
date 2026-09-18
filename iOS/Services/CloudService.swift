import Foundation
import CloudKit
import UIKit
import MeditationCore

struct RemoteFriend: Codable, Identifiable, Equatable {
    enum Direction: String, Codable { case incoming, outgoing }
    var id: String
    var name: String
    var status: String
    var direction: Direction
    var muted: Bool
    var firstSeenAt: Date
    var cloudIdentifier: String
}

struct SocialSignal: Equatable {
    var id: String
    var friendID: String
    var completedAt: Date
    var slot: String
}

@MainActor protocol CloudGateway {
    var available: Bool { get async }
    func upload(_ record: SessionRecord, share: Bool) async throws
    func sessions() async throws -> [SessionRecord]
    func friends() async throws -> [RemoteFriend]
    func incomingSignals() async throws -> [SocialSignal]
    func setReceiving(_ enabled: Bool) async throws
    func deleteHistory() async throws
}

@MainActor final class CloudService: CloudGateway {
    let container: CKContainer?
    private var privateDatabase: CKDatabase { container!.privateCloudDatabase }
    private var sharedDatabase: CKDatabase { container!.sharedCloudDatabase }
    private let channelZoneID = CKRecordZone.ID(zoneName: "PracticeChannel")
    private var channelRecordID: CKRecord.ID { CKRecord.ID(recordName: "channel", zoneID: channelZoneID) }
    private let subscriptionID = "shared-practice-signals-v1"

    init(container: CKContainer? = nil) {
        if let container {
            self.container = container
            return
        }
#if targetEnvironment(simulator) || EVAMOR_LOCAL
        self.container = nil
#else
        self.container = .default()
#endif
    }

    var available: Bool {
        get async {
            guard let container else { return false }
            return await withCheckedContinuation { continuation in
                container.accountStatus { status, _ in continuation.resume(returning: status == .available) }
            }
        }
    }

    func upload(_ record: SessionRecord, share: Bool) async throws {
        try await requireAccount()
        let id = CKRecord.ID(recordName: "session-\(record.id)")
        let cloudRecord: CKRecord
        do { cloudRecord = try await privateDatabase.record(for: id) }
        catch let error as CKError where error.code == .unknownItem { cloudRecord = CKRecord(recordType: "MeditationSession", recordID: id) }
        cloudRecord["payload"] = try JSONEncoder().encode(record) as CKRecordValue
        cloudRecord["startedAt"] = record.startDate as CKRecordValue
        _ = try await privateDatabase.save(cloudRecord)

        guard share, record.shareAtCompletion, record.completed else { return }
        let root = try await channel(displayName: nil)
        let signalID = CKRecord.ID(recordName: "signal-\(record.id)", zoneID: channelZoneID)
        let signal = CKRecord(recordType: "PracticeSignal", recordID: signalID)
        signal.parent = CKRecord.Reference(recordID: root.recordID, action: .none)
        signal["eventID"] = record.id as CKRecordValue
        signal["completedAt"] = Date(timeIntervalSince1970: record.endedAt / 1000) as CKRecordValue
        signal["slot"] = record.slot as CKRecordValue
        do { _ = try await privateDatabase.save(signal) }
        catch let error as CKError where error.code == .serverRecordChanged { return }
    }

    func sessions() async throws -> [SessionRecord] {
        try await requireAccount()
        let records = try await allRecords(in: privateDatabase, type: "MeditationSession", zoneID: nil)
        return records.compactMap { record in
            guard let payload = record["payload"] as? Data else { return nil }
            return try? JSONDecoder().decode(SessionRecord.self, from: payload)
        }
    }

    func prepareShare(displayName: String) async throws -> CKShare {
        try await requireAccount()
        let root = try await channel(displayName: displayName)
        if let reference = root.share, let existing = try await privateDatabase.record(for: reference.recordID) as? CKShare {
            return existing
        }
        let share = CKShare(rootRecord: root)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = "Canal de práctica" as CKRecordValue
        let result = try await privateDatabase.modifyRecords(saving: [root, share], deleting: [], savePolicy: .changedKeys, atomically: true)
        guard case .success(let saved)? = result.saveResults[share.recordID], let savedShare = saved as? CKShare else {
            throw CloudError.shareUnavailable
        }
        return savedShare
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        try await requireAccount()
        _ = try await container!.accept(metadata)
    }

    func friends() async throws -> [RemoteFriend] {
        try await requireAccount()
        var result: [RemoteFriend] = []
        if let share = try? await existingShare() {
            for participant in share.participants where participant.role != .owner {
                guard let identifier = participant.userIdentity.userRecordID?.recordName else { continue }
                let components = participant.userIdentity.nameComponents
                let formatted = components.map { PersonNameComponentsFormatter().string(from: $0) }
                let status: String
                switch participant.acceptanceStatus {
                case .accepted: status = "accepted"
                case .pending: status = "pending"
                case .removed: status = "removed"
                default: status = "unknown"
                }
                result.append(RemoteFriend(
                    id: "outgoing|\(identifier)", name: formatted?.nonEmpty ?? "Invitación privada",
                    status: status, direction: .outgoing, muted: false, firstSeenAt: .now,
                    cloudIdentifier: identifier
                ))
            }
        }
        for zone in try await sharedDatabase.allRecordZones() {
            let roots = try await allRecords(in: sharedDatabase, type: "PracticeChannel", zoneID: zone.zoneID)
            guard let root = roots.first else { continue }
            let id = Self.friendID(for: zone.zoneID)
            result.append(RemoteFriend(
                id: id, name: (root["displayName"] as? String)?.nonEmpty ?? "Amigo",
                status: "accepted", direction: .incoming, muted: false, firstSeenAt: .now,
                cloudIdentifier: Self.zoneIdentifier(for: zone.zoneID)
            ))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func incomingSignals() async throws -> [SocialSignal] {
        try await requireAccount()
        var signals: [SocialSignal] = []
        for zone in try await sharedDatabase.allRecordZones() {
            let friendID = Self.friendID(for: zone.zoneID)
            for record in try await allRecords(in: sharedDatabase, type: "PracticeSignal", zoneID: zone.zoneID) {
                guard let eventID = record["eventID"] as? String, let completedAt = record["completedAt"] as? Date else { continue }
                let slot = (record["slot"] as? String) ?? "practice"
                signals.append(.init(id: "\(friendID)|\(eventID)", friendID: friendID, completedAt: completedAt, slot: slot))
            }
        }
        return signals
    }

    func setReceiving(_ enabled: Bool) async throws {
        try await requireAccount()
        if enabled {
            let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            do { _ = try await sharedDatabase.save(subscription) }
            catch let error as CKError where error.code == .serverRecordChanged { }
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            do { _ = try await sharedDatabase.deleteSubscription(withID: subscriptionID) }
            catch let error as CKError where error.code == .unknownItem { }
        }
    }

    func deleteHistory() async throws {
        try await requireAccount()
        let sessions = try await allRecords(in: privateDatabase, type: "MeditationSession", zoneID: nil)
        // A user can delete a purely local history before a social channel has ever
        // existed. A missing custom zone must not prevent that deletion from syncing.
        let signals = (try? await allRecords(in: privateDatabase, type: "PracticeSignal", zoneID: channelZoneID)) ?? []
        for record in sessions + signals {
            do { _ = try await privateDatabase.deleteRecord(withID: record.recordID) }
            catch let error as CKError where error.code == .unknownItem { }
        }
    }

    func remove(_ friend: RemoteFriend) async throws {
        try await requireAccount()
        if friend.direction == .incoming {
            let zoneID = try Self.zoneID(from: friend.cloudIdentifier)
            _ = try await sharedDatabase.deleteRecordZone(withID: zoneID)
            return
        }
        let share = try await existingShare()
        guard let participant = share.participants.first(where: {
            $0.userIdentity.userRecordID?.recordName == friend.cloudIdentifier
        }) else { return }
        share.removeParticipant(participant)
        _ = try await privateDatabase.save(share)
    }

    private func requireAccount() async throws {
        guard container != nil, await available else { throw CloudError.accountUnavailable }
    }

    private func channel(displayName: String?) async throws -> CKRecord {
        do { _ = try await privateDatabase.save(CKRecordZone(zoneID: channelZoneID)) }
        catch let error as CKError where error.code == .serverRecordChanged { }
        let root: CKRecord
        do { root = try await privateDatabase.record(for: channelRecordID) }
        catch let error as CKError where error.code == .unknownItem { root = CKRecord(recordType: "PracticeChannel", recordID: channelRecordID) }
        if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            root["displayName"] = String(displayName.prefix(60)) as CKRecordValue
        } else if root["displayName"] == nil {
            root["displayName"] = "Amigo" as CKRecordValue
        }
        return try await privateDatabase.save(root)
    }

    private func existingShare() async throws -> CKShare {
        let root = try await privateDatabase.record(for: channelRecordID)
        guard let reference = root.share, let share = try await privateDatabase.record(for: reference.recordID) as? CKShare else {
            throw CloudError.shareUnavailable
        }
        return share
    }

    private func allRecords(in database: CKDatabase, type: String, zoneID: CKRecordZone.ID?) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        var page = try await database.records(matching: query, inZoneWith: zoneID)
        var records = page.matchResults.compactMap { try? $0.1.get() }
        while let cursor = page.queryCursor {
            page = try await database.records(continuingMatchFrom: cursor)
            records.append(contentsOf: page.matchResults.compactMap { try? $0.1.get() })
        }
        return records
    }

    private static func zoneIdentifier(for id: CKRecordZone.ID) -> String { "\(id.ownerName)|\(id.zoneName)" }
    private static func friendID(for id: CKRecordZone.ID) -> String { "incoming|\(zoneIdentifier(for: id))" }
    private static func zoneID(from value: String) throws -> CKRecordZone.ID {
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw CloudError.invalidFriend }
        return .init(zoneName: parts[1], ownerName: parts[0])
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }

enum CloudError: LocalizedError {
    case accountUnavailable, shareUnavailable, invalidFriend
    var errorDescription: String? {
        switch self {
        case .accountUnavailable: return "Activa iCloud Drive para Ecuanimidad en los ajustes del iPhone."
        case .shareUnavailable: return "No se pudo preparar la invitación privada. Inténtalo de nuevo."
        case .invalidFriend: return "La amistad guardada no es válida."
        }
    }
}
