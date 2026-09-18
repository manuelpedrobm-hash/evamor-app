import UserNotifications
import MeditationCore

@MainActor final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private var endGeneration = 0
    private var endTask: Task<Void, Error>?
    func requestPermission() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    func authorizationDescription() async -> String {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized: return "Autorizadas"
        case .provisional: return "Provisionales"
        case .ephemeral: return "Temporales"
        case .denied: return "Desactivadas"
        case .notDetermined: return "Sin solicitar"
        @unknown default: return "Estado desconocido"
        }
    }
    func scheduleEnd(_ progress: SessionProgress) async throws {
        endGeneration += 1
        let generation = endGeneration
        let previous = endTask
        let task = Task { @MainActor in
            _ = try? await previous?.value
            guard generation == self.endGeneration else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: ["session-end"])
            guard progress.pausedAt == nil, progress.deadline > Date() else { return }
            let settings = await self.center.notificationSettings()
            guard generation == self.endGeneration else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Ecuanimidad"; content.body = "Tu sesión ha terminado."
            if progress.configuration.audio.contains(.closing) || progress.configuration.audio.contains(.metta) {
                content.sound = UNNotificationSound(named: UNNotificationSoundName("gong.wav"))
            }
            content.userInfo = ["destination": "meditate"]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, progress.deadline.timeIntervalSinceNow), repeats: false)
            try await self.center.add(UNNotificationRequest(identifier: "session-end", content: content, trigger: trigger))
            // New additions await this task, so cancellation cannot remove a newer request.
            if generation != self.endGeneration { self.center.removePendingNotificationRequests(withIdentifiers: ["session-end"]) }
        }
        endTask = task
        try await task.value
    }
    func cancelEnd() { endGeneration += 1; center.removePendingNotificationRequests(withIdentifiers: ["session-end"]); center.removeDeliveredNotifications(withIdentifiers: ["session-end"]) }
    func notifySocial(friendID: String, count: Int, slot: String = "practice") async throws {
        let content = UNMutableNotificationContent()
        content.title = "Práctica compartida"
        content.body = Self.socialMessage(count: count, slot: slot)
        content.sound = .default
        content.userInfo = ["destination": "friends"]
        let identifier = "social-\(friendID)-\(UUID().uuidString)"
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
    static func socialMessage(count: Int, slot: String) -> String {
        if count == 1 {
            let practice = slot == "morning" ? "su meditación matutina" : (slot == "evening" ? "su meditación de la tarde" : "una meditación")
            return "Un amigo ha completado \(practice) y te envía metta."
        }
        return "Un amigo ha completado \(count) meditaciones y te envía metta."
    }
    func clearSocial() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("social-") }
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("social-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }
    func reconcile(_ reminders: ReminderSettings, continuity: PracticeContinuity? = nil) async throws {
        center.removePendingNotificationRequests(withIdentifiers: ["morning", "evening", "continuity-recovery"])
        for (id, enabled, minute) in [("morning", reminders.morningEnabled, reminders.morningMinute), ("evening", reminders.eveningEnabled, reminders.eveningMinute)] where enabled {
            let content = UNMutableNotificationContent(); content.title = "Un momento para meditar"
            content.body = id == "morning" ? "Tu práctica de mañana." : "Tu práctica de noche."
            content.userInfo = ["destination": "meditate"]
            if reminders.sound { content.sound = UNNotificationSound(named: UNNotificationSoundName("gong.wav")) }
            var components = DateComponents(); components.hour = minute / 60; components.minute = minute % 60
            // No fixed time zone: follows the device's wall clock; reconcile on significant time changes.
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        if reminders.continuityEnabled, continuity?.needsRecoveryToday == true {
            let now = Date()
            var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
            components.hour = reminders.continuityMinute / 60
            components.minute = reminders.continuityMinute % 60
            if let reminderDate = Calendar.current.date(from: components), reminderDate > now {
                let content = UNMutableNotificationContent()
                content.title = "Tu hilo sigue abierto"
                content.body = "Si te apetece, hoy puedes retomar tu práctica."
                content.userInfo = ["destination": "meditate"]
                if reminders.sound { content.sound = UNNotificationSound(named: UNNotificationSoundName("gong.wav")) }
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await center.add(UNNotificationRequest(identifier: "continuity-recovery", content: content, trigger: trigger))
            }
        }
    }
}
