# Safari Native TTS Benchmark

Benchmark pequeño para decidir si la síntesis de voz nativa que Safari expone mediante `window.speechSynthesis` sirve para una futura experiencia de lectura en iPhone/iPad. No es la aplicación final: no contiene OCR, lectores PDF/EPUB, biblioteca, exportación de audio, almacenamiento de documentos ni PWA.

## Privacidad y funcionamiento

La página usa `SpeechSynthesisUtterance` y `speechSynthesis` del navegador; no incluye cliente, endpoint ni API de TTS. El texto se pasa al sintetizador elegido por el usuario en el sistema. Las voces cuyo `localService` sea `false` se muestran, pero Play se bloquea porque la especificación las clasifica como voces remotas y podrían enviar el texto al proveedor. `localService: true` indica un sintetizador local, pero no prueba por sí mismo que esa voz funcione offline en una situación concreta. No se guarda ni produce WAV/MP3.

## Dependencias

- **Vite 8.3.0** como herramienta de desarrollo y compilación estática.
- No hay dependencias de ejecución. Se eliminaron `kokoro-js`, Transformers.js, ONNX Runtime y los assets/modelos de inferencia.
- GitHub Actions usa Node.js 24 y pnpm 12.6.0 para construir y desplegar `dist/`.

## Ejecutar y compilar

Requiere Node.js 20.19+ (se recomienda Node 24) y pnpm:

```sh
pnpm install
pnpm dev
pnpm build
pnpm preview
```

La compilación es un sitio estático. `vite.config.js` mantiene rutas relativas para el subdirectorio de GitHub Pages. El workflow `.github/workflows/pages.yml` publica automáticamente cada push a `main`.

## Uso

1. Abre el sitio en Safari del iPhone/iPad, toca el filtro Spanish y revisa el locale reportado por cada voz. Si aparece `es-MX`, esa es la identificación regional que expuso el sistema; no se deduce el acento a partir del nombre.
2. Escucha Spanish Short y evalúa especialmente los términos anatómicos. Prueba Medium y Long con la misma voz y velocidad.
3. Usa Pause/Resume, los botones de navegación y los controles de velocidad. También puedes tocar una oración o el encabezado de un párrafo.
4. Durante Long, prueba bloqueo de pantalla y cambio a otra app. Anota si continúa, se pausa, se detiene, se reanuda o Safari recarga.
5. Compara voces cambiando la selección. Para aplicar la nueva voz durante una lectura, la página detiene la cola; vuelve a tocar Play.

El benchmark divide el texto en párrafos y oraciones. Prefiere `Intl.Segmenter` y usa un divisor sencillo de respaldo con una lista corta de abreviaturas comunes. Cada oración se envía como utterance independiente para permitir pausa/navegación y resaltar la posición. `boundary` se registra si el motor lo entrega, pero la interfaz no depende de él.

## Diagnóstico y límites

El panel muestra las propiedades recibidas de `getVoices()`, posición, `rate` solicitado, eventos recientes y errores. `voiceschanged` vuelve a poblar la lista cuando el navegador notifica cambios. Safari puede devolver una lista vacía inicialmente o no exponer todas las voces instaladas; la página vuelve a consultarla durante los primeros segundos, incluye un botón para volver a detectar y ofrece filtros Spanish, English y All. `localService` y `default` se muestran literalmente como `true`, `false` o `unavailable`.

La Web Speech API define `start`, `end`, `error`, `pause`, `resume` y `boundary`, pero una implementación solo tiene que proporcionar `boundary` si el sintetizador lo ofrece. La tasa es el valor solicitado al motor, no una medición de velocidad acústica. La API no define qué sucede con la cola si iOS oculta, suspende o termina Safari; este benchmark lo deja como prueba manual y registra cambios de visibilidad cuando Safari los notifica. Si iOS termina el proceso, la página no puede registrar por qué ocurrió. La función “Listen to Page” de Safari es una función integrada distinta y no demuestra que el TTS de esta página siga activo en segundo plano. No se presenta una prueba de escritorio como validación de iOS.

Una voz remota (`localService: false`) no se reproduce por privacidad. Una voz local (`true`) tampoco equivale a una prueba de modo avión: las implicaciones de conexión y latencia no están garantizadas por la propiedad.

## Referencias consultadas

- [WebKit: Web Speech API en Safari 14.1](https://webkit.org/blog/11648/new-webkit-features-in-safari-14-1/) (el artículo confirma que WebKit ya soportaba síntesis de voz en Safari y documenta el motor común para reconocimiento).
- [Web Speech API, especificación de Speech Synthesis](https://webaudio.github.io/web-speech-api/#speechsynthesis) (métodos, eventos, lista de voces y significado de `localService`).
- [MDN: SpeechSynthesis](https://developer.mozilla.org/en-US/docs/Web/API/SpeechSynthesis) y [SpeechSynthesisUtterance](https://developer.mozilla.org/en-US/docs/Web/API/SpeechSynthesisUtterance).
- [WebKit bug 290497: voces descargadas que no aparecen en `getVoices()`](https://bugs.webkit.org/show_bug.cgi?id=290497) (reporte abierto; describe Safari 18 en macOS, no demuestra que cada iPhone tenga el mismo problema).
- [WebKit: privacidad en Safari 26](https://webkit.org/blog/16993/news-from-wwdc25-web-technology-coming-this-fall-in-safari-26-beta/) (WebKit anunció que puede reducir la fiabilidad de la lista de voces para scripts conocidos de fingerprinting; no significa que toda página reciba una lista incompleta).
- [Apple Support: escuchar una página en Safari para iPhone](https://support.apple.com/en-us/guide/iphone/iph449fc616c/ios) (función del lector integrado de Safari, distinta de esta prueba Web Speech).

La pregunta final —calidad de la voz, continuidad real en background y estabilidad en textos largos— solo puede contestarse probándolo en el iPhone/iPad objetivo.
