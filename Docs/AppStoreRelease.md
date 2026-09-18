# Preparación para App Store

## Listo en el proyecto

- Datos locales con SwiftData, funcionamiento sin conexión y restauración del temporizador.
- Catálogo HTTPS con caché, validación de tamaño, SHA-256 y duración.
- Declaración de privacidad sin seguimiento ni publicidad.
- Exportación y borrado del historial.
- Avisos sociales mínimos sin nombre, duración ni selección de audio.
- Compatibilidad con texto grande, VoiceOver y Reducir movimiento en los flujos principales.
- Puerta local para antiguos alumnos; solo conserva el acceso concedido y no guarda la contraseña.

## Bloqueos antes de enviar a revisión

1. ~~Obtener autorización escrita para editar, incorporar y redistribuir cada grabación de S. N. Goenka.~~ Resuelto: el usuario confirma (17 de septiembre de 2026) que ya cuenta con esa autorización. Conviene guardar el documento/correo de la autorización junto al proyecto por si App Review lo solicita.
2. ~~Elegir el identificador y equipo de distribución definitivos y subir iconos, capturas, descripción, categoría, soporte y política de privacidad en App Store Connect.~~ Textos, capturas a 1320×2868 (6,9"), icono, soporte y privacidad ya listos — ver [AppStoreListing.md](AppStoreListing.md). Política: <https://manuelpedrobm-hash.github.io/evamor-privacidad/>. Soporte: <https://manuelpedrobm-hash.github.io/evamor-soporte/>. Solo falta pegarlo en App Store Connect el día que exista la ficha (paso 6 del guion de abajo), y decidir el identificador/equipo definitivo si al final no es este del amigo.
3. ~~Configurar una URL HTTPS definitiva para el catálogo y publicar su política de conservación de logs.~~ Resuelto: catálogo publicado en `https://manuelpedrobm-hash.github.io/evamor-audio/catalog.json` (repositorio público `manuelpedrobm-hash/evamor-audio`, GitHub Pages). Los cinco Group Sitting ya no van embebidos en el binario. El registro de acceso lo cubre la política de privacidad de GitHub Pages, no una propia.
4. Crear el contenedor CloudKit definitivo, desplegar el esquema en producción y probar invitaciones con dos Apple ID reales.
5. Probar bloqueo, llamadas, auriculares, batería y sesiones de ocho horas en varios iPhone físicos.
6. Distribuir mediante TestFlight y resolver los informes antes de producción.
7. Entregar a App Review las credenciales de acceso compartidas en las notas de revisión. Si se necesita verificar individualmente a cada alumno, sustituir la puerta local por un servicio de cuentas antes del lanzamiento.

## Guion con la cuenta prestada (equipo de pago de un tercero)

Pensado para el día en que ya tengas acceso a una cuenta Apple Developer Program de pago (propia o prestada por alguien).

1. **Antes de nada, que te añadan como miembro** (no compartir contraseña):
   - En [developer.apple.com/account](https://developer.apple.com/account) → **People** → invitar tu Apple ID.
   - En [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Users and Access** → invitar tu Apple ID también ahí.
   - Acepta las invitaciones que te lleguen por correo.
2. **En tu Mac:** Xcode → Settings (⌘,) → Accounts → añade tu Apple ID si no está. Debería aparecer el nuevo equipo (no "Personal Team").
3. **Dime el Team ID nuevo** (aparece junto al nombre del equipo en esa pantalla, o en developer.apple.com/account → Membership). Con eso sustituyo `X5MB743UFG` por el equipo real en `Meditacion`, `MeditacionTests` y `DhammaUITests` dentro del proyecto.
4. **"Cebar" el esquema de CloudKit en Development** abriendo el target `Meditacion` (no `Evamor Local`) en tu iPhone y, una sola vez: activar "Compartir mis sesiones", generar una invitación desde Amigos, completar una sesión compartida, y activar "Recibir avisos de amigos". Esto crea en Development los tipos `MeditationSession`, `PracticeChannel`, `PracticeSignal` y la suscripción — el siguiente paso solo copia lo que exista aquí.
5. **Desplegar a Production:** en [icloud.developer.apple.com](https://icloud.developer.apple.com) → el contenedor `iCloud.com.manuelbecerril.evamor` → Schema → **Deploy Schema to Production**.
6. **Subir a TestFlight:** en Xcode, con el scheme `Meditacion` y "Any iOS Device" seleccionado, Product → Archive → Distribute App → App Store Connect → Upload. La primera vez, App Store Connect pedirá crear la ficha de la app (nombre, bundle ID `com.manuelbecerril.evamor`, categoría).
7. **Invitar a un segundo probador** (puede ser el mismo amigo u otra persona) en App Store Connect → TestFlight → añadir su email como probador externo. Instala la app en su iPhone con su propio Apple ID y repetís la prueba Amigos A → B descrita en `Docs/NotificationDelivery.md`.

Ningún paso de este guion tiene coste adicional una vez alguien ya paga la membresía: CloudKit, TestFlight y las notificaciones push son gratuitas dentro de esa membresía.
