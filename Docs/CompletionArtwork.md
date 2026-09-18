# Recursos visuales de finalización

La portada usa una identidad visual original llamada **Quietud**: un centro cálido sostenido por formas de piedra y dos trazos orgánicos que sugieren respiración. No representa una organización, una tradición ni un símbolo religioso. La pantalla de cierre presenta esta marca y el texto «Sé feliz» sobre la fotografía recibida, suavizada por un degradado verde oscuro que mantiene la legibilidad.

Archivos:

- Original maestro: `Design/StillnessMark-v2.png` (1254 × 1254 px).
- Pantalla de cierre y portada: `iOS/Resources/Assets.xcassets/CompletionArtwork.imageset/CompletionArtwork.png`.
- Icono adaptado a 1024 × 1024 px: `iOS/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
- Copia intacta de la foto recibida: `Design/ClosingPhoto-original.JPG` (896 × 1195 px).
- Fotografía usada como fondo de cierre: `iOS/Resources/Assets.xcassets/ClosingPhoto.imageset/ClosingPhoto.jpg`.

La marca Quietud se generó con la herramienta integrada de generación visual a partir de un encargo propio. No se utilizó como referencia ninguna aplicación, marca o ilustración existente. La fotografía fue proporcionada por el responsable del proyecto el 16 de septiembre de 2026 y se conserva sin modificaciones. Antes de publicar debe documentarse que existe autorización para usar y distribuir la imagen y la apariencia de la persona retratada.

## Sustituir los recursos más adelante

Cuando exista la imagen definitiva del usuario:

1. Para la marca, usa un PNG cuadrado de 1600 × 1600 px o más y conserva una copia maestra dentro de `Design/`.
2. Para la foto, usa un retrato vertical con espacio seguro alrededor del rostro y conserva también el original.
3. Sustituye los archivos dentro de sus respectivos image sets sin cambiar sus nombres.
4. No incorpores texto dentro de la imagen; «Sé feliz» se renderiza con tipografía del sistema y se adapta a accesibilidad.
5. Comprueba derechos de distribución, contraste y legibilidad a 64 px antes de publicar.

`Tools/generate_project.py` no dibuja ni sobrescribe estos recursos. Si falta alguno, se detiene con un error para evitar reemplazarlos silenciosamente.

## Comportamiento

- Solo aparece tras completar y guardar una sesión; cancelar no la muestra.
- Entrada suave y respiración de aproximadamente 2,6 segundos.
- Se cierra tocando, con el botón `Continuar` o automáticamente a los 7 segundos.
- Con `Reducir movimiento` no respira y la entrada dura 0,15 segundos.
