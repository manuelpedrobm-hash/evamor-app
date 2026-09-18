# Catálogo remoto de audios

Después de instalar esta versión, Ecuanimidad puede recibir audios y perfiles nuevos sin actualizarse desde App Store. La aplicación descarga un `catalog.json` mediante HTTPS, verifica el tamaño, el hash SHA-256 y la duración de cada audio, y guarda una copia local para usarla sin conexión. Si una actualización falla, conserva el catálogo y los archivos anteriores.

## Publicar un catálogo

1. Copia `Docs/AudioCatalogSource.example.json` y añade un elemento por audio. Cada `id` debe ser permanente y único.
2. Indica la duración real en segundos y una ruta local en `sourceFile`.
3. Genera la carpeta publicable:

```sh
python3 Tools/prepare_audio_catalog.py mi-catalogo.json PublicAudio \
  --base-url https://audio.example.com/evamor
```

4. Sube todo el contenido de `PublicAudio` al mismo alojamiento HTTPS. El servidor debe entregar los archivos sin autenticación y aceptar descargas completas.
5. En Ecuanimidad abre **Ajustes → Audios y perfiles → Abrir catálogo**, pega la URL terminada en `/catalog.json` y pulsa **Guardar y actualizar**.

Para que todos los usuarios reciban el catálogo sin configurarlo manualmente, define `EvamorAudioCatalogURL` en `iOS/Info.plist` antes de la primera publicación. Después, basta con sustituir el catálogo y añadir archivos en el servidor.

## Actualizaciones seguras

- No reutilices un `id` para una grabación distinta salvo que quieras sustituirla expresamente.
- Incrementa `revision` en cada publicación.
- Mantén disponibles los archivos antiguos mientras haya perfiles que los referencien.
- El catálogo solo acepta HTTPS, un máximo de 2 MB de JSON, identificadores únicos y hashes SHA-256 de 64 caracteres.
- El audio se activa únicamente si tamaño, hash y duración coinciden. Una descarga incompleta o modificada se descarta.
- La URL del catálogo identifica la dirección IP del dispositivo ante el proveedor de alojamiento. Debe mencionarse en la política de privacidad si el proveedor conserva registros.

Los hashes evitan activar archivos corruptos o distintos de los declarados. La seguridad del catálogo depende además de HTTPS y del control de la cuenta de alojamiento. Antes de una distribución amplia conviene añadir firma asimétrica del catálogo y fijar su clave pública en la aplicación.
