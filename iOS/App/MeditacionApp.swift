import SwiftUI
import SwiftData
import CloudKit
import UserNotifications

@main struct MeditacionApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel?
    @AppStorage(OldStudentAccess.grantedKey) private var oldStudentAccessGranted = false
    private var storageError: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        }
        if ProcessInfo.processInfo.arguments.contains("-resetOldStudentAccess") {
            UserDefaults.standard.removeObject(forKey: OldStudentAccess.grantedKey)
        } else if ProcessInfo.processInfo.arguments.contains("-grantOldStudentAccess") {
            UserDefaults.standard.set(true, forKey: OldStudentAccess.grantedKey)
        }
#endif
        do {
            let schema = Schema([MeditationSession.self, ActiveSession.self, Preferences.self, SyncOperation.self, FriendSnapshot.self, SocialReceipt.self, MeditationMedia.self])
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: configuration)
            _model = State(initialValue: AppModel(container: container))
        } catch {
            _model = State(initialValue: nil)
            storageError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if !oldStudentAccessGranted {
                OldStudentAccessView { oldStudentAccessGranted = true }
            } else if let model {
                RootView().environment(model)
                    .tint(Palette.green)
                    .task { delegate.model = model; await model.start() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { Task { await model.foreground() } }
                        else if phase == .background { model.background() }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                        Task { await model.foreground() }
                    }
            } else {
                ContentUnavailableView("No se pudo abrir el historial", systemImage: "externaldrive.badge.exclamationmark", description: Text("Tus datos no se han borrado. Cierra y vuelve a abrir la app.\n\(storageError ?? "")"))
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor weak var model: AppModel?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in await model?.acceptShare(cloudKitShareMetadata) }
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { completionHandler(.noData); return }
        Task { @MainActor in
            let changed = await model?.receivedCloudPush() ?? false
            completionHandler(changed ? .newData : .noData)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let social = notification.request.content.userInfo["destination"] as? String == "friends"
            if model?.engine.progress != nil || (social && model?.socialNotifications != true) { completionHandler([]) }
            else { completionHandler([.banner, .sound]) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            model?.tab = response.notification.request.content.userInfo["destination"] as? String == "friends" ? 2 : 0
            completionHandler()
        }
    }
}
