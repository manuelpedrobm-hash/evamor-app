@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import UIKit
import Vision
import MeditationCore

struct TimelapseResult {
    let url: URL
    let motion: MotionSummary
}

enum TimelapseError: LocalizedError {
    case cameraUnavailable
    case cannotConfigure
    case cannotCreateFile
    case noFrames

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "No se encontró la cámara elegida en este iPhone."
        case .cannotConfigure: return "No se pudo preparar la cámara."
        case .cannotCreateFile: return "No se pudo crear el timelapse."
        case .noFrames: return "El timelapse no contiene fotogramas."
        }
    }
}

enum TimelapseStorage {
    static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("Timelapses", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func outputURL(sessionID: String) throws -> URL {
        try directory().appendingPathComponent("evamor-\(sessionID).mp4")
    }

    static func existingURL(filename: String) -> URL? {
        guard let directory = try? directory() else { return nil }
        let url = directory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func remove(filename: String) {
        guard let directory = try? directory() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }
}

@MainActor final class TimelapseRecorder {
    let captureSession = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "evamor.timelapse.capture", qos: .userInitiated)
    private let frameSink = TimelapseFrameSink()
    private var currentInput: AVCaptureDeviceInput?
    private var outputConfigured = false
    private var configuredSelection: (position: TimelapseCameraPosition, lens: TimelapseLens)?
    private var runtimeErrorObserver: NSObjectProtocol?

    init() {
        // AVCaptureSession failures (unsupported format for the chosen camera,
        // hardware taken by another client, etc.) are otherwise silent: the
        // session simply never delivers frames and the recording ends with a
        // generic "no frames" error with no way to tell why.
        let sink = frameSink
        let queue = captureQueue
        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: captureSession, queue: nil
        ) { notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
            queue.async { sink.recordFailure(error ?? TimelapseError.cannotConfigure) }
        }
    }

    deinit {
        if let runtimeErrorObserver { NotificationCenter.default.removeObserver(runtimeErrorObserver) }
    }

    static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { continuation.resume(returning: $0) }
            }
        default: return false
        }
    }

    /// Back camera lenses actually present on this device, for building a lens picker.
    static func availableBackLenses() -> [TimelapseLens] {
        let types: [(TimelapseLens, AVCaptureDevice.DeviceType)] = [
            (.ultraWide, .builtInUltraWideCamera), (.wide, .builtInWideAngleCamera), (.telephoto, .builtInTelephotoCamera)
        ]
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: types.map(\.1), mediaType: .video, position: .back
        ).devices
        return types.filter { pair in discovered.contains { $0.deviceType == pair.1 } }.map(\.0)
    }

    private static func device(position: TimelapseCameraPosition, lens: TimelapseLens) -> AVCaptureDevice? {
        guard position == .back else {
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        let deviceType: AVCaptureDevice.DeviceType = {
            switch lens {
            case .ultraWide: return .builtInUltraWideCamera
            case .wide: return .builtInWideAngleCamera
            case .telephoto: return .builtInTelephotoCamera
            }
        }()
        return AVCaptureDevice.default(deviceType, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    func preparePreview(position: TimelapseCameraPosition = .front, lens: TimelapseLens = .wide) throws {
        if configuredSelection?.position != position || configuredSelection?.lens != lens {
            guard let camera = Self.device(position: position, lens: lens),
                  let input = try? AVCaptureDeviceInput(device: camera) else { throw TimelapseError.cameraUnavailable }
            captureSession.beginConfiguration()
            defer { captureSession.commitConfiguration() }
            if let currentInput { captureSession.removeInput(currentInput) }
            guard captureSession.canAddInput(input) else { throw TimelapseError.cameraUnavailable }
            captureSession.addInput(input)
            currentInput = input

            if !outputConfigured {
                captureSession.sessionPreset = .hd1280x720
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                guard captureSession.canAddOutput(output) else { throw TimelapseError.cannotConfigure }
                captureSession.addOutput(output)
                output.setSampleBufferDelegate(frameSink, queue: captureQueue)
                outputConfigured = true
            }
            if let connection = captureSession.connections.first(where: { $0.output is AVCaptureVideoDataOutput }) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = position == .front
                }
            }
            configuredSelection = (position, lens)
        }
        startCapture()
    }

    func beginRecording(sessionID: String, sourceSeconds: Double, outputSeconds: Int = 30, analyzeMovement: Bool = true) throws {
        let url = try TimelapseStorage.outputURL(sessionID: sessionID)
        try? FileManager.default.removeItem(at: url)
        try captureQueue.sync {
            try frameSink.begin(
                url: url,
                plan: TimelapsePlan(sourceSeconds: sourceSeconds, outputSeconds: outputSeconds),
                analyzeMovement: analyzeMovement
            )
        }
        startCapture()
    }

    func pauseCapture() {
        captureQueue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    func resumeCapture() { startCapture() }

    func cancel() {
        captureQueue.async { [captureSession, frameSink] in
            if captureSession.isRunning { captureSession.stopRunning() }
            frameSink.cancel()
        }
    }

    func finish() async throws -> TimelapseResult {
        try await withCheckedThrowingContinuation { continuation in
            captureQueue.async { [captureSession, frameSink] in
                if captureSession.isRunning { captureSession.stopRunning() }
                frameSink.finish { continuation.resume(with: $0) }
            }
        }
    }

    private func startCapture() {
        captureQueue.async { [captureSession] in
            if !captureSession.isRunning { captureSession.startRunning() }
        }
    }
}

private final class TimelapseFrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    private var plan: TimelapsePlan?
    // Wall-clock time of the last kept frame. AVCaptureSession resets its own
    // presentation-timestamp clock whenever it is stopped and restarted (as
    // pauseCapture/resumeCapture do), so that clock cannot be used to decide
    // whether enough time has passed since the last frame.
    private var lastKeptWallClock: CFTimeInterval?
    private var frameCount: Int64 = 0
    private var acceptingFrames = false
    private var failure: Error?
    private var previousJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    private var poseSampleCount = 0
    private var movementComparisonCount = 0
    private var totalJointDisplacement = 0.0
    private var analyzesMovement = true

    func begin(url: URL, plan: TimelapsePlan, analyzeMovement: Bool) throws {
        guard writer == nil else { throw TimelapseError.cannotCreateFile }
        outputURL = url
        self.plan = plan
        lastKeptWallClock = nil
        frameCount = 0
        failure = nil
        previousJoints = [:]
        poseSampleCount = 0
        movementComparisonCount = 0
        totalJointDisplacement = 0
        analyzesMovement = analyzeMovement
        acceptingFrames = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard acceptingFrames, failure == nil, let plan,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CACurrentMediaTime()
        if let lastKeptWallClock, now - lastKeptWallClock < plan.captureInterval { return }
        self.lastKeptWallClock = now

        do {
            if analyzesMovement { analyzeMovement(in: pixelBuffer) }
            if writer == nil { try makeWriter(for: pixelBuffer) }
            guard let writer, let input, let adaptor else { throw TimelapseError.cannotCreateFile }
            if writer.status == .unknown {
                guard writer.startWriting() else { throw writer.error ?? TimelapseError.cannotCreateFile }
                writer.startSession(atSourceTime: .zero)
            }
            guard writer.status == .writing else { throw writer.error ?? TimelapseError.cannotCreateFile }
            guard input.isReadyForMoreMediaData else { return }
            let presentationTime = CMTime(value: frameCount, timescale: CMTimeScale(TimelapsePlan.framesPerSecond))
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? TimelapseError.cannotCreateFile
            }
            frameCount += 1
        } catch {
            failure = error
            acceptingFrames = false
        }
    }

    func finish(completion: @escaping (Result<TimelapseResult, Error>) -> Void) {
        acceptingFrames = false
        if let failure { cleanState(removeFile: true); completion(.failure(failure)); return }
        guard frameCount > 0, let writer, let input, let url = outputURL else {
            cleanState(removeFile: true); completion(.failure(TimelapseError.noFrames)); return
        }
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { completion(.failure(TimelapseError.cannotCreateFile)); return }
            if self.writer?.status == .completed {
                let motion = MotionSummary(
                    sampleCount: self.poseSampleCount,
                    averageJointDisplacement: self.movementComparisonCount == 0 ? 0 : self.totalJointDisplacement / Double(self.movementComparisonCount)
                )
                self.cleanState(removeFile: false)
                completion(.success(TimelapseResult(url: url, motion: motion)))
            } else {
                let error = self.writer?.error ?? TimelapseError.cannotCreateFile
                self.cleanState(removeFile: true)
                completion(.failure(error))
            }
        }
    }

    func cancel() {
        acceptingFrames = false
        writer?.cancelWriting()
        cleanState(removeFile: true)
    }

    /// Called from the `AVCaptureSessionRuntimeError` observer when the capture
    /// hardware itself fails; without this, that failure was invisible and every
    /// recording that hit it silently ended with the generic "no frames" error.
    func recordFailure(_ error: Error) {
        guard acceptingFrames, failure == nil else { return }
        failure = error
        acceptingFrames = false
    }

    private func makeWriter(for pixelBuffer: CVPixelBuffer) throws {
        guard let outputURL else { throw TimelapseError.cannotCreateFile }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw TimelapseError.cannotCreateFile }
        writer.add(input)
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        self.writer = writer
        self.input = input
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
    }

    private func analyzeMovement(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let points = try? observation.recognizedPoints(.all) else { return }
        let current = points.reduce(into: [VNHumanBodyPoseObservation.JointName: CGPoint]()) { result, entry in
            if entry.value.confidence >= 0.3 { result[entry.key] = entry.value.location }
        }
        guard current.count >= 4 else { return }
        poseSampleCount += 1
        let shared = current.keys.filter { previousJoints[$0] != nil }
        if shared.count >= 4 {
            let displacement = shared.reduce(0.0) { partial, joint in
                guard let previous = previousJoints[joint], let point = current[joint] else { return partial }
                return partial + hypot(point.x - previous.x, point.y - previous.y)
            } / Double(shared.count)
            totalJointDisplacement += displacement
            movementComparisonCount += 1
        }
        previousJoints = current
    }

    private func cleanState(removeFile: Bool) {
        if removeFile, let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        writer = nil; input = nil; adaptor = nil; outputURL = nil; plan = nil
        lastKeptWallClock = nil; frameCount = 0; failure = nil; acceptingFrames = false
        previousJoints = [:]; poseSampleCount = 0; movementComparisonCount = 0; totalJointDisplacement = 0; analyzesMovement = true
    }
}

final class TimelapsePreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
