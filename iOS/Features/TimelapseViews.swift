import AVFoundation
import AVKit
import MeditationCore
import Photos
import SwiftUI

private enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case permissionDenied

        var errorDescription: String? {
            "Ecuanimidad no tiene permiso para añadir el vídeo a Fotos. Puedes permitirlo en Ajustes del iPhone."
        }
    }

    static func saveVideo(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.permissionDenied }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { saved, error in
                if let error { continuation.resume(throwing: error) }
                else if saved { continuation.resume() }
                else { continuation.resume(throwing: SaveError.permissionDenied) }
            }
        }
    }
}

struct TimelapseSetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            TimelapseCameraPreview(session: model.timelapse.captureSession)
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Button("Cancelar") { model.cancelTimelapseSetup() }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(.white)
                    Spacer()
                    Label("Sin sonido", systemImage: "mic.slash.fill")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.black.opacity(0.32), in: Capsule())
                }
                Spacer()
                VStack(spacing: 9) {
                    Text("Permanecer")
                        .font(.system(.title, design: .rounded, weight: .medium))
                    Text("Coloca el iPhone en vertical y encuadra tu espacio. El vídeo se acelera y permanece en este dispositivo.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.78))
                    Text("Vídeo final: \(model.configuration.timelapseOutputSeconds) s · La meditación continúa si bloqueas el iPhone")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Button {
                    model.confirmTimelapseStart()
                } label: {
                    Label("Comenzar meditación", systemImage: "record.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.white)
                .foregroundStyle(Palette.green)
            }
            .padding(24)
            .padding(.vertical, 10)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

private struct TimelapseCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> TimelapsePreviewView {
        let view = TimelapsePreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: TimelapsePreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

struct TimelapsePlaybackView: View {
    let url: URL
    let motion: MotionSummary?
    @State private var player: AVPlayer
    @State private var isSaving = false
    @State private var savedToPhotos = false
    @State private var saveError: String?
    private let quote: PaliQuote

    init(url: URL, motion: MotionSummary?) {
        self.url = url
        self.motion = motion
        quote = PaliQuote.forTimelapse(url)
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack(alignment: .bottom) {
                    VideoPlayer(player: player)
                    LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                        .allowsHitTesting(false)
                    VStack(spacing: 5) {
                        Text(quote.pali)
                            .font(.system(.headline, design: .serif, weight: .semibold))
                        Text(quote.translation)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                        Text(quote.source)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .foregroundStyle(.white)
                    .padding(20)
                    .allowsHitTesting(false)
                }
                .frame(minHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.12)) }
                if let motion {
                    MotionSummaryCard(summary: motion, dark: false)
                }
                Button {
                    Task { await saveToPhotos() }
                } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(savedToPhotos ? "Guardado en Fotos" : "Guardar en Fotos", systemImage: savedToPhotos ? "checkmark.circle.fill" : "photo.badge.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(isSaving || savedToPhotos)
                ShareLink(
                    item: url,
                    message: Text("\(quote.pali) — \(quote.translation) (\(quote.source))"),
                    preview: SharePreview("Mi práctica en Ecuanimidad")
                ) {
                    Label("Compartir una copia", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .padding(20)
        }
        .background(Palette.stone)
        .navigationTitle("Timelapse")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { player.play() }
        .onDisappear { player.pause() }
        .alert("No se pudo guardar en Fotos", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("Aceptar") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    @MainActor private func saveToPhotos() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoLibrarySaver.saveVideo(at: url)
            savedToPhotos = true
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#if DEBUG
struct TimelapseTestView: View {
    private enum Phase: Equatable { case preparing, ready, recording, finalizing, result, failed }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: Phase = .preparing
    @State private var remaining = 30
    @State private var resultURL: URL?
    @State private var motion: MotionSummary?
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if phase == .result, let resultURL, let motion {
                    TimelapsePlaybackView(url: resultURL, motion: motion)
                } else {
                    ZStack {
                        TimelapseCameraPreview(session: model.timelapse.captureSession)
                            .ignoresSafeArea()
                        LinearGradient(colors: [.black.opacity(0.5), .clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()
                        VStack(spacing: 18) {
                            HStack {
                                Button("Cerrar") { close() }
                                    .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.white)
                                Spacer()
                                Label("Prueba local", systemImage: "iphone")
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(.black.opacity(0.3), in: Capsule())
                            }
                            Spacer()
                            status
                            action
                        }
                        .padding(24)
                        .foregroundStyle(.white)
                    }
                }
            }
            .toolbar {
                if phase == .result {
                    ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } }
                }
            }
        }
        .preferredColorScheme(phase == .result ? nil : .dark)
        .task { await prepare() }
        .onChange(of: scenePhase) { _, newPhase in
            guard phase == .recording, newPhase != .active else { return }
            model.timelapse.cancel()
            errorMessage = "La prueba se detuvo porque Ecuanimidad dejó de estar visible. Vuelve a intentarlo manteniendo la app abierta durante los 30 segundos."
            phase = .failed
        }
        .onDisappear {
            if phase == .result {
                if let resultURL { TimelapseStorage.remove(filename: resultURL.lastPathComponent) }
                return
            }
            phase = .failed
            model.timelapse.cancel()
        }
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .preparing:
            ProgressView("Preparando cámara…").tint(.white)
        case .ready:
            VStack(spacing: 8) {
                Text("Prueba Permanecer").font(.title2.weight(.medium))
                Text("Graba 30 segundos sin sonido y muestra aquí el vídeo y el Pulso de quietud.")
                    .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
            }
        case .recording:
            VStack(spacing: 7) {
                Text("\(remaining)").font(.system(size: 58, weight: .ultraLight, design: .rounded)).monospacedDigit()
                Text("Permanece dentro del encuadre").font(.subheadline).foregroundStyle(.white.opacity(0.72))
            }
        case .finalizing:
            ProgressView("Creando timelapse…").tint(.white)
        case .failed:
            VStack(spacing: 8) {
                Label("No se pudo completar la prueba", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(errorMessage).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.72))
            }
        case .result:
            EmptyView()
        }
    }

    @ViewBuilder private var action: some View {
        switch phase {
        case .ready:
            Button("Empezar 30 segundos", systemImage: "record.circle") { start() }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(.white).foregroundStyle(Palette.green)
        case .failed:
            Button("Cerrar") { close() }.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.white)
        default:
            EmptyView()
        }
    }

    @MainActor private func prepare() async {
        guard await TimelapseRecorder.requestCameraAccess() else {
            errorMessage = "Activa Cámara para Ecuanimidad en Ajustes. Esta prueba no utiliza iCloud."
            phase = .failed
            return
        }
        do {
            try model.timelapse.preparePreview(position: model.configuration.timelapseCameraPosition, lens: model.configuration.timelapseLens)
            phase = .ready
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    private func start() {
        do {
            try model.timelapse.beginRecording(sessionID: "test-\(UUID().uuidString.lowercased())", sourceSeconds: 30)
            remaining = 30
            phase = .recording
            Task { @MainActor in
                for value in stride(from: 29, through: 0, by: -1) {
                    try? await Task.sleep(for: .seconds(1))
                    guard phase == .recording else { return }
                    remaining = value
                }
                await finish()
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    @MainActor private func finish() async {
        phase = .finalizing
        do {
            let result = try await model.timelapse.finish()
            resultURL = result.url
            motion = result.motion
            phase = .result
        } catch {
            errorMessage = error.localizedDescription
            phase = .failed
        }
    }

    private func close() {
        phase = .failed
        model.timelapse.cancel()
        dismiss()
    }
}
#endif
