# BVS (Basic Video Selector)

Aplicación de escritorio nativa para macOS que encuentra archivos por las cifras finales de su nombre y los copia a `Seleccionados`.

## Abrir y usar

1. Abre `BVS.xcodeproj` con Xcode.
2. Selecciona el esquema **BVS** y pulsa **Run** para iniciar la aplicación.
3. Elige una carpeta y pega cifras separadas por espacios, comas o saltos de línea.
4. Pulsa **Buscar coincidencias** y revisa la lista.
5. Opcionalmente, activa **Convertir videos compatibles a MP4** y pulsa **Procesar a “Seleccionados”**. Si la opción está desactivada, pulsa **Copiar a “Seleccionados”**.

## Añadir videos desde VLC

1. Abre VLC y empieza a reproducir un video local.
2. En BVS, pulsa **Ventana VLC** para abrir el panel flotante.
3. La primera vez, macOS puede pedir permiso para que BVS controle VLC. Permítelo en el aviso o en **Ajustes del Sistema > Privacidad y seguridad > Automatización**.
4. Pulsa **Guardar este video** en el panel o usa **⌃⌥⌘S** mientras VLC está en primer plano. Repite mientras revisas otros clips; los añadidos aparecen en la vista previa de la ventana principal y se pueden quitar con el botón menos.
5. Al terminar, copia o convierte el lote desde la ventana principal.

Si aún no elegiste una carpeta de trabajo, BVS usa la carpeta del primer video añadido desde VLC. Puedes dejar el panel junto a VLC; permanece flotante, abre dentro de la pantalla donde pulsaste **Ventana VLC**, no activa BVS al pulsar **Guardar este video** y actualiza el video actual aproximadamente una vez por segundo. El atajo **⌃⌥⌘S** se registra solo mientras VLC está en primer plano y añade el archivo actual sin abrir ni activar la ventana principal de BVS.

## Categorías y destino

- Crea categorías desde **Gestionar categorías…** antes de revisar videos. Puedes marcarlas como temporales (solo durante esta sesión) o permanentes (se conservan entre sesiones). La categoría elegida se asigna a cada video nuevo y sigue seleccionada hasta que elijas otra o **Sin categoría**.
- Al procesar, los videos con categoría se copian a `Seleccionados/[Categoría]`; los demás quedan directamente en `Seleccionados`. Quitar una categoría solo la retira del selector; no elimina videos ya procesados.
- En **Destino**, elige si `Seleccionados` se crea dentro de la carpeta de trabajo o dentro de otra carpeta que selecciones.
- Las categorías temporales se olvidan al salir de BVS. Los archivos ya procesados y sus carpetas de salida permanecen en el disco.

La búsqueda incluye archivos de cualquier formato en el nivel superior de la carpeta de trabajo. La extensión no forma parte de la comparación; por ejemplo, `CAM_20261114.MP4` coincide con `14`. No recorre subcarpetas. Al copiar, los archivos existentes con el mismo nombre se omiten y los originales se conservan. Al activar la conversión, los videos que macOS pueda convertir se guardan como MP4 con el mismo nombre base; los elementos que no son video se copian sin convertir. Si un video no es compatible, BVS lo informa y continúa con los demás. La carpeta `Seleccionados` se crea dentro de la ubicación elegida en **Destino**. Al terminar, **Mostrar en Finder** la abre directamente.

Requiere macOS 13 o posterior y Xcode para compilar el proyecto.
