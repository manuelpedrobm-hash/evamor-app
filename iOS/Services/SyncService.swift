import Foundation
import Observation
import Network
import MeditationCore

@MainActor @Observable final class SyncService {
    private(set) var syncing = false
    private(set) var pending = 0
    private(set) var lastSync: Date?
    var error: String?
    var onRefresh: (() -> Void)?
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let cloud: CloudGateway
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    private let owner = "local"

    init(store: LocalStore, cloud: CloudGateway) {
        self.store = store; self.cloud = cloud
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.sync() }
        }
        monitor.start(queue: DispatchQueue(label: "meditation.connectivity"))
    }

    func updatePending() { pending = (try? store.operations(owner: owner).count) ?? 0 }

    func sync() async {
        guard !syncing, await cloud.available else { updatePending(); return }
        syncing = true; error = nil
        defer { syncing = false; updatePending() }
        do {
            let sharingEnabled = try store.preferences(owner: owner).shareSessions
            for operation in try store.operations(owner: owner).filter({ $0.kind == "deleteHistory" }) {
                operation.attempts += 1; try store.commit()
                try await cloud.deleteHistory()
                try store.acknowledge([operation])
            }
            for operation in try store.operations(owner: owner).filter({ $0.kind == "session" }) {
                operation.attempts += 1; try store.commit()
                let record = try JSONDecoder().decode(SessionRecord.self, from: operation.payload)
                // Partial practices remain private even if the user's general
                // sharing preference is enabled. CloudService repeats this
                // guard before creating a social signal.
                try await cloud.upload(record, share: sharingEnabled && record.completed)
                try store.acknowledge([operation])
            }
            try store.merge(try await cloud.sessions(), owner: owner)
            try store.replaceFriends(try await cloud.friends(), owner: owner)
            lastSync = .now; retryTask?.cancel(); onRefresh?()
        } catch {
            self.error = error.localizedDescription
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }; await self?.sync()
            }
        }
    }
}
