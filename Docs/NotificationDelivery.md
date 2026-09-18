# Entrega de avisos sociales

## Condiciones necesarias

El receptor verá un aviso cuando se cumplan todas:

1. Ambos dispositivos ejecutan la misma aplicación firmada con el mismo contenedor CloudKit.
2. Cada persona usa una cuenta iCloud activa.
3. El receptor aceptó el canal privado del remitente.
4. El remitente tenía `Compartir mis sesiones` activo al completar y sigue activo al sincronizar.
5. El receptor tiene `Recibir avisos de amigos` activo, permiso del sistema y ese amigo sin silenciar.
6. iOS concede ejecución al push silencioso. Si no lo hace, la app recupera el evento al siguiente arranque o al volver a primer plano.

## Qué se envía

La señal compartida contiene `eventID`, `completedAt` y la franja mañana/tarde. El aviso mostrado dice «Un amigo ha completado su meditación matutina y te envía metta» o su variante de tarde. No incluye nombre, duración, estadística, configuración ni audio.

## Matriz de comportamiento

| Remitente comparte | Receptor recibe | Amigo silenciado | Resultado |
|---|---|---|---|
| No | Cualquiera | Cualquiera | No se crea señal social. |
| Sí | No | Cualquiera | La señal puede sincronizarse, pero el receptor no mantiene la suscripción ni muestra aviso. |
| Sí | Sí | Sí | La señal se marca como vista sin aviso. |
| Sí | Sí | No | Se crea un aviso cuando iOS procesa el push. |

Varias sesiones disponibles en un mismo procesamiento producen un resumen por amigo. Cada `eventID` se registra localmente antes de mostrarlo; reintentar la sincronización no vuelve a avisar.

Si una señal llega durante una meditación activa, no se marca como vista ni se presenta. Al completar o cancelar la práctica, el siguiente procesamiento puede mostrarla sin interrumpir la sesión.

## Diagnóstico en el dispositivo

En **Amigos → Estado** se muestran iCloud, canales recibidos y personas que reciben. En **Ajustes → Sincronización** aparecen el permiso de notificaciones y la cola pendiente. **Probar aviso en este iPhone** valida el permiso y el texto local sin necesitar otro usuario. Después debe realizarse la prueba completa A → B con dos iPhones y Apple ID distintos.

Un push silencioso no es una garantía de entrega inmediata. Bajo consumo, actualización en segundo plano desactivada, app forzada a cerrar o decisiones de energía de iOS pueden retrasar o impedir el despertar. La sesión y su sincronización privada no se pierden por ello; el aviso se recupera cuando la app vuelve a ejecutarse.
