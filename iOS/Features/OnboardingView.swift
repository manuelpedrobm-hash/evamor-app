import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let pageCount = 3

    var body: some View {
        ZStack {
            Palette.stone.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if page < pageCount - 1 {
                        Button("Omitir") { finish() }
                            .foregroundStyle(Palette.green)
                            .accessibilityHint("Cierra la bienvenida sin cambiar ninguna preferencia")
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 24)

                TabView(selection: $page) {
                    OnboardingPage(
                        image: "CompletionArtwork",
                        title: "Tu práctica, primero",
                        message: "Tras verificar el acceso de antiguo alumno, el temporizador y el historial funcionan sin conexión. Abre Ecuanimidad, pulsa Meditar y deja el teléfono.",
                        points: [
                            ("timer", "De 5 minutos a 8 horas"),
                            ("waveform", "Audio y Metta siempre opcionales"),
                            ("lock.shield", "Tus sesiones se guardan primero en el iPhone")
                        ]
                    )
                    .tag(0)

                    OnboardingPage(
                        systemImage: "hand.raised.fill",
                        title: "Privacidad clara",
                        message: "Ecuanimidad no contiene publicidad, seguimiento ni analítica de terceros. Tú decides cuándo usar iCloud y las notificaciones.",
                        points: [
                            ("video", "El historial permanece local"),
                            ("icloud", "iCloud solo para sincronización y amigos"),
                            ("bell.slash", "Avisos y envío social desactivados inicialmente")
                        ]
                    )
                    .tag(1)

                    OnboardingPage(
                        systemImage: "person.2.fill",
                        title: "Amigos, si quieres",
                        message: "Las invitaciones son privadas. El aviso indica que un amigo ha meditado y te envía metta; no muestra nombres, duración ni historial.",
                        points: [
                            ("person.crop.circle.badge.checkmark", "Aceptación mediante una invitación de iCloud"),
                            ("speaker.slash", "Puedes silenciar a cada persona"),
                            ("slider.horizontal.3", "Puedes detener el envío o todos los avisos")
                        ]
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: page)

                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Palette.green : Palette.limestone)
                            .frame(width: index == page ? 24 : 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Página \(page + 1) de \(pageCount)")
                .padding(.bottom, 20)

                Button(page == pageCount - 1 ? "Empezar" : "Siguiente") {
                    if page == pageCount - 1 { finish() }
                    else { withAnimation { page += 1 } }
                }
                .buttonStyle(PrimaryMeditationButtonStyle())
                .accessibilityIdentifier(page == pageCount - 1 ? "onboardingStart" : "onboardingNext")
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        hasCompletedOnboarding = true
    }
}

private struct OnboardingPage: View {
    var image: String?
    var systemImage: String?
    let title: String
    let message: String
    let points: [(String, String)]

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Group {
                    if let image {
                        Image(image).resizable().scaledToFill()
                    } else {
                        Image(systemName: systemImage ?? "circle")
                            .resizable().scaledToFit().padding(30)
                            .foregroundStyle(Palette.green)
                    }
                }
                .frame(width: 132, height: 132)
                .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 17) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Label(point.1, systemImage: point.0)
                            .font(.body)
                            .foregroundStyle(Palette.green)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
    }
}
