import Foundation
import Observation
import UIKit
import MeditationCore

@MainActor @Observable final class SessionEngine {
    private(set) var progress: SessionProgress?
    private(set) var owner = "local"
    private(set) var remaining = 0.0
    private(set) var phaseTitle = "Silencio"
    var error: String?
    var onCompletion: ((String) -> Void)?
    var onPartialSaved: ((String, Double) -> Void)?
    var sharingAllowed: (String) -> Bool = { _ in false }
    @ObservationIgnored private let repository: SessionRepository
    @ObservationIgnored private let clock: MeditationClock
    @ObservationIgnored private let audio: MeditationAudioPlayer
    @ObservationIgnored private let notifications: NotificationService
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var playingIndex: Int?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    init(repository: SessionRepository, audio: MeditationAudioPlayer, notifications: NotificationService, clock: MeditationClock = SystemMeditationClock()) {
        self.repository = repository; self.audio = audio; self.notifications = notifications; self.clock = clock
    }
    var isPaused: Bool { progress?.pausedAt != nil }
    func restore() {
        do {
            guard let (owner, saved) = try repository.loadActive() else { return }
            self.owner = owner; progress = saved; activate()
        } catch { self.error = "No se pudo recuperar la sesión: \(error.localizedDescription)" }
    }
    func start(_ configuration: SessionConfiguration, owner: String, id: String = UUID().uuidString.lowercased()) {
        guard progress == nil, configuration.isValid else { return }
        do {
            let saved = SessionProgress(configuration: configuration, now: clock.now, id: id)
            try repository.saveActive(saved, owner: owner)
            self.owner = owner; progress = saved; activate()
        } catch { self.error = "No se pudo iniciar la sesión: \(error.localizedDescription)" }
    }
    private func activate() {
        UIApplication.shared.isIdleTimerDisabled = true
        tick(); timer?.invalidate()
        guard progress != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        scheduleEnd()
    }
    private func scheduleEnd() {
        guard let progress else { return }
        Task { do { try await notifications.scheduleEnd(progress) } catch { self.error = "No se pudo programar el aviso de finalización." } }
    }
    func foreground() {
        playbackTask?.cancel(); playingIndex = nil; tick()
        if progress != nil { UIApplication.shared.isIdleTimerDisabled = true; scheduleEnd() }
    }
    func tick() {
        guard let progress else { return }
        remaining = progress.remaining(at: clock.now)
        if progress.isComplete(at: clock.now) {
            audio.stop()
            do {
                try repository.complete(progress, owner: owner, share: sharingAllowed(owner))
                let completedID = progress.id
                finish(); onCompletion?(completedID)
            } catch {
                // Preserve the active record so reopening can safely retry the atomic completion.
                timer?.invalidate(); self.error = "No se pudo guardar la sesión. Vuelve a abrir la app para reintentarlo."
            }
            return
        }
        guard !isPaused, let current = progress.phase(at: clock.now) else { return }
        phaseTitle = current.phase.catalogAudio?.title ?? current.phase.audio?.title ?? "Silencio"
        guard playingIndex != current.index else { return }
        playbackTask?.cancel(); audio.stop(); playingIndex = current.index
        if current.phase.audio != nil || current.phase.catalogAudio != nil {
            playbackTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do { try await audio.play(current.phase, offset: current.offset) }
                catch is CancellationError { }
                catch { pause(); self.error = "No se pudo reproducir el audio. La sesión está pausada." }
            }
        }
    }
    func pause() {
        guard var saved = progress else { return }
        saved.pause(at: clock.now)
        do {
            try repository.saveActive(saved, owner: owner); progress = saved
            playbackTask?.cancel(); audio.stop(); playingIndex = nil; notifications.cancelEnd(); remaining = saved.remaining(at: clock.now)
        } catch { self.error = "No se pudo guardar la pausa." }
    }
    func resume() {
        guard var saved = progress else { return }; saved.resume(at: clock.now)
        do { try repository.saveActive(saved, owner: owner); progress = saved; playingIndex = nil; tick(); scheduleEnd() }
        catch { self.error = "No se pudo reanudar la sesión." }
    }
    func cancel() {
        do { try repository.discardActive(); finish() }
        catch { self.error = "No se pudo cerrar la sesión." }
    }
    func finishEarly() {
        guard let progress else { return }
        let endedAt = clock.now
        let elapsed = progress.elapsed(at: endedAt)
        do {
            try repository.finishEarly(progress, endedAt: endedAt, owner: owner)
            let sessionID = progress.id
            finish()
            onPartialSaved?(sessionID, elapsed)
        } catch {
            self.error = "No se pudo guardar la práctica parcial. Inténtalo de nuevo."
        }
    }
    private func finish() {
        timer?.invalidate(); timer = nil; playbackTask?.cancel(); playbackTask = nil; audio.stop(); notifications.cancelEnd()
        progress = nil; playingIndex = nil; UIApplication.shared.isIdleTimerDisabled = false
    }
}
