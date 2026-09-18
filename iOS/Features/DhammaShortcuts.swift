import AppIntents
import Foundation

struct StartMeditationIntent: AppIntent {
    static let title: LocalizedStringResource = "Iniciar meditación"
    static let description = IntentDescription("Abre Ecuanimidad e inicia una sesión con la configuración de audio guardada.")
    static let openAppWhenRun = true

    @Parameter(title: "Duración en minutos", default: 60)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Meditar durante \(\.$minutes) minutos")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let validMinutes = min(480, max(5, minutes))
        UserDefaults.standard.set(validMinutes, forKey: "pendingQuickStartMinutes")
        return .result(dialog: "Abriendo Ecuanimidad para meditar durante \(validMinutes) minutos.")
    }
}

struct DhammaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMeditationIntent(),
            phrases: [
                "Iniciar una meditación en \(.applicationName)",
                "Meditar con \(.applicationName)"
            ],
            shortTitle: "Meditar",
            systemImageName: "timer"
        )
    }
}
