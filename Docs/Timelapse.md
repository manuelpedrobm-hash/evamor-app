# Permanecer: timelapse privado

La opción está desactivada inicialmente. Al activarla, Ecuanimidad solicita la cámara frontal únicamente cuando la persona pulsa `Meditar`, presenta un encuadre y no inicia la sesión hasta confirmar. No se configura ninguna entrada de micrófono.

La grabación no crea primero un vídeo de una hora. Se seleccionan fotogramas durante la práctica y se escriben directamente a 30 fps en un MP4 H.264 local. Una sesión de 5 minutos produce aproximadamente 10 segundos; las duraciones mayores ajustan el intervalo para mantener el resultado alrededor de 30 segundos como máximo.

## Pulso de quietud

Vision detecta puntos corporales en los fotogramas muestreados y calcula el cambio medio entre posturas visibles. Las coordenadas se desechan en memoria. Solo se guarda un resumen agregado junto al nombre local del vídeo.

Las salidas son deliberadamente no competitivas:

- `Quietud sostenida`
- `Ajustes suaves`
- `Movimiento vivo`
- `Práctica presente`, cuando faltan observaciones suficientes

No se denomina puntuación de anicca ni de ecuanimidad. La inmovilidad externa no prueba un estado mental y moverse no invalida una sesión.

## Límites

- iOS no mantiene la cámara activa con la app en segundo plano o el teléfono bloqueado. Ecuanimidad detiene únicamente la captura: el reloj, el audio y el aviso final continúan. Al volver, reanuda la captura si el proceso sigue vivo; si iOS terminó la app, restaura la sesión desde el tiempo persistido y descarta el vídeo incompleto.
- Un encuadre oscuro, ropa poco contrastada o un cuerpo parcialmente visible reducen la detección.
- El resultado no se sincroniza con CloudKit ni se incluye en señales sociales.
- La hoja de compartir aparece solo tras una acción de la persona.
