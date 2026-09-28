@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import MeditationCore
import UIKit

struct TimelapseResult {
    let url: URL
    let frameCount: Int
    let duration: Double
}

enum TimelapseError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case cameraNotReady
    case cameraInterrupted
    case cannotCreateVideo
    case noFrames

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Activa el acceso a la cámara en Ajustes para crear el timelapse."
        case .cameraUnavailable:
            return "No se encontró la cámara elegida en este iPhone."
        case .cameraNotReady:
            return "La cámara no ha podido entregar el primer fotograma. Comprueba que ninguna otra app la esté usando e inténtalo de nuevo."
        case .cameraInterrupted:
            return "La cámara dejó de estar disponible durante la sesión."
        case .cannotCreateVideo:
            return "No se pudo crear el archivo de vídeo."
        case .noFrames:
            return "No se recibió ningún fotograma de la cámara."
        }
    }
}

enum TimelapseStorage {
    static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Timelapses", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func outputURL(sessionID: String) throws -> URL {
        try directory().appendingPathComponent("ecuanimidad-\(sessionID).mp4")
    }

    static func existingURL(filename: String) -> URL? {
        guard (filename as NSString).lastPathComponent == filename,
              let directory = try? directory() else { return nil }
        let url = directory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func remove(filename: String) {
        guard (filename as NSString).lastPathComponent == filename,
              let directory = try? directory() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }
}

@MainActor final class TimelapseRecorder {
    let captureSession: AVCaptureSession
    private let controller: TimelapseCaptureController

    init() {
        let session = AVCaptureSession()
        captureSession = session
        controller = TimelapseCaptureController(session: session)
    }

    static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { continuation.resume(returning: $0) }
            }
        default:
            return false
        }
    }

    func prepare(camera: TimelapseCamera) async throws {
        try await controller.prepare(camera: camera)
    }

    /// Returns only after a frame has been appended to the new video. The
    /// meditation must not start before this succeeds.
    func startRecording(sessionID: String, sourceSeconds: Double, outputSeconds: Int) async throws {
        let url = try TimelapseStorage.outputURL(sessionID: sessionID)
        try await controller.startRecording(
            url: url,
            plan: TimelapsePlan(sourceSeconds: sourceSeconds, outputSeconds: outputSeconds)
        )
    }

    func pause() { controller.pause() }
    func resume() { controller.resume() }
    func cancel() { controller.cancel() }

    func finish() async throws -> TimelapseResult {
        try await controller.finish()
    }
}

private final class TimelapseCaptureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session: AVCaptureSession
    private let queue = DispatchQueue(label: "ecuanimidad.timelapse.capture", qos: .userInitiated)
    private var input: AVCaptureDeviceInput?
    private var output: AVCaptureVideoDataOutput?
    private var writer: TimelapseVideoWriter?
    private var plan: TimelapsePlan?
    private var lastKeptUptime: TimeInterval?
    private var acceptingFrames = false
    private var pendingStart: CheckedContinuation<Void, Error>?
    private var startToken: UUID?
    private var recordingFailure: Error?
    private var runtimeErrorObserver: NSObjectProtocol?

    init(session: AVCaptureSession) {
        self.session = session
        super.init()
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error ?? TimelapseError.cameraInterrupted
            self?.queue.async { self?.recordRuntimeFailure(error) }
        }
    }

    deinit {
        if let runtimeErrorObserver { NotificationCenter.default.removeObserver(runtimeErrorObserver) }
    }

    func prepare(camera: TimelapseCamera) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try configure(camera: camera)
                    if !session.isRunning { session.startRunning() }
                    guard session.isRunning else { throw TimelapseError.cameraNotReady }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func startRecording(url: URL, plan: TimelapsePlan) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard output != nil, session.isRunning, writer == nil, pendingStart == nil else {
                    continuation.resume(throwing: TimelapseError.cameraNotReady)
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: url)
                    writer = try TimelapseVideoWriter(url: url, framesPerSecond: TimelapsePlan.framesPerSecond)
                    self.plan = plan
                    lastKeptUptime = nil
                    recordingFailure = nil
                    acceptingFrames = true
                    pendingStart = continuation
                    let token = UUID()
                    startToken = token
                    queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                        guard let self, self.startToken == token, let pending = self.pendingStart else { return }
                        self.pendingStart = nil
                        self.startToken = nil
                        self.acceptingFrames = false
                        self.writer?.cancel(removeFile: true)
                        self.writer = nil
                        self.plan = nil
                        pending.resume(throwing: TimelapseError.cameraNotReady)
                    }
                } catch {
                    writer = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func pause() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func resume() {
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    func cancel() {
        queue.async { [self] in
            acceptingFrames = false
            let pending = pendingStart
            pendingStart = nil
            startToken = nil
            if session.isRunning { session.stopRunning() }
            writer?.cancel(removeFile: true)
            resetRecordingState()
            pending?.resume(throwing: CancellationError())
        }
    }

    func finish() async throws -> TimelapseResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                acceptingFrames = false
                if session.isRunning { session.stopRunning() }
                if let recordingFailure {
                    writer?.cancel(removeFile: true)
                    resetRecordingState()
                    continuation.resume(throwing: recordingFailure)
                    return
                }
                guard pendingStart == nil, let writer, writer.frameCount > 0 else {
                    self.writer?.cancel(removeFile: true)
                    resetRecordingState()
                    continuation.resume(throwing: TimelapseError.noFrames)
                    return
                }
                writer.finish { [weak self] result in
                    guard let self else {
                        continuation.resume(throwing: TimelapseError.cannotCreateVideo)
                        return
                    }
                    self.queue.async {
                        self.resetRecordingState()
                        continuation.resume(with: result)
                    }
                }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard acceptingFrames, recordingFailure == nil, let writer, let plan,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastKeptUptime, now - lastKeptUptime < plan.captureInterval { return }

        do {
            guard try writer.append(pixelBuffer) else { return }
            lastKeptUptime = now
            if let pendingStart {
                self.pendingStart = nil
                startToken = nil
                pendingStart.resume()
            }
        } catch {
            recordRuntimeFailure(error)
        }
    }

    private func configure(camera: TimelapseCamera) throws {
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        if let input { session.removeInput(input) }

        let position: AVCaptureDevice.Position = camera == .front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw TimelapseError.cameraUnavailable
        }
        let newInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(newInput) else { throw TimelapseError.cameraUnavailable }
        session.addInput(newInput)
        input = newInput

        let videoOutput: AVCaptureVideoDataOutput
        if let output {
            videoOutput = output
        } else {
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            guard session.canAddOutput(videoOutput) else { throw TimelapseError.cameraNotReady }
            session.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            output = videoOutput
        }

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = camera == .front
            }
        }
    }

    private func recordRuntimeFailure(_ error: Error) {
        guard acceptingFrames || pendingStart != nil else { return }
        acceptingFrames = false
        recordingFailure = error
        if let pendingStart {
            self.pendingStart = nil
            startToken = nil
            writer?.cancel(removeFile: true)
            writer = nil
            plan = nil
            pendingStart.resume(throwing: error)
        }
    }

    private func resetRecordingState() {
        writer = nil
        plan = nil
        lastKeptUptime = nil
        acceptingFrames = false
        pendingStart = nil
        startToken = nil
        recordingFailure = nil
    }
}

final class TimelapseVideoWriter: @unchecked Sendable {
    let url: URL
    let framesPerSecond: Int
    private var assetWriter: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private(set) var frameCount = 0

    init(url: URL, framesPerSecond: Int) throws {
        guard framesPerSecond > 0 else { throw TimelapseError.cannotCreateVideo }
        self.url = url
        self.framesPerSecond = framesPerSecond
    }

    /// Returns false only when AVAssetWriter is applying back pressure. The
    /// caller should try the next camera frame without advancing its sampler.
    func append(_ pixelBuffer: CVPixelBuffer) throws -> Bool {
        if assetWriter == nil { try configure(for: pixelBuffer) }
        guard let assetWriter, let input, let adaptor else { throw TimelapseError.cannotCreateVideo }
        guard assetWriter.status == .writing else { throw assetWriter.error ?? TimelapseError.cannotCreateVideo }
        guard input.isReadyForMoreMediaData else { return false }
        let time = CMTime(value: Int64(frameCount), timescale: CMTimeScale(framesPerSecond))
        guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
            throw assetWriter.error ?? TimelapseError.cannotCreateVideo
        }
        frameCount += 1
        return true
    }

    func finish(completion: @escaping (Result<TimelapseResult, Error>) -> Void) {
        guard frameCount > 0, let assetWriter, let input else {
            cancel(removeFile: true)
            completion(.failure(TimelapseError.noFrames))
            return
        }
        let count = frameCount
        let duration = Double(count) / Double(framesPerSecond)
        input.markAsFinished()
        assetWriter.endSession(atSourceTime: CMTime(value: Int64(count), timescale: CMTimeScale(framesPerSecond)))
        assetWriter.finishWriting { [weak self, url] in
            guard let self, let completedWriter = self.assetWriter else {
                completion(.failure(TimelapseError.cannotCreateVideo))
                return
            }
            if completedWriter.status == .completed {
                completion(.success(TimelapseResult(url: url, frameCount: count, duration: duration)))
            } else {
                try? FileManager.default.removeItem(at: url)
                completion(.failure(completedWriter.error ?? TimelapseError.cannotCreateVideo))
            }
        }
    }

    func cancel(removeFile: Bool) {
        assetWriter?.cancelWriting()
        if removeFile { try? FileManager.default.removeItem(at: url) }
    }

    private func configure(for pixelBuffer: CVPixelBuffer) throws {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { throw TimelapseError.cannotCreateVideo }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_600_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw TimelapseError.cannotCreateVideo }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.startWriting() else { throw writer.error ?? TimelapseError.cannotCreateVideo }
        writer.startSession(atSourceTime: .zero)
        assetWriter = writer
        self.input = input
        self.adaptor = adaptor
    }
}

final class TimelapsePreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
