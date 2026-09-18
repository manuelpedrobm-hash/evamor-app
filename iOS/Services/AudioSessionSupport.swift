import AVFoundation

enum AudioSessionSupport {
    private static let queue = DispatchQueue(label: "evamor.audio.session")

    static func activate(mode: AVAudioSession.Mode) async throws {
        let session = AVAudioSession.sharedInstance()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try session.setCategory(.playback, mode: mode)
                    if #available(iOS 27.0, *) {
                        var result: Result<Void, Error> = .success(())
                        let finished = DispatchSemaphore(value: 0)
                        session.activate(options: []) { activated, error in
                            if let error {
                                result = .failure(error)
                            } else if !activated {
                                result = .failure(CocoaError(.featureUnsupported))
                            }
                            finished.signal()
                        }
                        finished.wait()
                        try result.get()
                    } else {
                        try session.setActive(true)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func deactivate() {
        let session = AVAudioSession.sharedInstance()
        queue.async {
            if #available(iOS 27.0, *) {
                let finished = DispatchSemaphore(value: 0)
                session.deactivate(options: [.notifyOthersOnDeactivation]) { _, _ in
                    finished.signal()
                }
                finished.wait()
            } else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
}
