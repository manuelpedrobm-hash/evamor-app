# Ecuanimidad · iPhone

Aplicación original en SwiftUI para iOS 17+. Temporizador, audio, historial, estadísticas y recordatorios funcionan offline. SwiftData guarda primero cada sesión y mantiene una cola para sincronizarla cuando iCloud vuelva a estar disponible.

La primera pantalla limita el acceso a antiguos alumnos mediante las credenciales compartidas indicadas para este proyecto. La app compara hashes locales, no conserva la contraseña y permite cerrar el acceso desde Ajustes. Este mecanismo impide el acceso casual, pero una credencial común no verifica la identidad de cada alumno; para esa garantía haría falta un servicio de cuentas individual.

**Ecuanimidad** es el nombre visible. La dedicatoria privada y el acrónimo EVAMOR permanecen como un detalle oculto al mantener pulsado el centro del símbolo. Antes de distribuirla públicamente hay que comprobar la disponibilidad comercial del nombre y dejar clara en la ficha de App Store la ausencia de afiliación con VRI, Dhamma.org o cualquier organización de Vipassana.

## Coste operativo

La versión entregada no contiene Firebase, Cloud Functions, Firestore, FCM, servidor propio, API de pago ni dependencia de terceros. La función social usa **CloudKit sharing + APNs**, incluidos con la membresía de Apple Developer. No hay una cuenta de facturación que pueda generar cargos variables del backend.

La membresía de Apple Developer tiene su propio coste anual para distribuir en App Store; no es consumo del backend. Hay cuotas técnicas de iCloud y Apple puede limitar una app que abuse del servicio, pero esta arquitectura no convierte el exceso en una factura automática.

## Abrir y ejecutar

### Probar con un Apple ID gratuito en un iPhone

1. Abre `Meditacion.xcodeproj` y elige el esquema **Evamor Local** en la barra superior.
2. En el target **Evamor Local**, abre **Signing & Capabilities**, activa la firma automática y selecciona tu *Personal Team*.
3. Selecciona el iPhone como destino y pulsa Run. Esta variante no solicita iCloud ni Push Notifications, por lo que puede firmarse con un equipo personal.
4. Los datos se guardan localmente. Temporizador, audio, metta, historial, recordatorios locales, cámara, movimiento y timelapse siguen disponibles. La sincronización y los avisos entre amigos permanecen inactivos hasta usar el target completo con una membresía compatible.

La app local usa `com.manuelbecerril.evamor.local`; el target completo conserva `com.manuelbecerril.evamor` y sus capacidades de iCloud y push.

### Ejecutar la versión social completa

1. Usa una membresía del Apple Developer Program y selecciona el esquema **Meditacion**.
2. En el target **Meditacion**, selecciona el equipo de pago para `com.manuelbecerril.evamor`.
3. En **Signing & Capabilities**, confirma iCloud con CloudKit, Push Notifications y Background Modes (`Audio` y `Remote notifications`). El contenedor esperado es `iCloud.<bundle-id>`.
4. Para iCloud sharing y push usa dos iPhones reales con cuentas de iCloud distintas.

El proyecto no descarga paquetes. Puede regenerarse sin XcodeGen ni CocoaPods:

```sh
python3 Tools/generate_project.py
```

Para compilar y ejecutar todas las pruebas con el Xcode instalado, sin cambiar el selector global del Mac:

```sh
Tools/xcode_verify.sh --test
```

La app desactiva CloudKit en el simulador para que el modo personal pueda ejecutarse sin firma. Las amistades y APNs se validan después en iPhones firmados.

## Cómo funcionan los amigos

Cada usuario tiene un canal `PracticeChannel` en su base privada de CloudKit. La pantalla **Amigos** abre la interfaz privada de iCloud para invitar participantes con permiso de solo lectura. El destinatario acepta el enlace del sistema. Para avisos mutuos, cada persona comparte su propio canal con la otra una vez.

Al completar una sesión con **Compartir mis sesiones** activo:

1. La sesión se guarda en SwiftData junto con una operación estable de sincronización.
2. CloudKit recibe una copia privada de la sesión y una señal mínima en el canal compartido. La señal contiene un UUID, la fecha de finalización y la franja mañana/tarde; no contiene duración, historial ni audio.
3. Una suscripción de la base compartida genera un push silencioso de CloudKit/APNs.
4. El iPhone receptor consulta los cambios, descarta eventos ya vistos, aplica el control global y el silencio por amigo, agrupa eventos atrasados y crea un aviso local discreto.

Los push silenciosos son gestionados por iOS. Normalmente se procesan poco después, pero pueden demorarse, agruparse o no despertar la app. Es la contrapartida de filtrar por amigo sin operar un servidor. Una entrega visible más consistente con filtrado remoto exigiría backend.

Las invitaciones usan el enlace privado de CloudKit. No se ofrece un código corto: resolverlo, impedir enumeración y validar remitente/destinatario de forma segura exigiría un servicio central. El propietario puede retirar acceso; el receptor puede abandonar un canal.

## Privacidad

- Compartir sesiones y recibir avisos están desactivados inicialmente y son independientes.
- Un amigo tiene acceso de solo lectura a señales mínimas, nunca al historial privado.
- Silenciar a una persona se guarda solo en el iPhone receptor. Los eventos silenciados se marcan como vistos y no reaparecen al reactivar.
- Al desactivar recepción se elimina la suscripción CloudKit y cualquier aviso social local pendiente o entregado.
- Al desactivar envío, las sesiones que aún estén en la cola se sincronizan solo al historial privado y no generan señales sociales.
- iCloud identifica técnicamente a los participantes; la app no almacena correo, teléfono, contactos, tokens APNs ni credenciales.
- El timelapse es opcional, usa solo la cámara frontal y nunca añade una entrada de micrófono. El MP4 y su resumen de movimiento permanecen en el dispositivo; compartirlos requiere una acción explícita en la hoja del sistema.
- Vision observa puntos corporales para estimar cambios de postura. No conserva puntos, no analiza la cara y no afirma medir ecuanimidad, concentración ni calidad espiritual.

## Pruebas

```sh
swift test
python3 Tools/verify_core.py
```

Las pruebas iOS del esquema cubren finalización idempotente y offline, restauración de pausa, persistencia del silencio, deduplicación de señales, borrado del historial y orden de sincronización. Consulta `Docs/Acceptance.md` para las pruebas con dos dispositivos y `Docs/Verification.md` para el estado del entorno.

Sin Xcode también puede auditarse la configuración que condiciona la entrega:

```sh
python3 Tools/verify_project.py
python3 Tools/verify_audio.py
python3 Tools/describe_timeline.py 5 60 120 480
```

La matriz exacta de envío, recepción y silencio está en `Docs/NotificationDelivery.md`. La app incluye además **Ajustes → Sincronización → Probar aviso en este iPhone** para separar un problema de permisos locales de un problema CloudKit/APNs. `Docs/AudioPermissionRequest.md` contiene la solicitud de autorización necesaria antes de incorporar grabaciones protegidas.

## Catálogo de audios

La app ya no incluye ningún Group Sitting embebido en el binario: los cinco disponibles se sirven desde el catálogo remoto configurado en `EvamorAudioCatalogURL` (`https://manuelpedrobm-hash.github.io/evamor-audio/catalog.json`, publicado en GitHub Pages). Puede recibir audios y perfiles nuevos sin publicar otra versión. Las descargas se validan por tamaño, SHA-256 y duración, se guardan para uso sin conexión y nunca sustituyen una copia válida por una descarga incompleta. Consulta `Docs/RemoteAudioCatalog.md` para publicar cambios en el catálogo.

Los archivos facilitados son audio AAC dentro de contenedores MP4 con una extensión `.mp3` incorrecta. Se incorporan como `.m4a` válidos, sin recomprimir:

- **Long Instructions** (Salila, Dehradun): 64 min 32,715 s; perfil de 65 minutos.
- **Short Instructions** (Salila, Dehradun): 65 min 56,911 s; perfil de 66 minutos.
- **Giri** (Igatpuri): 63 min 41,214 s; perfil de 64 minutos.
- **Setu** (Chennai): 65 min 0,278 s; perfil de 65 minutos.
- **Shikhara** (Dharamshala): 65 min 9,449 s; perfil de 65 minutos.

La incorporación técnica no acredita derechos de distribución. Antes de TestFlight externo o App Store se necesita autorización escrita del titular; el usuario confirmó (17 de septiembre de 2026) contar con esa autorización para las grabaciones de S. N. Goenka.

El registro de acceso a `manuelpedrobm-hash.github.io` lo conserva GitHub Pages según su propia política de privacidad; la app no aloja el catálogo por sí misma.

## Comportamiento local

- Sesión base de 5 minutos a 8 horas. Los audios seleccionados forman parte de la base y metta se añade al final.
- La opción **Metta extendido** está en la configuración y permanece desactivada inicialmente. El recurso incluido es Bhavatu Sabba Mangalam (72,65 segundos), facilitado por el usuario.
- La portada permite elegir 5, 15, 30 o 60 minutos con un toque; la configuración completa conserva cualquier otra duración hasta 8 horas.
- La introducción es el fragmento 0:00–4:19 de Day01 Morning Chantings; metta usa Bhavatu Sabba Mangalam completo. Chanting, cierre y gong mantienen los tonos originales de prueba.
- La introducción y el cierre se colocan en los extremos de cualquier duración; el silencio absorbe toda la variación. Las grabaciones facilitadas se incorporan a petición del usuario; no se ha verificado autorización para distribución pública.
- Una interrupción o desconexión de auriculares pausa la práctica y exige reanudación explícita.
- Si iOS suspende la app durante el silencio, el reloj se reconstruye desde la fecha persistida y un aviso local puede señalar el final si hay permiso.
- Fecha, zona y franja se fijan al inicio. Las estadísticas se derivan de UUID únicos y no usan contadores acumulativos.
- Al pulsar **Terminar antes**, la práctica se guarda como parcial con el tiempo real y la duración prevista. Suma minutos meditados, pero no cuenta para rachas, hitos ni avisos a amigos. También conserva el timelapse si llegó a capturar fotogramas.
- El historial muestra los últimos siete días con indicadores separados de mañana y noche, calculados únicamente desde las sesiones locales.
- El **Hilo de práctica** enlaza sesiones y permite una pausa recuperable antes de empezar de nuevo. Se deriva del historial, sin puntos, compras, rankings ni contadores sincronizables. La regla completa está en `Docs/GentleContinuity.md`.
- Historial con resumen móvil de siete días, hitos personales y un recordatorio opcional para recuperar el hilo. Ninguna de estas funciones compara usuarios.
- El historial puede exportarse como JSON y borrarse desde Ajustes. El borrado local es inmediato y se sincroniza con iCloud antes de subir sesiones posteriores.
- Siri y Atajos pueden abrir una meditación con una duración indicada conservando la selección de audio.
- **Permanecer** crea opcionalmente un timelapse local de 10, 20 o 30 segundos. Al salir o bloquear el iPhone, iOS detiene la cámara pero la sesión y el audio continúan; al volver, la captura se reanuda si el proceso sigue vivo.
- En las compilaciones de desarrollo, **Tu sesión → Probar cámara y movimiento · 30 s** permite comprobar Permanecer sin crear una sesión ni usar iCloud. El resultado se reproduce dentro de Ecuanimidad y el archivo de prueba se elimina al cerrarlo.
- Los timelapses de prácticas completas o parciales pueden reproducirse en la pantalla de cierre y posteriormente desde **Historial → Sesión → Ver timelapse**. Cada uno muestra una de 22 frases del Dhammapada en pali con traducción española y referencia.
- El **Pulso de quietud** describe el movimiento visible como quietud sostenida, ajustes suaves o movimiento vivo. Todas las bandas son neutrales; no hay puntuaciones, suspensos, rankings ni comparaciones sociales.
- La sincronización se reintenta al recuperar red, al volver a primer plano y cada 30 segundos tras un fallo mientras la app permanece activa.
- La portada usa la identidad original **Quietud**. Mantener pulsado durante tres segundos el centro dorado revela una dedicatoria privada a Eva, un corazón con destellos, la frase «Que cada pausa te recuerde cuánto mereces sonreír» y el acrónimo `Estar · Ver · Aceptar · Meditar · Observar · Regresar`. La pantalla «Sé feliz» conserva la foto de la chica como fondo y aplica encima un degradado verde oscuro para que el texto mantenga contraste. `Docs/VisualIdentity.md` documenta la paleta y `Docs/CompletionArtwork.md` documenta ambos recursos.

Antes de publicar faltan el identificador definitivo, la creación y promoción a producción del esquema CloudKit, pruebas TestFlight, revisión del nombre Ecuanimidad, soporte, política de privacidad y confirmación de derechos de distribución pública de los audios.

Documentación oficial: [CloudKit sharing](https://developer.apple.com/documentation/cloudkit/shared-records), [suscripciones de CloudKit](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription), [programa Apple Developer](https://developer.apple.com/programs/whats-included/) y [notificaciones en segundo plano](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app).
