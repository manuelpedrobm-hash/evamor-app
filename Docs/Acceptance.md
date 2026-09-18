# Aceptación en dispositivo

Registra versión de iOS, modelo, build, cuentas iCloud y resultado. Usa dos iPhones reales; el simulador no valida APNs ni el flujo completo de compartir.

## Local

- Completar, pausar, reanudar y terminar antes una sesión en modo avión.
- Probar los presets de 5 minutos, 1, 2, 4, 6 y 8 horas; confirmar que el cierre empieza al final de la duración base.
- En la portada, tocar 5, 15, 30 y 60 minutos; confirmar que cambia el resumen, persiste al reiniciar y que `Meditar` usa esa duración.
- Bloquear el teléfono durante silencio y abrirlo después del plazo.
- Interrumpir con llamada, Siri y desconexión de auriculares.
- Confirmar una sola sesión tras reaperturas. Al terminar antes, debe guardarse una práctica parcial con el tiempo real y previsto; suma minutos pero no sesión completa, racha ni hito.
- Al completar, comprobar «Sé feliz», cierre por toque/botón y cierre automático. Al terminar antes, comprobar «Práctica guardada» y que no se crea ningún aviso para amigos.
- En ambas pantallas de cierre, confirmar que la fotografía sigue visible bajo el degradado y que texto y botones conservan contraste en modo claro, oscuro y con Texto grande.
- Activar `Reducir movimiento` y confirmar que la ilustración no pulsa.
- Probar medianoche, 12:00, cambio de zona y cambio de hora.
- Completar una sesión de mañana y otra de noche: el indicador semanal muestra ambos puntos; comprobar además su lectura con VoiceOver.
- Crear una cadena de tres días, dejar un día vacío y abrir al siguiente: el Hilo debe indicar que aún puede recuperarse. Completar una sesión y verificar que las cuentas enlazadas aumentan una sola vez.
- Introducir una segunda pausa en el mismo hilo: debe comenzar un hilo nuevo sin borrar sesiones, minutos ni historial anteriores.

## iCloud y sincronización

- Completar offline y recuperar conexión: aparece una vez en iCloud y en un segundo dispositivo del mismo usuario.
- Desactivar compartir antes de recuperar conexión: se sube al historial privado sin señal social.
- Cerrar sesión de iCloud o desactivar iCloud Drive: lo local sigue disponible y la cola permanece.
- Probar respuesta perdida y varios reintentos: UUID único y operación eliminada solo tras éxito.

## Amigos y avisos

- A comparte su canal con B mediante la interfaz privada de iCloud; B acepta y aparece como canal entrante.
- B comparte su canal con A y se comprueba la relación recíproca.
- Con envío/recepción activos, completar por la mañana en A: B recibe «Un amigo ha completado su meditación matutina y te envía metta.» sin nombre ni duración. Repetir por la tarde.
- Completar dos sesiones diferentes en A: B debe recuperar dos identificadores distintos; si llegan juntas, puede mostrar un único resumen que indica dos meditaciones, pero ambas quedan marcadas como recibidas.
- Terminar una práctica antes en A con compartir activo: se sincroniza en el historial privado de A y B no recibe ninguna señal.
- Silenciar A en B: las nuevas señales se consumen sin mostrar aviso; al reactivar no reaparecen.
- Desactivar todos los avisos sociales: se elimina la suscripción y los avisos locales sociales.
- Completar varias sesiones offline: al sincronizar, B recibe como máximo un resumen por procesamiento y amigo.
- Retirar acceso y abandonar canal; verificar que desaparecen al refrescar.
- Abrir una invitación reenviada a una cuenta no invitada: no obtiene acceso.
- Meditar mientras llega un push social: no se presenta dentro de la sesión activa.
- Impedir la actualización en segundo plano, completar en A y abrir después B: el aviso pendiente se recupera una sola vez.
- Recibir una señal durante una sesión activa en B: debe quedar pendiente y aparecer después de finalizar, nunca encima del temporizador.

## Condiciones de iOS

Prueba con bajo consumo, actualización en segundo plano desactivada, app forzada a cerrar, Concentración y notificaciones denegadas. Documenta retrasos: CloudKit y APNs no prometen despertar la app para cada push silencioso.
