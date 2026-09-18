# Línea temporal adaptable

La duración elegida es la duración **base**. Introducción, chanting y cierre caben dentro de esa base; metta extendido se añade después. El silencio ocupa automáticamente la diferencia.

Recursos actuales, incorporados el 17 de septiembre de 2026:

- Introducción: primeros **4 min 19 s** de `Day01_Morning_Chantings_Chanting_10day.mp3`.
- Metta: `Bhavatu Sabba Mangalam`, grabación completa de **72,6465306122449 s**.
- Chanting (12 s), cierre (8 s) y gong (3 s): tonos originales de prueba.

Con todas las opciones activas:

| Base | Introducción | Chanting | Silencio | Cierre | Metta | Fin real aproximado |
|---|---|---|---|---|---|---|
| 5 min | 0:00–4:19 | 4:19–4:31 | 4:31–4:52 | 4:52–5:00 | 5:00–6:12,65 | 6:13 |
| 60 min | 0:00–4:19 | 4:19–4:31 | 4:31–59:52 | 59:52–60:00 | 60:00–61:12,65 | 61:13 |
| 8 h | 0:00–4:19 | 4:19–4:31 | 4:31–7:59:52 | 7:59:52–8:00:00 | 8:00:00–8:01:12,65 | 8:01:13 |

Incluso la sesión mínima admite todos los recursos sin truncarlos. La batería de pruebas recorre cada minuto de 5 a 480 y las 16 combinaciones de audio (7.616 configuraciones), verificando las fases y su duración. Las pruebas iOS verifican la decodificación y reproducción al inicio, mitad y final de cada WAV, así como parada/reanudación rápida.

```sh
python3 Tools/describe_timeline.py 5 30 60 120 480
python3 Tools/verify_audio.py
```

Los originales de Descargas no se modifican. Los WAV de la app son PCM mono de 16 bits a 22.050 Hz. Las duraciones exactas se mantienen en `Core/Session.swift` y `iOS/Resources/AudioManifest.json`.
