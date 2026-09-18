# Estado de verificación

## Revisión del 17 de septiembre de 2026

- Nombre visible cambiado a «Ecuanimidad» sin añadir texto sobre el símbolo en la portada. EVAMOR queda solo en la dedicatoria oculta. Las duraciones rápidas 5, 15, 30 y 60 siempre responden, persisten y retiran un audio largo si no cabe.
- Permanecer conserva cámara, timelapse y Pulso de quietud. La fotografía se mantiene en el cierre bajo un degradado que protege la legibilidad. El vídeo puede durar 10, 20 o 30 segundos, el análisis de movimiento es opcional y existen borrado automático y borrado en grupo.
- Al bloquear el iPhone, la cámara se detiene por la política de iOS; la sesión usa su reloj persistido, mantiene el audio en curso y programa el aviso final. Al volver, la captura se reanuda si el proceso sigue vivo.
- Introducción 0:00–4:19 y Bhavatu completo validados. Los dos Group Sitting recibidos eran AAC/MP4 con extensión `.mp3` errónea; se incorporaron sin recomprimir como M4A reproducibles, con perfiles de 65 y 66 minutos.
- El catálogo HTTPS admite audios y perfiles nuevos sin actualizar la app. Comprueba esquema, tamaño, SHA-256 y duración, conserva caché sin conexión y mantiene el catálogo anterior ante un fallo.
- Perfiles personales, preescucha y descarga bajo demanda probados. Los dos audios incluidos se abren con AVAudioPlayer y coinciden con su metadato y hash.
- Cada timelapse muestra una de 22 frases del Dhammapada en pali, traducción española y referencia. La selección varía por archivo y permanece estable al volver a abrirlo.
- Terminar antes guarda una práctica parcial con el tiempo real y el previsto. Sus minutos aparecen en el historial y el resumen semanal, pero no altera sesiones completas, rachas, hitos ni avisos sociales. El formato anterior del historial sigue siendo compatible.
- Acceso de antiguos alumnos probado con rechazo de credenciales erróneas, aceptación de las correctas, hash local y salida desde Ajustes. La contraseña no se persiste.
- Amigos: señales mínimas con franja mañana/tarde, invitaciones privadas de solo lectura, deduplicación, descarte de eventos previos a la amistad, silencio individual, agrupación y textos exactos de metta cubiertos por pruebas. La pantalla muestra el estado de canales entrantes y salientes.
- Cada sesión completada crea su propia solicitud de señal social cuando compartir está activo. Las prácticas parciales pasan a iCloud privado y se bloquean en la cola y de nuevo en CloudService antes de crear señales.
- UX: bienvenida con progreso, acción Meditar destacada, perfiles preparados para reducir decisiones, progreso circular durante la sesión y cierre «Sé feliz» con frase pali opcional en el timelapse.

## Resultados automatizados

- `xcodebuild test`: 35 pruebas unitarias/integración aprobadas. Cubren 7.616 combinaciones de minuto/audio, persistencia, reproducción, catálogo, perfiles, acceso, prácticas parciales, una señal por cada sesión completada, amigos, borrado de timelapses, pali y sincronización.
- Dos pruebas de interfaz cubren el acceso de antiguo alumno y el recorrido bienvenida → duraciones rápidas → configuración → sesión → pausa/reanudación → guardado parcial.
- `Tools/verify_project.py`: 85 comprobaciones estáticas de capacidades, privacidad, social, catálogo, acceso, audio, prácticas parciales y timelapse.
- `Tools/verify_audio.py` y `Tools/verify_catalog.py`: formato, duración, tamaño y SHA-256 de los siete recursos de audio.
- `Tools/verify_core.py`: pruebas portables del núcleo fuera de Xcode.
- El target completo `Meditacion` compiló correctamente en Release para un iPhone genérico con CloudKit, APNs, iCloud sharing y audio en segundo plano configurados.
- La versión 0.4.0 (4) del target `Evamor Local`, con nombre visible «Ecuanimidad», se compiló con firma Apple Development, se instaló y se abrió correctamente en el iPhone 13 Pro conectado. Esta variante personal no incluye CloudKit ni APNs.

Los avisos `AVAudioSession Hang Risk`, teclado y diagnóstico `simctl` proceden del runtime del simulador. No han causado fallos de prueba; la reproducción también debe escucharse en un iPhone físico antes de distribuir.

## Pendiente de infraestructura o dispositivo real

- Obtener autorización escrita para redistribuir todas las grabaciones protegidas.
- Crear el contenedor CloudKit definitivo, desplegar el esquema a Production y comprobar Amigos A → B con dos iPhones y Apple ID diferentes. El simulador desactiva CloudKit y no valida APNs.
- Probar cámara, orientación, bloqueo, llamadas, auriculares, batería y sesiones largas en varios iPhone.
- Entregar las credenciales compartidas a App Review y completar TestFlight, metadatos, soporte y política de privacidad pública.

No se desplegó un backend, alojamiento de catálogo ni esquema CloudKit de producción desde este entorno.

## Actualización del 17 de septiembre de 2026 (tarde)

- El target `Meditacion` (el que se publicará, con CloudKit/APNs) no tenía `DEVELOPMENT_TEAM` ni `CODE_SIGN_STYLE`: solo compilaba en Release "para iPhone genérico" sin firmar y nunca se había instalado en un dispositivo físico. Se añadió `CODE_SIGN_STYLE = Automatic` y `DEVELOPMENT_TEAM = X5MB743UFG` (mismo equipo que ya usaba `Evamor Local`) a `Meditacion`, `MeditacionTests` y `DhammaUITests`, para poder instalarlo y ejecutar la batería de pruebas en un iPhone real, no solo en simulador.
- Se confirmó que `Meditacion` y `Evamor Local` compilan exactamente los mismos 19 archivos Swift y los mismos recursos (mismo `Info.plist`, mismo `Assets.xcassets`, mismos audios): no existen dos copias del código. La única diferencia de código es una condición de compilación (`EVAMOR_LOCAL`, usada solo en `CloudService.swift:47`) que desactiva el contenedor CloudKit en la variante personal y en el simulador. Los 35 tests unitarios/integración y los 2 de interfaz ya corrían con `TEST_HOST`/`TEST_TARGET_NAME` apuntando a `Meditacion.app`, no a `Evamor Local`.
- Tras el cambio de firma se repitió toda la verificación disponible en este entorno: `Tools/verify_audio.py` y `Tools/verify_catalog.py` (7 audios, hash/duración correctos), `Tools/verify_project.py` (85/85), `Tools/verify_core.py` (99.145 aserciones) y `Tools/xcode_verify.sh --test` (build + 35 tests + 2 UI tests) sobre el scheme `Meditacion` en simulador: todo en verde.

### Actualización del 18 de septiembre de 2026

`group-long.m4a` y `group-short.m4a` (~127 MB) dejaron de declararse como `bundledResource` y se eliminaron de `iOS/Resources/`: `iOS/Resources/AudioCatalog.json` ahora tiene `tracks`/`profiles` vacíos y el proyecto se regeneró con `Tools/generate_project.py`. Los cinco Group Sitting disponibles (los dos anteriores más Giri/Igatpuri, Setu/Chennai y Shikhara/Dharamshala, tres grabaciones nuevas) se sirven exclusivamente desde `https://manuelpedrobm-hash.github.io/evamor-audio/catalog.json`, publicado en un repositorio público de GitHub Pages con el mismo patrón que `evamor-privacidad`/`evamor-soporte`. Verificado por hash sobre HTTPS tras publicar. `Tools/verify_project.py` (85/85) y `Tools/verify_catalog.py`/`Tools/verify_audio.py` siguen en verde tras el cambio.

Contrapartida: la app ya no trae ningún Group Sitting disponible sin conexión desde la primera instalación; el primer uso de cada uno requiere red para descargarlo (con verificación de tamaño/hash/duración, como el resto del catálogo remoto).
