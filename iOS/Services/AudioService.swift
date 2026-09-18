import AVFoundation
import MeditationCore

@MainActor protocol MeditationAudioPlayer {
    func play(_ phase: SessionPhase, offset: Double) async throws
    func stop()
}

@MainActor final class AudioService: MeditationAudioPlayer {
    private var player: AVAudioPlayer?
    private var playbackGeneration = 0
    var isPlaying: Bool { player?.isPlaying == true }
    var onInterruption: (() -> Void)?
    private let catalogURL: (String) -> URL?
    private var observers: [NSObjectProtocol] = []
    init(catalogURL: @escaping (String) -> URL? = { _ in nil }) {
        self.catalogURL = catalogURL
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.onInterruption?() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.onInterruption?() }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func play(_ phase: SessionPhase, offset: Double) async throws {
        try Task.checkCancellation()
        playbackGeneration += 1
        let generation = playbackGeneration
        let url: URL?
        if let catalogAudio = phase.catalogAudio {
            url = catalogURL(catalogAudio.id)
        } else if let kind = phase.audio {
            url = Bundle.main.url(forResource: kind.rawValue, withExtension: "wav")
        } else {
            return
        }
        guard let url else {
            throw CocoaError(.fileNoSuchFile)
        }
        // Serialize activation and deactivation so an old stop cannot silence
        // the next phase or a rapidly resumed recording.
        try await AudioSessionSupport.activate(mode: phase.catalogAudio == nil ? .default : .spokenAudio)
        try Task.checkCancellation()
        guard generation == playbackGeneration else { throw CancellationError() }
        player = try AVAudioPlayer(contentsOf: url)
        player?.currentTime = offset; player?.prepareToPlay()
        guard player?.play() == true else { throw CocoaError(.fileReadUnknown) }
    }
    func stop() {
        playbackGeneration += 1
        player?.stop(); player = nil
        AudioSessionSupport.deactivate()
    }
}
