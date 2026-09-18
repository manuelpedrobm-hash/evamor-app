import Foundation
import SwiftData
import CloudKit
import Observation
import MeditationCore

@MainActor @Observable final class AppModel {
    let store: LocalStore
    let cloud: CloudService
    let notifications: NotificationService
    let engine: SessionEngine
    let sync: SyncService
    let catalog: AudioCatalogService
    let owner = "local"
    var configuration = SessionConfiguration()
    var reminders = ReminderSettings()
    var shareSessions = false
    var socialNotifications = false
    var displayName = ""
    var cloudAvailable = false
    var notificationStatus = "Comprobando…"
    var records: [SessionRecord] = []
    var friends: [RemoteFriend] = []
    var tab = 0
    var error: String?
    var completionMessage = false
    var completionTitle = "Sé feliz"
    var completionSubtitle = "Tu sesión se ha guardado"
    var showCompletionCelebration = false

    init(container: ModelContainer) {
        store = LocalStore(container: container)
        cloud = CloudService()
        notifications = NotificationService()
        let catalog = AudioCatalogService()
        self.catalog = catalog
        let audio = AudioService(catalogURL: { [weak catalog] id in catalog?.localURL(for: id) })
        engine = SessionEngine(repository: store, audio: audio, notifications: notifications)
        sync = SyncService(store: store, cloud: cloud)
        audio.onInterruption = { [weak engine] in engine?.pause() }
        engine.sharingAllowed = { [weak self] owner in (try? self?.store.preferences(owner: owner).shareSessions) ?? false }
        engine.onCompletion = { [weak self] sessionID in self?.handleCompletion(sessionID: sessionID) }
        engine.onPartialSaved = { [weak self] sessionID, elapsed in self?.handlePartialSaved(sessionID: sessionID, elapsed: elapsed) }
        sync.onRefresh = { [weak self] in self?.reload() }
        reload(); engine.restore()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetUITestSession") {
            engine.cancel()
        }
#endif
#if DEBUG
        // Used only by the simulator screenshot workflow. It never marks a
        // session as completed or writes sample data.
        if ProcessInfo.processInfo.arguments.contains("-showCompletionPreview") {
            showCompletionCelebration = true
        }
        if ProcessInfo.processInfo.arguments.contains("-showActiveSessionPreview") {
            engine.start(configuration, owner: owner)
        }
        if ProcessInfo.processInfo.arguments.contains("-showPartialCompletionPreview") {
            completionMessage = true
            completionTitle = "Práctica guardada"
            completionSubtitle = "Has meditado \(Self.elapsedLabel(1_425)). Queda en el historial como parcial."
            showCompletionCelebration = true
        }
#endif
    }

    var statistics: MeditationStatistics { MeditationStatistics(records: records) }

    func reload() {
        do {
            let preferences = try store.preferences(owner: owner)
            configuration = try preferences.configuration(); reminders = try preferences.reminders()
            shareSessions = preferences.shareSessions; socialNotifications = preferences.socialNotifications
            displayName = preferences.displayName
            records = try store.records(owner: owner); friends = try store.friends(owner: owner)
            sync.updatePending()
        } catch { self.error = error.localizedDescription }
    }

    func start() async {
        await catalog.refresh()
        await refreshDiagnostics()
        do { try await notifications.reconcile(reminders, continuity: statistics.continuity) } catch { self.error = error.localizedDescription }
        if socialNotifications && cloudAvailable {
            do { try await cloud.setReceiving(true) } catch { self.error = error.localizedDescription }
        }
        await sync.sync(); reload()
        if socialNotifications { await processIncoming(deliver: true) }
        consumePendingQuickStart()
    }

    func foreground() async {
        engine.foreground()
        reload(); await refreshDiagnostics()
        do { try await notifications.reconcile(reminders, continuity: statistics.continuity) } catch { self.error = error.localizedDescription }
        await sync.sync(); reload()
        if socialNotifications { await processIncoming(deliver: true) }
        consumePendingQuickStart()
    }

    func beginMeditation() async {
        completionMessage = false
        completionTitle = "Sé feliz"
        completionSubtitle = "Tu sesión se ha guardado"
        if let reference = configuration.catalogAudio {
            guard let track = catalog.track(id: reference.id) else {
                error = "El audio de este perfil ya no está en el catálogo."
                return
            }
            do { _ = try await catalog.download(track) }
            catch { self.error = error.localizedDescription; return }
        }
        engine.start(configuration, owner: owner)
    }

    func pauseSession() { engine.pause() }

    func resumeSession() async { engine.resume() }

    func endSessionEarly() { engine.finishEarly() }

    private func handleCompletion(sessionID: String) {
        completionMessage = true
        completionTitle = "Sé feliz"
        completionSubtitle = "Tu sesión se ha guardado"
        reload()
        presentSavedSession(sessionID: sessionID)
    }

    private func handlePartialSaved(sessionID: String, elapsed: Double) {
        completionMessage = true
        completionTitle = "Práctica guardada"
        completionSubtitle = "Has meditado \(Self.elapsedLabel(elapsed)). Queda en el historial como parcial."
        reload()
        presentSavedSession(sessionID: sessionID)
    }

    private func presentSavedSession(sessionID: String) {
        showCompletionCelebration = true
        Task { await finishCompletionWork() }
    }

    private static func elapsedLabel(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        let minutes = value / 60
        let remainder = value % 60
        if minutes == 0 { return "\(remainder) s" }
        if remainder == 0 { return minutes == 1 ? "1 min" : "\(minutes) min" }
        return "\(minutes) min \(remainder) s"
    }

    private func finishCompletionWork() async {
        try? await notifications.reconcile(reminders, continuity: statistics.continuity)
        await sync.sync(); reload()
        _ = await processIncoming(deliver: true)
    }

    func saveConfiguration(_ value: SessionConfiguration) {
        guard value.isValid else { return }
        do {
            let preferences = try store.preferences(owner: owner)
            preferences.configurationData = try JSONEncoder().encode(value)
            try store.commit(); configuration = value
        } catch { self.error = error.localizedDescription }
    }

    func setQuickDuration(_ minutes: Int) {
        var updated = configuration
        updated.minutes = minutes
        // A quick duration must always do what its label says. If future,
        // longer audio assets do not fit, prefer a silent session at that time.
        if !updated.isValid {
            updated.audio = []
            updated.catalogAudio = nil
        }
        saveConfiguration(updated)
    }

    func apply(_ profile: CatalogSessionProfile) {
        let track = profile.trackID.flatMap { catalog.track(id: $0) }
        let configuration = SessionConfiguration(
            minutes: profile.minutes,
            audio: profile.builtInAudio ?? [],
            catalogAudio: track?.reference
        )
        guard configuration.isValid else {
            error = "El perfil no cabe en la duración indicada por el catálogo."
            return
        }
        saveConfiguration(configuration)
    }

    func apply(_ profile: SavedSessionProfile) { saveConfiguration(profile.configuration) }

    func saveCurrentProfile(named name: String) { catalog.saveProfile(name: name, configuration: configuration) }

    func deleteProfile(id: String) { catalog.deleteProfile(id: id) }

    private func consumePendingQuickStart() {
        guard engine.progress == nil else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "pendingQuickStartMinutes") != nil else { return }
        let minutes = defaults.integer(forKey: "pendingQuickStartMinutes")
        defaults.removeObject(forKey: "pendingQuickStartMinutes")
        var updated = configuration
        updated.minutes = min(480, max(5, minutes))
        guard updated.isValid else { return }
        saveConfiguration(updated)
        engine.start(updated, owner: owner)
    }

    func saveReminders(_ value: ReminderSettings) async {
        do {
            if value.morningEnabled || value.eveningEnabled || value.continuityEnabled {
                guard try await notifications.requestPermission() else { error = "Los avisos están desactivados en los ajustes del iPhone."; return }
            }
            let preferences = try store.preferences(owner: owner)
            preferences.reminderData = try JSONEncoder().encode(value)
            try store.commit(); reminders = value
            try await notifications.reconcile(value, continuity: statistics.continuity)
        } catch { self.error = error.localizedDescription }
    }

    func setSocial(share: Bool, receive: Bool) async {
        do {
            if share || receive {
                guard await cloud.available else { throw CloudError.accountUnavailable }
            }
            if receive && !socialNotifications {
                guard try await notifications.requestPermission() else { error = "Activa las notificaciones en los ajustes del iPhone."; return }
            }
            let preferences = try store.preferences(owner: owner)
            preferences.shareSessions = share; preferences.socialNotifications = receive
            try store.commit(); shareSessions = share; socialNotifications = receive
            if await cloud.available { try await cloud.setReceiving(receive) }
            if receive {
                await sync.sync(); reload(); await processIncoming(deliver: false)
            } else {
                await notifications.clearSocial()
            }
            await sync.sync()
        } catch { self.error = error.localizedDescription; reload() }
    }

    func saveDisplayName(_ value: String) {
        do {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let preferences = try store.preferences(owner: owner)
            preferences.displayName = String(trimmed.prefix(60))
            try store.commit(); displayName = preferences.displayName
        } catch { self.error = error.localizedDescription }
    }

    func refreshDiagnostics() async {
        cloudAvailable = await cloud.available
        notificationStatus = await notifications.authorizationDescription()
    }

    func sendTestNotification() async {
        do {
            guard try await notifications.requestPermission() else {
                error = "Las notificaciones están desactivadas en los ajustes del iPhone."
                await refreshDiagnostics(); return
            }
            try await notifications.notifySocial(friendID: "test", count: 1, slot: "morning")
            await refreshDiagnostics()
        } catch { self.error = error.localizedDescription }
    }

    func deleteHistory() async {
        do {
            try store.deleteHistory(owner: owner)
            reload()
            await sync.sync()
            reload()
        } catch { self.error = error.localizedDescription }
    }

    func toggleMute(_ friend: RemoteFriend) {
        do { try store.setMuted(!friend.muted, friendID: friend.id, owner: owner); reload() }
        catch { self.error = error.localizedDescription }
    }

    func remove(_ friend: RemoteFriend) async {
        do { try await cloud.remove(friend); await sync.sync(); reload() }
        catch { self.error = error.localizedDescription }
    }

    func acceptShare(_ metadata: CKShare.Metadata) async {
        do { try await cloud.accept(metadata); await sync.sync(); reload(); await processIncoming(deliver: false); tab = 2 }
        catch { self.error = error.localizedDescription }
    }

    func receivedCloudPush() async -> Bool {
        guard socialNotifications else { return false }
        await sync.sync(); reload()
        return await processIncoming(deliver: true)
    }

    @discardableResult private func processIncoming(deliver: Bool) async -> Bool {
        // Without an iCloud account there is nothing to check, and the app must
        // not surface a CloudKit error after every purely local session.
        guard await cloud.available else { return false }
        do {
            // Keep social events unread while meditating; completion retries them after closing the session.
            if deliver && engine.progress != nil { return false }
            let fresh = try store.claim(try await cloud.incomingSignals())
            guard deliver, socialNotifications else { return !fresh.isEmpty }
            let candidates = fresh.map {
                SocialEventCandidate(id: $0.id, friendID: $0.friendID, completedAt: $0.completedAt, slot: $0.slot)
            }
            let policies = friends.filter { $0.direction == .incoming }.map {
                SocialFriendRule(id: $0.id, muted: $0.muted, firstSeenAt: $0.firstSeenAt)
            }
            for batch in SocialNotificationPolicy.batches(receiving: socialNotifications, events: candidates, friends: policies) {
                try await notifications.notifySocial(friendID: batch.friendID, count: batch.eventIDs.count, slot: batch.slot)
            }
            return !fresh.isEmpty
        } catch { self.error = error.localizedDescription; return false }
    }
}
