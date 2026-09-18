import SwiftUI
import CloudKit
import UIKit
import MeditationCore

enum Palette {
    static let green = Color(red: 0.12, green: 0.29, blue: 0.24)
    static let sage = Color(red: 0.55, green: 0.65, blue: 0.53)
    static let stone = Color(red: 0.95, green: 0.93, blue: 0.87)
    static let limestone = Color(red: 0.86, green: 0.83, blue: 0.72)
    static let gold = Color(red: 0.79, green: 0.58, blue: 0.22)
    static let night = Color(red: 0.035, green: 0.10, blue: 0.08)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    var body: some View {
        @Bindable var model = model
        ZStack {
            TabView(selection: $model.tab) {
                NavigationStack { MeditateView() }.tabItem { Label("Meditar", systemImage: "circle") }.tag(0)
                NavigationStack { HistoryView() }.tabItem { Label("Historial", systemImage: "calendar") }.tag(1)
                NavigationStack { FriendsView() }.tabItem { Label("Amigos", systemImage: "person.2") }.tag(2)
                NavigationStack { SettingsView() }.tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }.tag(3)
            }
            .toolbarBackground(Palette.stone.opacity(0.96), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            if model.showCompletionCelebration {
                CompletionCelebrationView(
                    title: model.completionTitle,
                    subtitle: model.completionSubtitle
                ) { model.showCompletionCelebration = false }
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
            }
            if !hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: model.showCompletionCelebration)
        .tint(Palette.green)
        .fullScreenCover(isPresented: Binding(get: { model.engine.progress != nil }, set: { _ in })) {
            ActiveSessionView().interactiveDismissDisabled()
        }
        .alert("No se pudo completar la acción", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Aceptar") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

struct CompletionCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var contentVisible = false
    let title: String
    let subtitle: String
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Image("ClosingPhoto")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)
            LinearGradient(
                colors: [Palette.green.opacity(0.58), Palette.night.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image("CompletionArtwork")
                    .resizable().scaledToFill()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.18)) }
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    .scaleEffect(contentVisible ? (reduceMotion ? 1 : (breathing ? 1.04 : 0.98)) : 0.82)
                    .opacity(contentVisible ? 1 : 0)
                Text(title)
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(0.6)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 12)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .opacity(contentVisible ? 1 : 0)
                Button("Continuar") { dismiss() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.white)
                    .opacity(contentVisible ? 0.78 : 0)
            }
            .padding(32)
            .padding(.bottom, 28)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
        .task {
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.9)) { contentVisible = true }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathing = true }
            }
#if DEBUG
            guard !ProcessInfo.processInfo.arguments.contains("-showCompletionPreview") else { return }
#endif
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

struct MeditateView: View {
    @Environment(AppModel.self) private var model
    @State private var configuring: Bool
    @State private var showingDedication: Bool
    @State private var showingCatalog = false

    init() {
#if DEBUG
        _configuring = State(initialValue: ProcessInfo.processInfo.arguments.contains("-showConfigurationPreview"))
        _showingDedication = State(initialValue: ProcessInfo.processInfo.arguments.contains("-showDedicationPreview"))
#else
        _configuring = State(initialValue: false)
        _showingDedication = State(initialValue: false)
#endif
    }

    var body: some View {
        ZStack {
            Palette.stone.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Image("CompletionArtwork")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(.white.opacity(0.38)) }
                        .overlay {
                            Color.clear
                                .frame(width: 52, height: 52)
                                .contentShape(Circle())
                                .onLongPressGesture(minimumDuration: 3) {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    showingDedication = true
                                }
                        }
                        .shadow(color: Palette.green.opacity(0.18), radius: 22, y: 12)
                        .accessibilityHidden(true)

                    VStack(spacing: 6) {
                        Text("Un momento de quietud")
                            .font(.system(.title2, design: .rounded, weight: .medium))
                            .multilineTextAlignment(.center)
                        Text("Acomódate. Cuando estés listo, comienza.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        Text(durationLabel(model.configuration.minutes))
                            .accessibilityIdentifier("selectedDuration")
                            .font(.system(size: 42, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Palette.green)
                        if model.configuration.audio.contains(.metta) {
                            Text("+ 1 min 13 s de metta al final")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Divider().overlay(Palette.limestone.opacity(0.5))
                        Label(audioSummary, systemImage: model.configuration.audio.isEmpty ? "speaker.slash" : "waveform")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.6)) }

                    VStack(spacing: 14) {
                        Button {
                            Task { await model.beginMeditation() }
                        } label: {
                            Text("Meditar")
                                .font(.title3.weight(.semibold))
                        }
                            .buttonStyle(PrimaryMeditationButtonStyle())
                            .accessibilityIdentifier("meditateButton")
                            .accessibilityHint("Inicia la sesión con la configuración guardada")
                        Button("Configurar sesión", systemImage: "slider.horizontal.3") { configuring = true }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .accessibilityIdentifier("configureSessionButton")
                    }
                    if model.completionMessage {
                        Label("Práctica guardada", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.green)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Duración rápida")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 9) {
                            ForEach([5, 15, 30, 60], id: \.self) { minutes in
                                Button {
                                    model.setQuickDuration(minutes)
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    Text(minutes == 60 ? "1 h" : "\(minutes) min")
                                        .font(.subheadline.weight(model.configuration.minutes == minutes ? .semibold : .regular))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(model.configuration.minutes == minutes ? Palette.green : .white.opacity(0.5))
                                        .foregroundStyle(model.configuration.minutes == minutes ? .white : Palette.green)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .accessibilityIdentifier("quickDuration\(minutes)")
                                .accessibilityLabel("Meditar \(durationLabel(minutes))")
                                .accessibilityValue(model.configuration.minutes == minutes ? "Seleccionado" : "")
                            }
                        }
                    }

                    ProfileStrip { showingCatalog = true }

                    if model.statistics.continuity.activeDays > 0 {
                        ContinuityCard(continuity: model.statistics.continuity)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 96)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $configuring) { ConfigurationView(configuration: model.configuration) }
        .sheet(isPresented: $showingCatalog) { AudioCatalogView() }
        .sheet(isPresented: $showingDedication) { EvamorDedicationView() }
        .alert("Sesión", isPresented: Binding(get: { model.engine.error != nil }, set: { if !$0 { model.engine.error = nil } })) {
            Button("Aceptar") { model.engine.error = nil }
        } message: { Text(model.engine.error ?? "") }
    }

    private var audioSummary: String {
        if let catalog = model.configuration.catalogAudio {
            let extras = AudioKind.allCases.filter { model.configuration.audio.contains($0) }.map(\.title)
            return ([catalog.title] + extras).joined(separator: " · ")
        }
        return model.configuration.audio.isEmpty
            ? "En silencio"
            : AudioKind.allCases.filter { model.configuration.audio.contains($0) }.map(\.title).joined(separator: " · ")
    }
}

struct PrimaryMeditationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(.white)
            .background(Palette.green, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct EvamorDedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var revealed = false

    private let words = [
        ("E", "Estar"), ("V", "Ver"), ("A", "Aceptar"),
        ("M", "Meditar"), ("O", "Observar"), ("R", "Regresar")
    ]

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .stroke(index.isMultiple(of: 2) ? Palette.gold.opacity(0.18) : Palette.sage.opacity(0.15), lineWidth: 1)
                        .frame(width: CGFloat(170 + index * 76), height: CGFloat(170 + index * 76))
                        .scaleEffect(reduceMotion ? 1 : (breathing ? 1.035 : 0.97))
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: 26) {
                Spacer()
                ZStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 62, weight: .ultraLight))
                        .foregroundStyle(Palette.sage.opacity(0.58))
                        .rotationEffect(.degrees(breathing && !reduceMotion ? 8 : -8))
                    Image(systemName: "heart.fill")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Palette.gold)
                        .scaleEffect(revealed ? (reduceMotion ? 1 : (breathing ? 1.08 : 0.96)) : 0.6)
                }
                VStack(spacing: 9) {
                    Text("Para Eva, con amor.")
                        .font(.system(size: 34, weight: .light, design: .rounded))
                    Text("Que cada pausa te recuerde cuánto mereces sonreír.")
                        .font(.title3.weight(.light))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .multilineTextAlignment(.center)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                        HStack(spacing: 10) {
                            Text(word.0)
                                .font(.headline)
                                .foregroundStyle(Palette.gold)
                                .frame(width: 20)
                            Text(word.1)
                                .font(.subheadline)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .frame(maxWidth: 420)

                Text("EVAMOR")
                    .font(.caption.weight(.semibold))
                    .tracking(5)
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                Button("Cerrar") { dismiss() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.white)
            }
            .padding(28)
            .padding(.vertical, 18)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 10)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task {
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.8)) { revealed = true }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { breathing = true }
            }
        }
        .accessibilityLabel("Para Eva, con amor. Que cada pausa te recuerde cuánto mereces sonreír. Estar, ver, aceptar, meditar, observar, regresar.")
    }
}

private struct ContinuityCard: View {
    let continuity: PracticeContinuity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Hilo de práctica", systemImage: "circle.hexagongrid.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.green)
                Spacer()
                Text("\(continuity.activeDays) \(continuity.activeDays == 1 ? "día" : "días")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(0..<min(continuity.linkedSessions, 9), id: \.self) { index in
                    Circle()
                        .fill(index.isMultiple(of: 2) ? Palette.gold : Palette.sage)
                        .frame(width: 11, height: 11)
                }
                if continuity.linkedSessions > 9 {
                    Text("+\(continuity.linkedSessions - 9)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(continuity.linkedSessions) \(continuity.linkedSessions == 1 ? "sesión enlazada" : "sesiones enlazadas")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(17)
        .background(Palette.limestone.opacity(0.34), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Palette.gold.opacity(0.18)) }
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        if continuity.needsRecoveryToday { return "Tu hilo sigue abierto hoy. Una sesión lo continúa." }
        if continuity.practicedToday && continuity.pauseUsed { return "Has retomado el hilo. La pausa queda integrada." }
        if continuity.practicedToday { return "Tu práctica de hoy ya forma parte del hilo." }
        return "Hoy puedes añadir una nueva sesión al hilo."
    }
}

struct ConfigurationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var configuration: SessionConfiguration
    @State private var showingCatalog = false
    private var selectedTrack: AudioCatalogTrack? {
        configuration.catalogAudio.flatMap { model.catalog.track(id: $0.id) }
    }
    private var isStandalone: Bool { selectedTrack?.standalone == true }

    var body: some View {
        NavigationStack {
            Form {
                if !model.catalog.tracks.isEmpty {
                    Section {
                        Picker("Cántico o Group Sitting", selection: Binding(
                            get: { configuration.catalogAudio?.id },
                            set: { id in
                                guard let id, let track = model.catalog.track(id: id) else {
                                    configuration.catalogAudio = nil
                                    return
                                }
                                configuration.catalogAudio = track.reference
                                if track.standalone == true {
                                    configuration.audio = []
                                    configuration.minutes = max(SessionConfiguration.allowedMinutes.lowerBound, Int(ceil(track.durationSeconds / 60)))
                                }
                            }
                        )) {
                            Text("Ninguno").tag(String?.none)
                            ForEach(model.catalog.tracks) { track in
                                Text(track.title).tag(String?.some(track.id))
                            }
                        }
                    } header: { Text("Extra") } footer: {
                        Text(isStandalone
                            ? "Esta grabación ya es una sesión completa: incluye su propia duración y cierre, sin audios ni ajustes adicionales."
                            : "Se añade como pista adicional al principio de tu sesión. Si aún no está descargada, se descarga al empezar a meditar.")
                    }
                }
                if !isStandalone {
                    Section("Duración de la meditación") {
                        Stepper(durationLabel(configuration.minutes), value: $configuration.minutes, in: SessionConfiguration.allowedMinutes, step: 5)
                        Picker("Elegir duración", selection: $configuration.minutes) {
                            ForEach([5, 10, 15, 20, 30, 45, 60, 75, 90, 120, 180, 240, 360, 480], id: \.self) {
                                Text(durationLabel($0)).tag($0)
                            }
                        }
                    }
                    Section {
                        ForEach(AudioKind.userSelectable, id: \.self) { kind in
                            Toggle(kind.title, isOn: Binding(get: { configuration.audio.contains(kind) }, set: { if $0 { configuration.audio.insert(kind) } else { configuration.audio.remove(kind) } }))
                        }
                    } header: { Text("Audio opcional") } footer: {
                        Text("Introducción: 4 min 19 s. Metta: Bhavatu Sabba Mangalam, 1 min 13 s adicionales al final.")
                    }
                } else {
                    Section {
                        LabeledContent("Duración", value: durationLabel(configuration.minutes))
                    }
                }
                Section {
                    Button("Explorar audios y perfiles", systemImage: "waveform.badge.magnifyingglass") {
                        showingCatalog = true
                    }
                }
                if !configuration.isValid { Text("Selecciona al menos \(configuration.minimumMinutes) minutos para incluir estos audios.").foregroundStyle(.red) }
            }
            .sheet(isPresented: $showingCatalog) { AudioCatalogView() }
            .onChange(of: showingCatalog) { _, visible in
                if !visible { configuration = model.configuration }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.stone)
            .navigationTitle("Tu sesión").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { model.saveConfiguration(configuration); dismiss() }.disabled(!configuration.isValid) }
            }
        }
    }
}

private func durationLabel(_ minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes) minutos" }
    let hours = minutes / 60
    let remainder = minutes % 60
    if remainder == 0 { return hours == 1 ? "1 hora" : "\(hours) horas" }
    return "\(hours) h \(remainder) min"
}

private func practiceDurationLabel(_ seconds: Double) -> String {
    let value = max(0, Int(seconds.rounded(.down)))
    let hours = value / 3600
    let minutes = (value % 3600) / 60
    let remainder = value % 60
    if hours > 0 { return "\(hours) h \(minutes) min \(remainder) s" }
    if minutes > 0 { return "\(minutes) min \(remainder) s" }
    return "\(remainder) s"
}

struct ActiveSessionView: View {
    @Environment(AppModel.self) private var model
    @State private var cancelling = false
    var body: some View {
        ZStack {
            RadialGradient(colors: [Palette.green.opacity(0.82), Palette.night], center: .center, startRadius: 0, endRadius: 460)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    Circle().stroke(Palette.sage.opacity(0.14), lineWidth: 1).frame(width: 286, height: 286)
                    Circle()
                        .trim(from: 0, to: sessionFraction)
                        .stroke(Palette.limestone, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 286, height: 286)
                        .animation(.linear(duration: 0.25), value: sessionFraction)
                    Circle().stroke(Palette.limestone.opacity(0.17), lineWidth: 1).frame(width: 232, height: 232)
                    VStack(spacing: 16) {
                        Text(model.engine.isPaused ? "En pausa" : model.engine.phaseTitle)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                        Text(formatted(model.engine.remaining))
                            .font(.system(size: 54, weight: .ultraLight, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .accessibilityLabel("Tiempo restante, \(durationLabel(Int(ceil(model.engine.remaining / 60))))")
                        Text("\(Int((sessionFraction * 100).rounded())) % completado")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .padding(.horizontal, 20)
                }
                Spacer()
                Button(model.engine.isPaused ? "Reanudar" : "Pausar", systemImage: model.engine.isPaused ? "play.fill" : "pause.fill") {
                    if model.engine.isPaused { Task { await model.resumeSession() } } else { model.pauseSession() }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.white)
                Button("Terminar antes") { cancelling = true }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 32)
            }
            .padding(32)
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .confirmationDialog("¿Guardar esta práctica como parcial?", isPresented: $cancelling, titleVisibility: .visible) {
            Button("Guardar práctica parcial") { model.endSessionEarly() }
            Button("Seguir meditando", role: .cancel) {}
        } message: {
            Text("Se guardará el tiempo meditado. No contará como sesión completa ni enviará un aviso a tus amigos.")
        }
        .alert("Sesión", isPresented: Binding(get: { model.engine.error != nil }, set: { if !$0 { model.engine.error = nil } })) {
            Button("Aceptar") { model.engine.error = nil }
        } message: { Text(model.engine.error ?? "") }
    }
    private func formatted(_ seconds: Double) -> String {
        let value = Int(ceil(seconds))
        if value >= 3600 { return String(format: "%02d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    private var sessionFraction: Double {
        guard let total = model.engine.progress?.configuration.totalSeconds, total > 0 else { return 0 }
        return min(1, max(0, (total - model.engine.remaining) / total))
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if !model.records.isEmpty {
                Section {
                    PracticeWeekView(records: model.records)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Últimos siete días")
                }
                Section {
                    HStack(spacing: 12) {
                        Label("\(model.statistics.weeklySessions) completas", systemImage: "checkmark.circle.fill")
                        Spacer()
                        Label("\(model.statistics.weeklyMinutes) min", systemImage: "clock.fill")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.green)
                    .padding(.vertical, 5)
                } header: {
                    Text("Resumen semanal")
                }
                Section {
                    MilestoneView(statistics: model.statistics)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Hito personal")
                }
            }
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    PracticeMetric(value: "\(model.statistics.sessions)", label: "Completas", icon: "checkmark.circle.fill")
                    PracticeMetric(value: "\(model.statistics.minutes)", label: "Minutos meditados", icon: "clock")
                    PracticeMetric(value: "\(model.statistics.dailyStreak)", label: "Días seguidos", icon: "calendar")
                    PracticeMetric(value: "\(model.statistics.twiceDailyStreak)", label: "Mañana y noche", icon: "sun.and.horizon")
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("Tu práctica")
            }
            if model.statistics.partialSessions > 0 {
                Section {
                    Label(
                        "\(model.statistics.partialSessions) \(model.statistics.partialSessions == 1 ? "práctica parcial guardada" : "prácticas parciales guardadas")",
                        systemImage: "clock.badge.checkmark"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            if model.records.isEmpty {
                ContentUnavailableView {
                    Label("Tu historial empieza aquí", systemImage: "calendar")
                } description: {
                    Text("Las prácticas completas y parciales se guardan automáticamente.")
                } actions: {
                    Button("Ir a meditar") { model.tab = 0 }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
            }
            ForEach(Dictionary(grouping: model.records, by: \.localDate).keys.sorted(by: >), id: \.self) { day in
                Section(day) {
                    ForEach(model.records.filter { $0.localDate == day }) { record in
                        NavigationLink {
                            Form {
                                LabeledContent("Fecha de práctica", value: record.localDate)
                                LabeledContent("Práctica", value: record.slot == "morning" ? "Mañana" : "Tarde / noche")
                                LabeledContent("Estado", value: record.completed ? "Completa" : "Parcial")
                                LabeledContent(record.completed ? "Duración" : "Tiempo meditado", value: practiceDurationLabel(record.durationSeconds))
                                if !record.completed {
                                    LabeledContent("Duración prevista", value: practiceDurationLabel(record.plannedDurationSeconds))
                                    Text("Las prácticas parciales suman tiempo meditado, pero no cuentan para rachas, hitos ni avisos a amigos.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                LabeledContent("Zona al empezar", value: record.timeZoneID)
                                LabeledContent("Audio", value: {
                                    let names = AudioKind.allCases.filter { record.configuration.audio.contains($0) }.map(\.title)
                                        + (record.configuration.catalogAudio.map { [$0.title] } ?? [])
                                    return names.isEmpty ? "Sin audio" : names.joined(separator: ", ")
                                }())
                            }.navigationTitle("Sesión")
                        } label: {
                            HStack {
                                Label(
                                    record.completed
                                        ? (record.slot == "morning" ? "Mañana" : "Tarde / noche")
                                        : (record.slot == "morning" ? "Parcial · mañana" : "Parcial · tarde / noche"),
                                    systemImage: record.completed ? (record.slot == "morning" ? "sun.max" : "moon") : "clock.badge.checkmark"
                                )
                                Spacer(); Text(practiceDurationLabel(record.durationSeconds)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.stone)
        .navigationTitle("Historial").refreshable { await model.sync.sync() }
    }
}

private struct MilestoneView: View {
    let statistics: MeditationStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Palette.gold)
                Text("Próximo hito: \(statistics.nextMilestone) sesiones")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            ProgressView(value: Double(statistics.sessions), total: Double(statistics.nextMilestone))
                .tint(Palette.gold)
            Text(statistics.sessionsToNextMilestone == 1
                 ? "Falta una sesión."
                 : "Faltan \(statistics.sessionsToNextMilestone) sesiones. Cada práctica cuenta.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(17)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.72)) }
        .accessibilityElement(children: .combine)
    }
}

private struct PracticeWeekView: View {
    let records: [SessionRecord]

    private var days: [(key: String, label: String, spoken: String, slots: Set<String>)] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            let key = DayKey.make(date, timeZone: .current)
            let slots = Set(records.filter { $0.completed && $0.localDate == key }.map(\.slot))
            let spoken = date.formatted(.dateTime.weekday(.wide).day().month())
            return (key, formatter.string(from: date).uppercased(), spoken, slots)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.key) { day in
                VStack(spacing: 9) {
                    Text(day.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 4) {
                        Circle()
                            .fill(day.slots.contains("morning") ? Palette.gold : Palette.limestone.opacity(0.42))
                        Circle()
                            .fill(day.slots.contains("evening") ? Palette.green : Palette.limestone.opacity(0.42))
                    }
                    .frame(width: 18, height: 40)
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: day))
            }
        }
        .padding(18)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.72)) }
    }

    private func accessibilityLabel(for day: (key: String, label: String, spoken: String, slots: Set<String>)) -> String {
        if day.slots.isEmpty { return "\(day.spoken), sin sesión" }
        if day.slots.contains("morning") && day.slots.contains("evening") { return "\(day.spoken), sesión de mañana y de noche" }
        return "\(day.spoken), sesión de \(day.slots.contains("morning") ? "mañana" : "noche")"
    }
}

private struct PracticeMetric: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.system(.title, design: .rounded, weight: .medium))
                .foregroundStyle(Palette.green)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.72)) }
    }
}

struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var showingShare = false

    private var incomingChannelCount: Int {
        model.friends.filter { $0.direction == .incoming }.count
    }

    private var acceptedRecipientCount: Int {
        model.friends.filter { $0.direction == .outgoing && $0.status == "accepted" }.count
    }

    var body: some View {
        List {
            Section {
                LabeledContent("iCloud", value: model.cloudAvailable ? "Conectado" : "No disponible")
                LabeledContent("Canales que recibes", value: "\(incomingChannelCount)")
                LabeledContent("Personas que reciben", value: "\(acceptedRecipientCount)")
                Button(model.sync.syncing ? "Comprobando…" : "Comprobar ahora", systemImage: "arrow.clockwise") {
                    Task { await model.sync.sync() }
                }
                .disabled(model.sync.syncing || !model.cloudAvailable)
            } header: {
                Text("Estado")
            } footer: {
                Text("Para intercambiar avisos, cada persona acepta la invitación de la otra. El estado se actualiza desde iCloud.")
            }
            Section {
                if model.cloudAvailable {
                    TextField("Nombre visible para tus amigos", text: $name)
                        .textContentType(.name).onSubmit { model.saveDisplayName(name) }
                    Button("Invitar o gestionar amigos", systemImage: "person.crop.circle.badge.plus") {
                        model.saveDisplayName(name); showingShare = true
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("La invitación privada se envía con la interfaz de iCloud. Para recibir avisos mutuamente, cada persona comparte su canal con la otra.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Activa iCloud Drive para Ecuanimidad. El temporizador y el historial siguen funcionando sin iCloud.")
                        .foregroundStyle(.secondary)
                }
            } header: { Text("Tu canal privado") } footer: {
                Text("CloudKit está incluido con Apple; esta función no requiere Firebase, servidor propio ni cuenta de facturación.")
            }
            Section("Amigos") {
                if model.friends.isEmpty { Text("Todavía no hay canales compartidos.").foregroundStyle(.secondary) }
                ForEach(model.friends) { friend in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(friend.name).font(.headline)
                        Text(friend.direction == .incoming ? "Comparte sus sesiones contigo" : (friend.status == "accepted" ? "Recibe tus sesiones" : "Invitación pendiente"))
                            .font(.caption).foregroundStyle(.secondary)
                        if friend.direction == .incoming {
                            Button(friend.muted ? "Activar avisos" : "Silenciar avisos") { model.toggleMute(friend) }
                        }
                    }
                    .swipeActions {
                        Button(friend.direction == .incoming ? "Dejar canal" : "Retirar acceso", role: .destructive) {
                            Task { await model.remove(friend) }
                        }
                    }
                }
            }
            if model.sync.pending > 0 { Text("\(model.sync.pending) sesiones pendientes de sincronizar").font(.footnote).foregroundStyle(.secondary) }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.stone)
        .navigationTitle("Amigos").refreshable { await model.sync.sync() }
        .onAppear { name = model.displayName }
        .sheet(isPresented: $showingShare) { CloudSharingSheet(displayName: model.displayName) }
    }
}

struct CloudSharingSheet: UIViewControllerRepresentable {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let displayName: String

    func makeCoordinator() -> Coordinator { Coordinator(model: model, dismiss: dismiss) }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        guard let container = model.cloud.container else {
            return UIActivityViewController(
                activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [])
            )
        }
        let provider = NSItemProvider()
        let options = CKAllowedSharingOptions(
            allowedParticipantPermissionOptions: .readOnly,
            allowedParticipantAccessOptions: .specifiedRecipientsOnly
        )
        let cloud = model.cloud
        provider.registerCKShare(container: container, allowedSharingOptions: options) {
            try await cloud.prepareShare(displayName: displayName)
        }
        let configuration = UIActivityItemsConfiguration(itemProviders: [provider])
        configuration.metadataProvider = { key in
            key == .title ? "Canal de práctica" : nil
        }
        let controller = UIActivityViewController(activityItemsConfiguration: configuration)
        controller.completionWithItemsHandler = { _, _, _, error in
            Task { @MainActor in
                if let error { context.coordinator.model.error = error.localizedDescription }
                await context.coordinator.model.sync.sync()
                context.coordinator.dismiss()
            }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject {
        let model: AppModel
        let dismiss: DismissAction
        init(model: AppModel, dismiss: DismissAction) { self.model = model; self.dismiss = dismiss }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(OldStudentAccess.grantedKey) private var oldStudentAccessGranted = false
    @State private var reminderSheet = false
    @State private var privacySheet = false
    @State private var exporting = false
    @State private var deleteConfirmation = false
    @State private var showingCatalog = false
    @State private var exportDocument = HistoryExportDocument(records: [])
    var body: some View {
        Form {
            Section("Audios y perfiles") {
                Button("Abrir catálogo", systemImage: "waveform") { showingCatalog = true }
                LabeledContent("Revisión", value: model.catalog.document.revision)
                Text("Los catálogos remotos permiten añadir audios y perfiles sin publicar otra versión.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Recordatorios personales") {
                Button("Configurar recordatorios") { reminderSheet = true }
                Text("El gong respeta los ajustes de sonido y Concentración del iPhone.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Compartir mis sesiones", isOn: Binding(get: { model.shareSessions }, set: { value in Task { await model.setSocial(share: value, receive: model.socialNotifications) } }))
                Toggle("Recibir avisos de amigos", isOn: Binding(get: { model.socialNotifications }, set: { value in Task { await model.setSocial(share: model.shareSessions, receive: value) } }))
                Text("Ejemplo: «Un amigo ha completado su meditación matutina y te envía metta». No muestra nombres, duración ni audio.").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Privacidad social") } footer: {
                Text("Los avisos usan CloudKit y APNs sin un servidor de la app. El filtrado por amigo depende de que iOS procese el push silencioso y puede demorarse.")
            }
                .disabled(!model.cloudAvailable)
            Section("Sincronización") {
                LabeledContent("iCloud", value: model.cloudAvailable ? "Disponible" : "No disponible")
                LabeledContent("Notificaciones", value: model.notificationStatus)
                LabeledContent("Pendientes", value: "\(model.sync.pending)")
                if let date = model.sync.lastSync { LabeledContent("Última sincronización", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if let error = model.sync.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                Button(model.sync.syncing ? "Sincronizando…" : "Sincronizar ahora") { Task { await model.sync.sync() } }.disabled(model.sync.syncing || !model.cloudAvailable)
                Button("Probar aviso en este iPhone", systemImage: "bell.badge") { Task { await model.sendTestNotification() } }
                Text("La prueba confirma permiso y presentación local. La ruta CloudKit/APNs completa se comprueba con dos iPhones.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Exportar historial", systemImage: "square.and.arrow.up") {
                    exportDocument = HistoryExportDocument(records: model.records)
                    exporting = true
                }
                .disabled(model.records.isEmpty)
                Button("Borrar todo mi historial", systemImage: "trash", role: .destructive) {
                    deleteConfirmation = true
                }
                .disabled(model.records.isEmpty && model.sync.pending == 0)
            } header: {
                Text("Tus datos")
            } footer: {
                Text("El borrado es inmediato en este iPhone y se aplica en iCloud al recuperar conexión. No elimina amigos ni preferencias.")
            }
            Section("Privacidad y ayuda") {
                Button("Cómo funciona tu privacidad", systemImage: "hand.raised") { privacySheet = true }
                Button("Volver a ver la bienvenida", systemImage: "rectangle.portrait.and.arrow.forward") {
                    hasCompletedOnboarding = false
                }
            }
            Section("Acceso") {
                LabeledContent("Antiguo alumno", value: "Verificado en este iPhone")
                Button("Cerrar acceso", systemImage: "lock", role: .destructive) {
                    oldStudentAccessGranted = false
                }
            }
            Section("Acerca de") {
                Text("Ecuanimidad · versión de desarrollo").font(.headline)
                Text("Una herramienta independiente para tu práctica personal, sin afiliación institucional.").font(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.stone)
        .navigationTitle("Ajustes")
        .sheet(isPresented: $reminderSheet) { ReminderView(settings: model.reminders) }
        .sheet(isPresented: $privacySheet) { PrivacySummaryView() }
        .sheet(isPresented: $showingCatalog) { AudioCatalogView() }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "Ecuanimidad-historial") { result in
            if case .failure(let error) = result { model.error = error.localizedDescription }
        }
        .confirmationDialog("¿Borrar todo el historial?", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            Button("Borrar historial", role: .destructive) { Task { await model.deleteHistory() } }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Las sesiones y estadísticas se eliminarán. Esta acción no se puede deshacer.")
        }
    }
}

struct PrivacySummaryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PrivacyRow(icon: "iphone", title: "En este iPhone", detail: "Temporizador, configuración e historial se guardan localmente y funcionan sin conexión.")
                    PrivacyRow(icon: "icloud", title: "En iCloud", detail: "Si está disponible, las sesiones se sincronizan en tu base privada. Las invitaciones comparten únicamente señales mínimas de práctica.")
                    PrivacyRow(icon: "eye.slash", title: "Sin seguimiento", detail: "No hay publicidad, analítica de terceros, contactos, ubicación ni perfiles comerciales.")
                } header: {
                    Text("Qué ocurre con tus datos")
                }
                Section {
                    PrivacyRow(icon: "person.2", title: "Avisos discretos", detail: "Un amigo recibe solo si fue una práctica de mañana o tarde. El aviso dice que le envías metta; no muestra tu nombre, duración ni audio.")
                    PrivacyRow(icon: "switch.2", title: "Tú decides", detail: "Compartir sesiones, recibir avisos y cada silencio individual son controles separados y empiezan desactivados.")
                    PrivacyRow(icon: "square.and.arrow.up", title: "Exportar o borrar", detail: "Puedes exportar tu historial como JSON o borrarlo desde Ajustes.")
                } header: {
                    Text("Tus controles")
                }
                Section {
                    Text("Ecuanimidad es una aplicación independiente. No está afiliada a VRI, Dhamma.org ni a una organización de Vipassana.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Privacidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
}

private struct PrivacyRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .frame(width: 26)
                .foregroundStyle(Palette.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ReminderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var settings: ReminderSettings
    var body: some View {
        NavigationStack {
            Form {
                Section("Mañana") {
                    Toggle("Recordatorio de mañana", isOn: $settings.morningEnabled)
                    DatePicker("Hora", selection: timeBinding(morning: true), displayedComponents: .hourAndMinute)
                }
                Section("Noche") {
                    Toggle("Recordatorio de noche", isOn: $settings.eveningEnabled)
                    DatePicker("Hora", selection: timeBinding(morning: false), displayedComponents: .hourAndMinute)
                }
                Section {
                    Toggle("Avisarme si el hilo puede recuperarse", isOn: $settings.continuityEnabled)
                    DatePicker("Hora", selection: continuityTimeBinding, displayedComponents: .hourAndMinute)
                        .disabled(!settings.continuityEnabled)
                } header: {
                    Text("Hilo de práctica")
                } footer: {
                    Text("Solo se programa cuando ayer fue una pausa y todavía puedes continuar el hilo hoy.")
                }
                Toggle("Sonido de gong", isOn: $settings.sound)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.stone)
            .navigationTitle("Recordatorios").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Guardar") { Task { await model.saveReminders(settings); if model.error == nil { dismiss() } } } }
                }
        }
    }
    func timeBinding(morning: Bool) -> Binding<Date> {
        Binding(get: {
            let minute = morning ? settings.morningMinute : settings.eveningMinute
            return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let value = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if morning { settings.morningMinute = value } else { settings.eveningMinute = value }
        })
    }
    var continuityTimeBinding: Binding<Date> {
        Binding(get: {
            Calendar.current.date(
                bySettingHour: settings.continuityMinute / 60,
                minute: settings.continuityMinute % 60,
                second: 0,
                of: Date()
            ) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.continuityMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        })
    }
}
