# Arquitectura

`AppModel` compone SwiftData (`LocalStore`), `SessionEngine`, AVFoundation (`AudioService`), UserNotifications (`NotificationService`), CloudKit (`CloudService`) y `SyncService`. Las vistas no acceden directamente a almacenamiento ni red. El núcleo de sesión y estadísticas permanece en `MeditationCore` y tiene pruebas independientes.

## Datos locales

- `MeditationSession`: práctica completa o parcial codificada, con tiempo real, tiempo previsto y clave `local:<UUID>`.
- `ActiveSession`: configuración congelada, pausa y fecha real de finalización.
- `Preferences`: sesión, recordatorios, nombre social y consentimientos.
- `SyncOperation`: outbox persistente para sesiones privadas y señales autorizadas.
- `FriendSnapshot`: canal entrante o participante saliente, silencio y primera fecha observada.
- `SocialReceipt`: ID de señal procesada para deduplicación.

Guardar la sesión, insertar su outbox y eliminar la sesión activa usa una sola transacción SwiftData. Los reintentos conservan el UUID y CloudKit usa nombres de registro derivados de ese UUID.

## CloudKit

La base privada contiene `MeditationSession` y una zona personalizada `PracticeChannel`. La raíz `PracticeChannel` se comparte mediante `CKShare` con permiso privado de solo lectura. Sus hijos `PracticeSignal` contienen únicamente `eventID`, `completedAt` y la franja `morning`/`evening`.

La base compartida del receptor contiene los canales aceptados. Una `CKDatabaseSubscription` solicita contenido en segundo plano. Tras el push, la app consulta las zonas compartidas, deduplica, filtra por consentimiento y silencio, y crea un aviso local por amigo. Los eventos anteriores a la primera observación del canal se ignoran para que una amistad nueva no genere avisos históricos.

La app no controla servidores ni secretos y no puede suplantar al propietario de un canal: solo el propietario escribe señales y los participantes reciben acceso de lectura. Las identidades y la aceptación son gestionadas por iCloud.

## Límites deliberados

- Las relaciones recíprocas requieren dos invitaciones, una por canal.
- Se sustituye el código privado corto por el enlace privado del sistema CloudKit.
- El filtrado individual exige push silencioso y ejecución en segundo plano; iOS puede retrasarlo o coalescerlo.
- Retirar acceso evita lecturas futuras. CloudKit conserva la semántica de participantes; la app no implementa un directorio global ni búsqueda de usuarios.
- El historial local funciona sin iCloud. La sincronización y los amigos requieren una cuenta iCloud activa.
- La puerta de antiguo alumno compara hashes locales de las credenciales compartidas y recuerda únicamente el acceso concedido. Sirve como control de acceso casual; no constituye identidad individual ni sustituye una autenticación de servidor.

## Esquema para producción

Antes de TestFlight, usa CloudKit Dashboard para confirmar los tipos y campos creados en desarrollo, crea índices consultables para los tipos consultados y despliega el esquema al entorno Production. Configura el contenedor `iCloud.<bundle-id>` en el App ID y en los perfiles de firma.
