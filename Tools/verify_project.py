#!/usr/bin/env python3
"""Static checks that do not require Xcode, Apple credentials, or network access."""
from pathlib import Path
import plistlib
import struct

root = Path(__file__).resolve().parents[1]
checks = []

def check(condition, message):
    if not condition:
        raise AssertionError(message)
    checks.append(message)

info = plistlib.loads((root / "iOS/Info.plist").read_bytes())
entitlements = plistlib.loads((root / "iOS/Meditacion.entitlements").read_bytes())
project = (root / "Meditacion.xcodeproj/project.pbxproj").read_text()
cloud = (root / "iOS/Services/CloudService.swift").read_text()
app = (root / "iOS/App/AppModel.swift").read_text()
notifications = (root / "iOS/Services/NotificationService.swift").read_text()
catalog = (root / "iOS/Services/AudioCatalogService.swift").read_text()
access = (root / "iOS/Features/OldStudentAccessView.swift").read_text()
timelapse = (root / "iOS/Services/TimelapseService.swift").read_text()
store = (root / "iOS/Data/LocalStore.swift").read_text()
views = (root / "iOS/Features/Views.swift").read_text()
core = (root / "Core/Session.swift").read_text()
generator = (root / "Tools/generate_project.py").read_text()
swift_sources = "\n".join(p.read_text() for p in (root / "iOS").rglob("*.swift"))

def png_size(path):
    data = path.read_bytes()
    check(data[:8] == b"\x89PNG\r\n\x1a\n", f"PNG válido: {path.name}")
    return struct.unpack(">II", data[16:24])

def jpeg_size(path):
    data = path.read_bytes()
    check(data[:2] == b"\xff\xd8", f"JPEG válido: {path.name}")
    offset = 2
    while offset + 9 < len(data):
        if data[offset] != 0xFF:
            offset += 1
            continue
        marker = data[offset + 1]
        offset += 2
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        length = int.from_bytes(data[offset:offset + 2], "big")
        if marker in {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}:
            height = int.from_bytes(data[offset + 3:offset + 5], "big")
            width = int.from_bytes(data[offset + 5:offset + 7], "big")
            return width, height
        offset += length
    raise AssertionError(f"No se encontraron dimensiones JPEG: {path.name}")

check(info.get("CKSharingSupported") is True, "CloudKit sharing activado")
check(info.get("CFBundleDisplayName") == "Ecuanimidad", "Nombre visible Ecuanimidad")
background = set(info.get("UIBackgroundModes", []))
check({"audio", "remote-notification"} <= background, "Modos de audio y push en segundo plano")
check(entitlements.get("aps-environment") == "$(APS_ENVIRONMENT)", "Entitlement APNs por configuración")
check(entitlements.get("com.apple.developer.icloud-services") == ["CloudKit"], "Servicio CloudKit habilitado")
containers = entitlements.get("com.apple.developer.icloud-container-identifiers", [])
check(containers == ["iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)"], "Contenedor iCloud ligado al bundle ID")
check('"name" = "Evamor Local"' in project, "Target local disponible para Personal Team")
check('"path" = "EvamorLocal.app"' in project, "Producto local independiente")
check('"PRODUCT_BUNDLE_IDENTIFIER" = "com.manuelbecerril.evamor.local"' in project, "Bundle ID local independiente")
check('EVAMOR_LOCAL' in project and 'targetEnvironment(simulator) || EVAMOR_LOCAL' in cloud, "CloudKit desactivado en el iPhone para el target local")
local_scheme = (root / "Meditacion.xcodeproj/xcshareddata/xcschemes/Evamor Local.xcscheme").read_text()
check('BlueprintName="Evamor Local"' in local_scheme, "Esquema Evamor Local compartido")
check("XCRemoteSwiftPackageReference" not in project, "Sin paquetes Swift remotos")
check("Firebase" not in project and "import Firebase" not in swift_sources, "Sin SDK de Firebase")
check("CKDatabaseSubscription" in cloud, "Suscripción a cambios de la base compartida")
check("shouldSendContentAvailable = true" in cloud, "Push silencioso solicitado para aplicar privacidad")
check("registerForRemoteNotifications" in cloud, "Registro APNs presente")
check("accept(metadata)" in cloud, "Aceptación de invitaciones CloudKit")
check('share.publicPermission = .none' in cloud, "Enlace público desactivado")
check(".specifiedRecipientsOnly" in swift_sources and ".readOnly" in swift_sources, "Participantes restringidos a invitación privada y lectura")
check('var shareSessions = false' in app, "Envío social desactivado inicialmente")
check('var socialNotifications = false' in app, "Recepción social desactivada inicialmente")
check("SocialReceipt" in store and "func claim(" in store, "Deduplicación persistente de señales")
check("firstSeenAt" in store and "event.completedAt >= friend.firstSeenAt" in core, "Eventos anteriores a la amistad ignorados")
check("!friend.muted" in core, "Silencio por amigo aplicado antes del aviso")
check('return "Un amigo ha completado \\(practice) y te envía metta."' in notifications, "Texto social de metta sin nombre ni duración")
check("SocialNotificationPolicy.batches" in app, "Sesiones atrasadas agrupadas por una política probada")
artwork = root / "iOS/Resources/Assets.xcassets/CompletionArtwork.imageset/CompletionArtwork.png"
check(artwork.exists() and artwork.stat().st_size > 1_000, "Ilustración de finalización incluida")
check(png_size(artwork) == (1254, 1254), "Ilustración maestra a 1254 × 1254")
icon = root / "iOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
check(icon.exists() and png_size(icon) == (1024, 1024), "Icono de aplicación a 1024 × 1024")
master = root / "Design/StillnessMark-v2.png"
check(master.exists() and master.read_bytes() == artwork.read_bytes(), "Original visual versionado y conectado")
check("required_artwork.exists()" in generator and ".write_bytes(" not in generator, "El generador preserva la identidad visual")
check('Text(title)' in views and 'completionTitle = "Sé feliz"' in app and 'Image("CompletionArtwork")' in views, "Frase e ilustración conectadas a la vista")
photo = root / "iOS/Resources/Assets.xcassets/ClosingPhoto.imageset/ClosingPhoto.jpg"
photo_master = root / "Design/ClosingPhoto-original.JPG"
check(photo.exists() and jpeg_size(photo) == (896, 1195), "Foto de cierre incluida a 896 × 1195")
check(photo_master.exists() and photo_master.read_bytes() == photo.read_bytes(), "Foto original preservada sin alteraciones")
check('Image("ClosingPhoto")' in views and 'Palette.night.opacity(0.92)' in views, "Fotografía conservada con contraste en el cierre")
check('private var audioSummary' in views and 'Acomódate. Cuando estés listo, comienza.' in views, "Portada renovada con resumen accesible")
check('Text("Duración rápida")' in views and 'ForEach([5, 15, 30, 60]' in views, "Duraciones rápidas guardadas desde la portada")
check('model.setQuickDuration(minutes)' in views and '.disabled(minutes < model.configuration.minimumMinutes)' not in views, "Duraciones rápidas siempre pulsables")
check('.toolbar(.hidden, for: .navigationBar)' in views and '.navigationTitle("Evamor")' not in views and '.navigationTitle("Ecuanimidad")' not in views, "Portada sin título de texto sobre el símbolo")
check("PracticeWeekView(records: model.records)" in views and 'slots.contains("morning")' in views, "Ritmo semanal local de mañana y noche")
check('Button("Ir a meditar") { model.tab = 0 }' in views, "Estado vacío conduce directamente a meditar")
check('Label("Hilo de práctica"' in views and "PracticeContinuity" in core, "Continuidad amable visible y derivada de sesiones")
check("needsRecoveryToday" in core and "pendingPause" in core, "Una pausa recuperable sin contadores mutables")
check("continuity-recovery" in notifications and "continuityEnabled" in core, "Recordatorio opcional para recuperar el hilo")
check("weeklySessions" in core and 'Text("Resumen semanal")' in views, "Resumen semanal derivado del historial")
check("nextMilestone" in core and "sessionsToNextMilestone" in views, "Hitos personales sin clasificación")
check("#if targetEnvironment(simulator)" in cloud and "self.container = nil" in cloud, "Modo personal arranca en simulador sin CloudKit")
check("showCompletionCelebration = true" in app, "Cierre visual activado únicamente desde la finalización")
check("accessibilityReduceMotion" in views, "Animación respeta Reducir movimiento")
check("allowedMinutes = 5...480" in core, "Duraciones permitidas entre 5 minutos y 8 horas")
check(".introduction, .chanting" in core and ".closing, .metta" in core, "Secuencia de apertura, silencio y cierre conservada")
check("if deliver && engine.progress != nil" in app, "Avisos sociales retenidos durante la meditación")
check("processIncoming(deliver: true)" in app, "Recuperación de avisos al volver a primer plano")
check('%02d:%02d:%02d' in views, "Contador con horas para sesiones largas")
check('case .metta: return "Metta extendido"' in core and "ForEach(AudioKind.userSelectable" in views, "Metta disponible en la configuración")
check('Button("Exportar historial"' in views and "HistoryExportDocument" in swift_sources, "Exportación local del historial")
check('Button("Borrar todo mi historial"' in views and 'kind: "deleteHistory"' in store, "Borrado local inmediato con sincronización pendiente")
check('filter({ $0.kind == "deleteHistory" })' in swift_sources and "cloud.deleteHistory()" in swift_sources, "Borrado remoto se procesa antes de nuevas sesiones")
check("StartMeditationIntent" in swift_sources and "AppShortcutsProvider" in swift_sources, "Atajo de Siri para iniciar meditación")
check("NSCameraUsageDescription" in info and "timelapse" in info["NSCameraUsageDescription"], "Permiso de cámara contextualizado")
check("AVCaptureVideoDataOutput" in timelapse and "AVCaptureAudioDataOutput" not in timelapse, "Timelapse frontal sin entrada de micrófono")
check("AVAssetWriter" in timelapse and "maximumOutputSeconds = 30" in core, "MP4 directo limitado a unos 30 segundos")
check("VNDetectHumanBodyPoseRequest" in timelapse and "VNDetectFace" not in timelapse, "Movimiento corporal local sin análisis facial")
check('Probar cámara y movimiento · 30 s' in views and 'TimelapseTestView' in swift_sources, "Prueba local breve de cámara y movimiento")
check('Guardar en Fotos' in swift_sources and 'NSPhotoLibraryAddUsageDescription' in info, "Exportación explícita del timelapse a Fotos")
check('colors: [Palette.green.opacity(0.58), Palette.night.opacity(0.92)]' in views, "Fondo tranquilo y legible de cierre")
check('VideoPlayer(player:' in swift_sources and 'Label("Ver timelapse"' in views, "Reproductor de timelapse dentro de la aplicación")
check("MeditationMedia" in store and 'kind: "session"' not in store[store.find("func saveMedia"):store.find("func mediaFilename")], "Vídeo y movimiento excluidos de sincronización")
check('Toggle("Crear timelapse"' in views and 'Label("Compartir timelapse"' in views, "Control y compartición explícitos")
check("no mide ecuanimidad" in views and "MovementBand" in core, "Bandas amables sin afirmar calidad mental")
check("cameraPausedForBackground" in app and "model.background()" in swift_sources and "engine.pause()" not in app[app.find("func background()"):app.find("func beginMeditation()")], "La cámara se pausa pero la sesión continúa en segundo plano")
check("OldStudentAccess.verify" in access and "SecureField" in access and "oldStudentAccessGranted" in swift_sources, "Puerta local para antiguos alumnos")
check("SHA256.hash" in access and "behappy" not in access, "La contraseña no se guarda en texto claro en la aplicación")
check("EvamorAudioCatalogURL" in info and "downloadURL" in catalog and "checksumMismatch" in catalog, "Catálogo remoto HTTPS con verificación de integridad")
check("savedProfiles" in catalog and "togglePreview" in catalog, "Perfiles guardados y vista previa de audio")
check("deleteAllMedia" in store and "timelapseRetentionDays" in app, "Borrado automático y en grupo de timelapses")
check("struct PaliQuote" in swift_sources and "static let collection" in swift_sources and "quote.translation" in swift_sources, "Frases en pali con traducción en timelapses")
check("completed: Bool" in core and "plannedDurationSeconds" in core and "partialSessions" in core, "Prácticas parciales conservan tiempo real y previsto")
check("func finishEarly" in swift_sources and "onPartialSaved" in swift_sources and 'Guardar práctica parcial' in views, "Terminar antes guarda y presenta la práctica parcial")
check("record.completed" in cloud and "guard share, record.shareAtCompletion, record.completed" in cloud and "sharingEnabled && record.completed" in swift_sources, "Las prácticas parciales no generan avisos sociales")
check('onLongPressGesture(minimumDuration: 3)' in views and 'Text("Para Eva, con amor.")' in views and 'cuánto mereces sonreír' in views, "Dedicatoria oculta en el centro dorado")
check('("E", "Estar")' in views and '("R", "Regresar")' in views, "Acrónimo EVAMOR completo")

print(f"PASS {len(checks)} comprobaciones estáticas")
for item in checks:
    print(f"  ✓ {item}")
