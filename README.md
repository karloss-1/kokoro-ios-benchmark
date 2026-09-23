# Kokoro Benchmark

Benchmark mínimo para comprobar la carga y la síntesis local de Kokoro 82M en Safari de iPhone/iPad. Mide WASM y WebGPU cuando el navegador expone un adaptador; no es la aplicación final.

## Dependencias

- `kokoro-js` **1.2.1**: API oficial de Kokoro para navegador.
- `@huggingface/transformers` **3.8.1**: última versión estable 3.x compatible con la dependencia `^3.5.1` de Kokoro.js 1.2.1. La versión 4.x actual tiene una API mayor y no está declarada por esta versión estable de Kokoro.js.
- `vite` **8.3.0**: servidor de desarrollo y empaquetador estático.
- Dependencias resueltas por el lockfile: `phonemizer` **1.2.1** y `onnxruntime-web` **1.22.0-dev.20250409-89f8206ba4** (versión requerida por Transformers.js 3.8.1).
- CI/despliegue: pnpm **12.6.0** y Node.js **24**; el lockfile fija las versiones de la aplicación y sus dependencias.
- Modelo: `onnx-community/Kokoro-82M-v1.0-ONNX`.

Las versiones están fijadas en `package.json` y `pnpm-lock.yaml`. `onnxruntime-node` y `sharp` se omiten porque son paquetes de Node que no hacen falta en el navegador. No se necesita backend, cuenta ni servicio de TTS.

## Ejecutar

Requiere Node.js 20.19+ (se recomienda Node 24) y pnpm.

```sh
pnpm install
pnpm dev
```

Para revisar el artefacto estático:

```sh
pnpm build
pnpm preview
```

Abre la URL HTTPS publicada directamente en Safari. El motor WASM de ONNX Runtime se sirve desde los assets de este sitio. En la primera carga se descargan pesos y datos de voz desde Hugging Face. Esos archivos se ejecutan en el dispositivo; el texto de prueba no se envía a un proveedor remoto de síntesis. El navegador puede conservar archivos del modelo en su caché para cargas posteriores.

## Publicar en GitHub Pages

El workflow `.github/workflows/pages.yml` construye `dist/` y lo publica con GitHub Pages al actualizar `main` o ejecutar el workflow manualmente. En la configuración del repositorio, Pages debe tener `Build and deployment → Source: GitHub Actions`. Los assets usan rutas relativas para servir desde `https://karloss-1.github.io/kokoro-ios-benchmark/`.

## Modelos y backends

El benchmark fija el modelo `Kokoro-82M-v1.0-ONNX` para que las comparaciones sean repetibles. Las opciones visibles son las variantes que existen en el repositorio ONNX:

| Backend | Opción | Tamaño del archivo ONNX aprox. | Nota |
| --- | --- | ---: | --- |
| WASM | Q8 | 92.4 MB | Inicio recomendado en iPhone/iPad; también es la opción WASM usada por la demo oficial de Kokoro. |
| WASM | Q4 + FP16 (`q4f16`) | 154 MB | Variante ofrecida por la API/modelo; el archivo es mayor que Q8. |
| WebGPU | FP32 | 326 MB | Configuración recomendada por la demo oficial de Kokoro para WebGPU; mayor uso de memoria. |
| WebGPU | Q8 o Q4 + FP16 | 92.4 / 154 MB | Pruebas experimentales. La existencia del artefacto no garantiza que Safari/WebGPU admita todos sus operadores. |

La variante `q4` simple se omite: el archivo actual mide unos 305 MB, más que FP32 y Q8; `q4f16` es el artefacto Q4 más adecuado para comparar en móvil. Solo se carga una configuración a la vez. Al cambiarla, usa **Load model** para cerrar el worker anterior y cargar la seleccionada.

El selector de voces se llena con las voces publicadas por Kokoro.js. El modelo v1.0 usado aquí ofrece voces en inglés; por eso los textos de prueba predeterminados también están en inglés. Puedes editar el texto.

## Métricas

- **Tiempo de carga:** desde que comienza `KokoroTTS.from_pretrained()` hasta que el modelo y el tokenizador están listos. Incluye descarga si hace falta.
- **Tiempo de generación:** suma wall-clock de la preparación del texto y las llamadas secuenciales a Kokoro. Empieza después de la carga y usa `performance.now()` dentro del worker.
- **Carga de voz:** descarga o lectura de caché de los datos de voz; se prepara antes de iniciar el cronómetro de generación.
- **Duración de audio:** cantidad real de muestras PCM devueltas por el modelo dividida entre 24,000 muestras/s. No se estima desde palabras.
- **RTF:** tiempo de generación en segundos / duración real del audio. Menor que 1 significa que generó más rápido que el tiempo de reproducción.
- **Velocidad equivalente:** 1 / RTF, en múltiplos de tiempo real.
- **Tamaño:** bytes del WAV PCM de 16 bits creado a partir de las muestras devueltas.
- **Caracteres:** puntos de código Unicode, incluidos espacios. **Palabras:** fragmentos separados por espacios.

Kokoro.js no publica una API para leer el proveedor ONNX realmente elegido tras la carga. El resultado informa el **backend solicitado** y marca el **backend confirmado** como no expuesto; no presenta una solicitud WebGPU como confirmación de ejecución WebGPU.

El historial y los WAV viven en memoria de la pestaña y se borran al cerrar/recargar. No hay botón de cancelación: la API pública de `generate()` no ofrece una señal de aborto para cancelar una inferencia en curso de forma segura.

## Límites conocidos en iOS/iPadOS

- WebGPU llegó a Safari 26 en iOS/iPadOS 26. La disponibilidad real también depende de `requestAdapter()` en el dispositivo. El benchmark comprueba el adaptador y bloquea esa opción si no lo encuentra.
- Que exista el adaptador no garantiza que Kokoro y todos los operadores ONNX funcionen; las opciones WebGPU cuantizadas son experimentales. Si fallan, carga WASM Q8 para comprobar el fallback de forma explícita.
- La memoria disponible para una pestaña de Safari es limitada y iOS puede terminar o recargar el proceso. Safari no siempre expone una causa detectable. Empieza con WASM Q8 y Short, mantén la página abierta y pasa a textos largos solo después.
- `navigator.deviceMemory` no está expuesto habitualmente en Safari; la interfaz muestra que no está disponible en vez de inferirlo.
- El sitio no incluye un service worker ni se declara PWA/offline. El primer acceso requiere internet para abrir el sitio y descargar dependencias del modelo; las cargas posteriores dependen de la caché del navegador.
- La funcionalidad debe medirse en el iPhone/iPad real. Una compilación o una prueba en escritorio no valida compatibilidad en iOS.

## Referencias actuales

- [Kokoro.js](https://github.com/hexgrad/kokoro/tree/main/kokoro.js) y [demo web oficial](https://github.com/hexgrad/kokoro/tree/main/kokoro.js/demo)
- [Modelo ONNX y variantes](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX)
- [Transformers.js: tipos de datos](https://huggingface.co/docs/transformers.js/guides/dtypes) y [WebGPU](https://huggingface.co/docs/transformers.js/guides/webgpu)
- [WebKit: novedades de Safari 26.0 y WebGPU en iOS/iPadOS](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/)
