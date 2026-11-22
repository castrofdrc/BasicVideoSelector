# BVS (Basic Video Selector)

Aplicación de escritorio nativa para macOS que encuentra archivos por las cifras finales de su nombre y los copia a `Seleccionados`.

## Abrir y usar

1. Abre `BVS.xcodeproj` con Xcode.
2. Selecciona el esquema **BVS** y pulsa **Run** para iniciar la aplicación.
3. Elige una carpeta y pega cifras separadas por espacios, comas o saltos de línea.
4. Pulsa **Buscar coincidencias** y revisa la lista.
5. Opcionalmente, activa **Convertir videos compatibles a MP4** y pulsa **Procesar a “Seleccionados”**. Si la opción está desactivada, pulsa **Copiar a “Seleccionados”**.

## Flujo recomendado: seleccionar desde VLC

1. Abre VLC y empieza a reproducir un video local.
2. En BVS, deja seleccionado **VLC · recomendado** y pulsa **Abrir ventana VLC** para abrir el panel flotante.
3. La primera vez, macOS puede pedir permiso para que BVS controle VLC. Permítelo en el aviso o en **Ajustes del Sistema > Privacidad y seguridad > Automatización**.
4. Pulsa **Guardar este video** en el panel o usa **⌃⌥⌘S** mientras VLC está en primer plano para añadirlo sin categoría. También puedes asignar atajos numéricos a categorías y guardar directamente en ellas con **⌃⌥⌘1** a **⌃⌥⌘0**.
5. Al terminar, copia o convierte el lote desde la ventana principal.

Si aún no elegiste una carpeta de trabajo, BVS usa la carpeta del primer video añadido desde VLC. Puedes dejar el panel junto a VLC; permanece flotante, abre dentro de la pantalla donde pulsaste **Abrir ventana VLC**, no activa BVS al pulsar **Guardar este video** y actualiza el video actual aproximadamente una vez por segundo. Los atajos se registran solo mientras VLC está en primer plano. Asígnalos en **Configuración > Categorías**; cada número se puede vincular a una categoría. Una cifra sin asignar muestra un aviso y no guarda el video. Si una combinación ya está ocupada, BVS lo indica y mantiene activos los demás atajos. Los atajos de categorías temporales se olvidan al cerrar BVS.

La ventana principal mantiene la vista previa de los videos guardados y el botón para procesar el lote. La selección por cifras finales está disponible como método alternativo desde el selector superior.

## Categorías y destino

- Crea categorías desde **Gestionar categorías…** antes de revisar videos. Puedes marcarlas como temporales (solo durante esta sesión) o permanentes (se conservan entre sesiones). La categoría elegida se asigna a cada video nuevo y sigue seleccionada hasta que elijas otra o **Sin categoría**.
- Al procesar, los videos con categoría se copian a `Seleccionados/[Categoría]`; los demás quedan directamente en `Seleccionados`. En la vista previa puedes cambiar la categoría de cada video, incluso si lo encontraste por cifras. Quitar una categoría solo la retira del selector; no elimina videos ya procesados.
- En **Configuración** (engranaje), gestiona categorías y elige si `Seleccionados` se crea dentro de la carpeta de trabajo o dentro de otra carpeta. La ubicación elegida se conserva entre sesiones.
- Las categorías temporales se olvidan al salir de BVS. Los archivos ya procesados y sus carpetas de salida permanecen en el disco.

La búsqueda incluye archivos de cualquier formato en el nivel superior de la carpeta de trabajo. La extensión no forma parte de la comparación; por ejemplo, `CAM_20261114.MP4` coincide con `14`. No recorre subcarpetas. Al copiar, los archivos existentes con el mismo nombre se omiten y los originales se conservan. Al activar la conversión, los videos que macOS pueda convertir se guardan como MP4 con el mismo nombre base; los elementos que no son video se copian sin convertir. Si un video no es compatible, BVS lo informa y continúa con los demás. La carpeta `Seleccionados` se crea dentro de la ubicación elegida en **Destino**. Al terminar, **Mostrar en Finder** la abre directamente.

Requiere macOS 13 o posterior y Xcode para compilar el proyecto.
