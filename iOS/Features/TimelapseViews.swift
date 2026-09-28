import AVFoundation
import AVKit
import SwiftUI

struct TimelapseSetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            TimelapseCameraPreview(session: model.timelapse.captureSession)
                .ignoresSafeArea()
            LinearGradient(
                colors: [.black.opacity(0.58), .clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Button("Cancelar") { model.cancelTimelapseSetup() }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(.white)
                        .disabled(model.isStartingTimelapse)
                    Spacer()
                    Label("Sin sonido", systemImage: "mic.slash.fill")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.34), in: Capsule())
                }
                Spacer()
                VStack(spacing: 8) {
                    Text("Timelapse")
                        .font(.system(.title, design: .rounded, weight: .medium))
                    Text("Comprueba el encuadre. Al comenzar, esperaremos a escribir el primer fotograma antes de iniciar el temporizador.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Vídeo final de hasta \(model.configuration.timelapse.outputSeconds) s · Solo en este iPhone")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Button {
                    Task { await model.confirmTimelapseStart() }
                } label: {
                    Group {
                        if model.isStartingTimelapse {
                            HStack {
                                ProgressView().tint(Palette.green)
                                Text("Comprobando primer fotograma…")
                            }
                        } else {
                            Label("Comenzar meditación", systemImage: "record.circle")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.white)
                .foregroundStyle(Palette.green)
                .disabled(model.isStartingTimelapse)
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
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VStack(spacing: 20) {
            VideoPlayer(player: player)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.28))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            ShareLink(item: url, preview: SharePreview("Mi práctica en Ecuanimidad")) {
                Label("Compartir una copia", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 20)
            Text("El vídeo no contiene sonido y permanece en este iPhone hasta que lo compartas o borres.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .background(Palette.stone)
        .navigationTitle("Timelapse")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }
}
