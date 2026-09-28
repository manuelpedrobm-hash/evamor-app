import AVFoundation
import MeditationCore

@MainActor protocol MeditationAudioPlayer {
    var isPlaying: Bool { get }
    func play(_ phase: SessionPhase, offset: Double) async throws
    func playTimeline(_ phases: [SessionPhase], offset: Double) async throws
    func stop()
}

@MainActor final class AudioService: NSObject, MeditationAudioPlayer, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var timelinePlayer: AVPlayer?
    private var timelineEndObserver: NSObjectProtocol?
    private var playbackGeneration = 0
    var isPlaying: Bool { player?.isPlaying == true || (timelinePlayer?.rate ?? 0) > 0 }
    var onInterruption: (() -> Void)?
    var onPlaybackFinished: ((Bool) -> Void)?
    private let catalogURL: (String) -> URL?
    private var observers: [NSObjectProtocol] = []
    init(catalogURL: @escaping (String) -> URL? = { _ in nil }) {
        self.catalogURL = catalogURL
        super.init()
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
        player?.delegate = self
        player?.currentTime = offset; player?.prepareToPlay()
        guard player?.play() == true else { throw CocoaError(.fileReadUnknown) }
    }
    func playTimeline(_ phases: [SessionPhase], offset: Double) async throws {
        try Task.checkCancellation()
        playbackGeneration += 1
        let generation = playbackGeneration
        let composition = try await Self.makeTimeline(phases)
        try await AudioSessionSupport.activate(mode: .default)
        try Task.checkCancellation()
        guard generation == playbackGeneration else { throw CancellationError() }
        let item = AVPlayerItem(asset: composition)
        let timelinePlayer = AVPlayer(playerItem: item)
        timelineEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.onPlaybackFinished?(true)
            }
        }
        self.timelinePlayer = timelinePlayer
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            timelinePlayer.seek(to: CMTime(seconds: offset, preferredTimescale: 44_100), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
        try Task.checkCancellation()
        guard generation == playbackGeneration else { throw CancellationError() }
        timelinePlayer.play()
    }
    static func makeTimeline(_ phases: [SessionPhase]) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard let timeline = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let silenceURL = Bundle.main.url(forResource: "meditation-silence", withExtension: "wav") else {
            throw CocoaError(.fileNoSuchFile)
        }
        var cursor = CMTime.zero
        for phase in phases {
            let url: URL
            if let kind = phase.audio {
                guard let soundURL = Bundle.main.url(forResource: kind.rawValue, withExtension: "wav") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                url = soundURL
            } else {
                url = silenceURL
            }
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try Task.checkCancellation()
            var left = phase.seconds
            while left > 0.0001 {
                let segment = min(left, phase.audio == nil ? 60 : phase.seconds)
                let duration = CMTime(seconds: segment, preferredTimescale: 44_100)
                try timeline.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: cursor)
                cursor = CMTimeAdd(cursor, duration)
                left -= segment
            }
        }
        return composition
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedPlayer = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player,
                  ObjectIdentifier(current) == finishedPlayer else { return }
            self.onPlaybackFinished?(flag)
        }
    }
    func stop() {
        playbackGeneration += 1
        player?.stop(); player = nil
        timelinePlayer?.pause(); timelinePlayer = nil
        if let timelineEndObserver { NotificationCenter.default.removeObserver(timelineEndObserver) }
        timelineEndObserver = nil
        AudioSessionSupport.deactivate()
    }
}
