# Prueba real de avisos entre amigos

## Estado de esta copia

- La rama de trabajo es `codex/timelapse-local-audio`. El timelapse y el permiso de cámara se han retirado. Los metadatos de vídeos de instalaciones anteriores permanecen en la base local para que la actualización no borre datos antiguos.
- `Evamor Local` (`com.manuelbecerril.evamor.local`) sirve para probar audio en el iPhone de Manuel, pero **no usa CloudKit**.
- `Meditacion` (`com.manuelbecerril.evamor`) es el target con CloudKit y APNs. El equipo personal configurado en este Mac no puede firmarlo: Xcode indica que los equipos personales no admiten iCloud ni Push Notifications. Hace falta seleccionar un equipo del Apple Developer Program con esas capacidades.

## Preparar dos iPhone en Desarrollo

1. En Xcode, abrir `Meditacion.xcodeproj`, escoger el esquema **Meditacion** y un equipo de desarrollo de pago en *Signing & Capabilities* con firma automática. Confirmar iCloud → CloudKit, Push Notifications y Background Modes → Remote notifications y Audio. El contenedor configurado es `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`. Si el equipo no puede registrar `com.manuelbecerril.evamor`, usar un Bundle ID propio y el contenedor correspondiente en los dos teléfonos.
2. Compilar e instalar **el mismo target, Bundle ID, equipo y contenedor** en dos iPhone físicos. A y B deben iniciar sesión con **cuentas de iCloud distintas**, con iCloud Drive disponible. No usar `Evamor Local` para esta prueba. La app de iCloud puede coexistir con la local porque tiene otro Bundle ID.
3. Abrir la app en ambos. En **Ajustes → Sincronización**, confirmar `iCloud: Disponible`. En B, tocar **Probar aviso en este iPhone** y aceptar el permiso de notificaciones. Ese botón prueba solo el aviso local, no el circuito entre amigos.
4. En A, tocar **Preparar canal de amigos en iCloud**; debe salir «Canal privado preparado en iCloud». Esto crea `PracticeChannel` y su `CKShare` en el contenedor de desarrollo. Activar **Compartir mis sesiones**. En B, activar **Recibir avisos de amigos**. En **Amigos** de A, crear una invitación privada y enviarla a la cuenta iCloud de B. B abre el enlace y acepta. En B debe aparecer A como canal recibido; en A, B como participante aceptado. Sin esta invitación, no hay aviso.
5. En A, elegir una práctica de **5 minutos** y completarla entera, sin terminar antes. Al finalizar, entrar en **Ajustes → Sincronización** y comprobar que `Pendientes` llega a 0; tocar **Sincronizar ahora** si hace falta.
6. B debería recibir «Un amigo ha completado su meditación matutina y te envía metta» (o la versión de tarde). Si no aparece de inmediato, abrir B, tocar **Sincronizar ahora** y revisar **Amigos → Estado**, el permiso de notificaciones, Concentración y que A no esté silenciado. Los pushes silenciosos de iOS no garantizan entrega inmediata.
7. Para probar B → A, repetir en sentido inverso: B debe activar compartir, enviar **su propia invitación** a A y A debe activar recibir. Una invitación A → B no habilita automáticamente la dirección contraria.

## Qué registros crea la app

No hay que escribir registros a mano en CloudKit Console. La app los crea al usarla en el entorno **Development**: `PracticeChannel` y su `CKShare` con el botón de preparación o al preparar la invitación; `MeditationSession` al sincronizar una práctica; `PracticeSignal` al sincronizar una práctica completa compartida. La señal contiene solo identificador del evento, hora de finalización y franja mañana/tarde. En CloudKit Console se puede comprobar que existen los tres tipos y los registros correspondientes.

## Después, TestFlight

Tras comprobar el flujo en Development, desplegar el esquema de CloudKit de **Development a Production** en CloudKit Console. Compilar/archivar `Meditacion` en Release con el mismo contenedor y subirlo a TestFlight. Instalar esa versión en los dos iPhone y crear **invitaciones nuevas**: los datos e invitaciones de Development no pasan a Production. No hacer este paso hasta haber superado la prueba anterior.

La prueba real sigue pendiente hasta disponer del equipo de Apple Developer con CloudKit/APNs y del segundo iPhone. Un simulador o el botón de aviso local no sustituyen la comprobación A → B.
