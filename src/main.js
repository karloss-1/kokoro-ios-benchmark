import "./style.css";

const MODEL_ID = "onnx-community/Kokoro-82M-v1.0-ONNX";
const MODEL_OPTIONS = {
  wasm: [
    { dtype: "q8", title: "Q8 · 92.4 MB", description: "Cuantización de 8 bits; opción WASM recomendada por la demo oficial." },
    { dtype: "q4f16", title: "Q4 + FP16 · 154 MB", description: "Cuatro bits con pesos FP16. El archivo es mayor que Q8; útil para comparar cuantización." },
  ],
  webgpu: [
    { dtype: "fp32", title: "FP32 · 326 MB · recomendado", description: "La demo oficial de Kokoro usa FP32 con WebGPU. Es la variante más pesada." },
    { dtype: "q8", title: "Q8 · 92.4 MB · experimental", description: "El paquete y el modelo ofrecen Q8; Kokoro no lo recomienda para WebGPU, puede fallar." },
    { dtype: "q4f16", title: "Q4 + FP16 · 154 MB · experimental", description: "Disponible en el modelo; el uso con WebGPU depende de los operadores que admita Safari." },
  ],
};

const TESTS = {
  short: {
    name: "Short",
    text: "A reliable benchmark measures real work on the device. First, Kokoro loads its model weights; then it turns this short paragraph into speech. The audio duration comes from the generated samples, so the real-time factor reflects the actual result.",
  },
  medium: {
    name: "Medium",
    text: "This medium test checks whether local speech generation remains steady across several sentences. The benchmark divides the text into safe pieces, synthesizes each piece in sequence, and joins the audio before measuring its duration. Loading and generation are timed separately. A warm run may load faster when Safari has cached the model files, while synthesis time still depends on the selected backend, device temperature, available memory, and other work running on the phone or tablet. Listen to the result and compare the real-time factor with the other backend and quantization settings. The same text and voice make those comparisons easier to interpret.",
  },
  long: {
    name: "Long",
    text: "This longer test is intended to put more sustained work on the device without turning the benchmark into an unusually large download or a multi-hour task. Kokoro processes this passage as a sequence of short sections, so no single request exceeds the model's input window. The page keeps every generated audio section in memory until it can join them into one playable WAV file. That means a longer passage also uses more memory for the final audio. If Safari reloads the page, the app can report that an operation was in progress, but iOS does not reliably tell a web page why its process ended. Keep the screen awake during a run and begin with the short test after loading a new model. When that works, try this passage and note whether the output plays through, how long synthesis takes, and whether the browser remains responsive. For a fair comparison, load one backend and quantization at a time, then reuse this exact passage and voice. The generation timer includes text preparation and all sequential synthesis calls, but excludes model download and loading. The audio duration is measured from the number of PCM samples returned by Kokoro at its documented sample rate. No duration is estimated from the word count. A result below one real-time factor generated faster than playback; a result above one took longer than the resulting audio would take to play.",
  },
};

const $ = (selector) => document.querySelector(selector);
const els = {
  status: $("#app-status"),
  statusText: $("#status-text"),
  webgpuBadge: $("#webgpu-badge"),
  userAgent: $("#user-agent"),
  webgpuStatus: $("#webgpu-status"),
  selectedBackend: $("#selected-backend"),
  selectedModel: $("#selected-model"),
  hardwareConcurrency: $("#hardware-concurrency"),
  deviceMemory: $("#device-memory"),
  backendButtons: [...document.querySelectorAll("[data-backend]")],
  backendNote: $("#backend-note"),
  quantization: $("#quantization"),
  quantizationNote: $("#quantization-note"),
  voice: $("#voice"),
  testButtons: [...document.querySelectorAll("[data-test]")],
  text: $("#test-text"),
  textCount: $("#text-count"),
  modelState: $("#model-state"),
  loadButton: $("#load-button"),
  generateButton: $("#generate-button"),
  progressRegion: $("#progress-region"),
  progressBar: $("#progress-bar"),
  progressText: $("#progress-text"),
  latestSection: $("#latest-section"),
  latestResult: $("#latest-result"),
  resultStatus: $("#result-status"),
  historySection: $("#history-section"),
  historyList: $("#history-list"),
  clearHistory: $("#clear-history"),
  toast: $("#toast"),
};

const state = {
  webgpu: { checked: false, available: false, reason: "" },
  backend: "wasm",
  dtype: "q8",
  worker: null,
  loadedConfig: null,
  loadMs: null,
  busy: false,
  results: [],
  currentTest: "short",
  toastTimer: null,
  latestLoadProgress: null,
};

function currentConfig() {
  return { backend: state.backend, dtype: state.dtype, modelId: MODEL_ID };
}

function sameConfig(a, b) {
  return Boolean(a && b && a.backend === b.backend && a.dtype === b.dtype && a.modelId === b.modelId);
}

function boot() {
  els.userAgent.textContent = navigator.userAgent || "No expuesto";
  els.hardwareConcurrency.textContent = Number.isFinite(navigator.hardwareConcurrency)
    ? `${navigator.hardwareConcurrency} hilos lógicos`
    : "No expuesto por el navegador";
  els.deviceMemory.textContent = Number.isFinite(navigator.deviceMemory)
    ? `${navigator.deviceMemory} GB (aprox.)`
    : "No expuesto por el navegador";
  setTest("short");
  renderQuantizationOptions();
  updateDeviceInfo();
  renderWebGPUState();
  checkWebGPU();
  checkInterruptedOperation();
  bindEvents();
}

async function checkWebGPU() {
  const gpu = navigator.gpu;
  if (!gpu || typeof gpu.requestAdapter !== "function") {
    state.webgpu = { checked: true, available: false, reason: "navigator.gpu no está disponible" };
    renderWebGPUState();
    return;
  }

  try {
    const adapter = await gpu.requestAdapter();
    state.webgpu = adapter
      ? { checked: true, available: true, reason: "Adaptador WebGPU disponible" }
      : { checked: true, available: false, reason: "Safari no devolvió un adaptador WebGPU" };
  } catch (error) {
    state.webgpu = { checked: true, available: false, reason: error?.message || "Falló requestAdapter()" };
    console.warn("[Kokoro Benchmark] WebGPU adapter check failed", error);
  }
  renderWebGPUState();
}

function renderWebGPUState() {
  const gpuButton = els.backendButtons.find((button) => button.dataset.backend === "webgpu");
  gpuButton.disabled = !state.webgpu.checked || !state.webgpu.available || state.busy;
  if (!state.webgpu.checked) {
    els.webgpuStatus.textContent = "Comprobando adaptador…";
    els.webgpuBadge.textContent = "WebGPU: comprobando";
    els.webgpuBadge.className = "badge pending";
    return;
  }
  if (state.webgpu.available) {
    els.webgpuStatus.textContent = "Sí · adaptador disponible";
    els.webgpuBadge.textContent = "WebGPU: disponible";
    els.webgpuBadge.className = "badge success";
  } else {
    const reason = state.webgpu.reason || "Sin adaptador WebGPU";
    els.webgpuStatus.textContent = `No · ${reason}`;
    els.webgpuBadge.textContent = "WebGPU: no disponible";
    els.webgpuBadge.className = "badge warning";
  }
}

function bindEvents() {
  els.backendButtons.forEach((button) => {
    button.addEventListener("click", () => setBackend(button.dataset.backend));
  });
  els.quantization.addEventListener("change", () => {
    state.dtype = els.quantization.value;
    const choice = MODEL_OPTIONS[state.backend].find((option) => option.dtype === state.dtype);
    if (choice) els.quantizationNote.textContent = choice.description;
    updateDeviceInfo();
    updateModelState();
  });
  els.voice.addEventListener("change", updateGenerateButton);
  els.testButtons.forEach((button) => button.addEventListener("click", () => setTest(button.dataset.test)));
  els.text.addEventListener("input", () => {
    state.currentTest = null;
    setSelectedTest(null);
    updateTextCount();
    updateGenerateButton();
  });
  els.loadButton.addEventListener("click", loadModel);
  els.generateButton.addEventListener("click", generate);
  els.clearHistory.addEventListener("click", clearHistory);
  window.addEventListener("pagehide", () => {
    if (state.worker && state.busy) sessionStorage.setItem("kokoro-benchmark-pending", "1");
  });
}

function setBackend(backend) {
  if (state.busy || (backend === "webgpu" && !state.webgpu.available)) return;
  state.backend = backend;
  const options = MODEL_OPTIONS[backend];
  state.dtype = options[0].dtype;
  els.backendButtons.forEach((button) => {
    const selected = button.dataset.backend === backend;
    button.classList.toggle("is-selected", selected);
    button.setAttribute("aria-pressed", String(selected));
  });
  els.backendNote.textContent = backend === "webgpu"
    ? "Kokoro recomienda FP32. Las cuantizaciones Q8 y Q4F16 se muestran como pruebas experimentales en WebGPU."
    : "WASM corre en el CPU. Q8 es la opción recomendada para empezar en iPhone/iPad.";
  renderQuantizationOptions();
  updateDeviceInfo();
  updateModelState();
}

function renderQuantizationOptions() {
  const options = MODEL_OPTIONS[state.backend];
  els.quantization.innerHTML = options
    .map((option) => `<option value="${option.dtype}">${option.title}</option>`)
    .join("");
  els.quantization.value = state.dtype;
  const selected = options.find((option) => option.dtype === state.dtype) ?? options[0];
  els.quantizationNote.textContent = selected.description;
}

function updateDeviceInfo() {
  const backendName = state.backend === "webgpu" ? "WebGPU" : "WASM";
  const option = MODEL_OPTIONS[state.backend].find((item) => item.dtype === state.dtype);
  els.selectedBackend.textContent = backendName;
  els.selectedModel.textContent = `Kokoro 82M · ${option?.title ?? state.dtype}`;
}

function setTest(name) {
  const test = TESTS[name];
  if (!test || state.busy) return;
  state.currentTest = name;
  els.text.value = test.text;
  setSelectedTest(name);
  updateTextCount();
  updateGenerateButton();
}

function setSelectedTest(name) {
  els.testButtons.forEach((button) => {
    const selected = button.dataset.test === name;
    button.classList.toggle("is-selected", selected);
    button.setAttribute("aria-pressed", String(selected));
  });
}

function updateTextCount() {
  const value = els.text.value;
  const characters = [...value].length;
  const words = countWords(value);
  els.textCount.textContent = `${formatInteger(characters)} caracteres · ${formatInteger(words)} palabras`;
}

function updateModelState() {
  const matches = sameConfig(state.loadedConfig, currentConfig());
  if (matches) {
    els.modelState.textContent = `Cargado · ${formatDurationMs(state.loadMs)}`;
    els.modelState.className = "quiet-state loaded";
  } else if (state.loadedConfig) {
    els.modelState.textContent = "Configuración cambió · vuelve a cargar";
    els.modelState.className = "quiet-state stale";
  } else {
    els.modelState.textContent = "Modelo sin cargar";
    els.modelState.className = "quiet-state";
  }
  updateGenerateButton();
}

function updateGenerateButton() {
  const ready = sameConfig(state.loadedConfig, currentConfig());
  els.generateButton.disabled = state.busy || !ready || !els.text.value.trim();
  els.loadButton.disabled = state.busy || (state.backend === "webgpu" && !state.webgpu.available);
}

function loadModel() {
  if (state.busy) return;
  if (state.backend === "webgpu" && !state.webgpu.available) {
    showError(`WebGPU no está disponible: ${state.webgpu.reason}. Selecciona WASM para probar la generación local.`);
    return;
  }

  const config = currentConfig();
  stopWorker();
  state.loadedConfig = null;
  state.loadMs = null;
  state.busy = true;
  state.worker = createWorker();
  sessionStorage.setItem("kokoro-benchmark-pending", "1");
  setBusy(true, "Cargando modelo…");
  setStatus("Cargando modelo…", "working");
  els.modelState.textContent = "Cargando modelo…";
  els.modelState.className = "quiet-state";
  els.progressRegion.hidden = false;
  setProgress(0, "Preparando la carga…");
  state.latestLoadProgress = null;
  console.info("[Kokoro Benchmark] Requesting model", config);
  state.worker.postMessage({ type: "load", config, webgpuProbe: state.webgpu });
}

function generate() {
  if (!sameConfig(state.loadedConfig, currentConfig()) || state.busy) return;
  const text = els.text.value.trim();
  if (!text) return;

  const input = {
    text,
    voice: els.voice.value,
    testName: TESTS[state.currentTest]?.name ?? "Texto propio",
  };
  state.busy = true;
  sessionStorage.setItem("kokoro-benchmark-pending", "1");
  setBusy(true, "Generando audio…");
  setStatus("Generando audio local…", "working");
  els.progressRegion.hidden = false;
  setProgress(0, "Preparando la síntesis…");
  console.info("[Kokoro Benchmark] Starting generation", {
    backendRequested: state.backend,
    dtype: state.dtype,
    voice: input.voice,
    characters: [...text].length,
    words: countWords(text),
    testName: input.testName,
  });
  state.worker.postMessage({ type: "generate", request: input });
}

function createWorker() {
  const worker = new Worker(new URL("./tts.worker.js", import.meta.url), { type: "module" });
  worker.addEventListener("message", onWorkerMessage);
  worker.addEventListener("error", onWorkerError);
  worker.addEventListener("messageerror", onWorkerMessageError);
  return worker;
}

function onWorkerMessage(event) {
  const message = event.data;
  switch (message?.type) {
    case "load-progress":
      state.latestLoadProgress = message.detail;
      renderLoadProgress(message.detail);
      break;
    case "model-loaded":
      state.busy = false;
      state.loadedConfig = message.config;
      state.loadMs = message.loadMs;
      sessionStorage.removeItem("kokoro-benchmark-pending");
      populateVoices(message.voices);
      setBusy(false);
      setProgress(100, `Modelo cargado en ${formatDurationMs(message.loadMs)}. Los datos de voz se cargan al generar.`);
      setStatus("Modelo listo", "success");
      updateModelState();
      window.setTimeout(() => {
        if (!state.busy) els.progressRegion.hidden = true;
      }, 2200);
      break;
    case "generation-progress":
      setProgress(
        Math.round((message.completedChunks / message.totalChunks) * 100),
        `Generando sección ${message.completedChunks} de ${message.totalChunks}…`,
      );
      break;
    case "voice-preparing":
      setProgress(0, `Preparando datos de voz ${message.voice} antes de medir…`);
      break;
    case "generation-complete":
      state.busy = false;
      sessionStorage.removeItem("kokoro-benchmark-pending");
      setBusy(false);
      els.progressRegion.hidden = true;
      recordResult(message);
      setStatus("Generación terminada", "success");
      break;
    case "operation-error":
      handleOperationError(message);
      break;
    default:
      console.warn("[Kokoro Benchmark] Unknown worker message", message);
  }
}

function onWorkerError(event) {
  console.error("[Kokoro Benchmark] Worker error", event.message, event.error);
  const stage = state.loadedConfig ? "generate" : "load";
  handleOperationError({
    stage,
    failureCategory: stage === "generate" ? "inference" : "unknown-load",
    name: event.error?.name ?? "WorkerError",
    message: event.message || "El worker del modelo terminó inesperadamente.",
    stack: event.error?.stack ?? "",
    backend: state.backend,
    dtype: state.dtype,
    diagnostics: mainThreadFailureDiagnostics(stage, event.error, "El worker emitió un error; su fase interna no está disponible."),
  });
}

function onWorkerMessageError(event) {
  console.error("[Kokoro Benchmark] Worker message could not be decoded", event);
  const stage = state.loadedConfig ? "generate" : "load";
  handleOperationError({
    stage,
    failureCategory: stage === "generate" ? "inference" : "unknown-load",
    name: "MessageError",
    message: "La página no pudo decodificar un mensaje del worker. Safari no expuso la causa.",
    backend: state.backend,
    dtype: state.dtype,
    diagnostics: mainThreadFailureDiagnostics(stage, null, "La página no pudo decodificar el mensaje del worker; la causa no está expuesta."),
  });
}

function handleOperationError(error) {
  state.busy = false;
  sessionStorage.removeItem("kokoro-benchmark-pending");
  setBusy(false);
  els.progressRegion.hidden = true;
  const message = friendlyError(error);
  setStatus(error.stage === "load" ? "Falló la carga" : "Falló la inferencia", "error");
  if (error.stage === "load") {
    state.loadedConfig = null;
    state.loadMs = null;
    els.modelState.textContent = "No se pudo cargar";
    els.modelState.className = "quiet-state stale";
  }
  els.latestSection.hidden = false;
  els.resultStatus.textContent = "Error";
  els.resultStatus.className = "badge danger";
  const diagnostics = error.diagnostics ?? mainThreadFailureDiagnostics(
    error.stage,
    error,
    "No hay datos suficientes para localizar la fase exacta.",
  );
  els.latestResult.innerHTML = `
    <div class="error-panel">
      <strong>${escapeHtml(message.title)}</strong>
      <p>${escapeHtml(message.body)}</p>
      <details><summary>Diagnóstico técnico</summary><pre>${escapeHtml(JSON.stringify({
        category: error.failureCategory ?? diagnostics.category ?? "unknown-load",
        stage: error.stage ?? "unavailable",
        requestedBackend: error.backend ?? state.backend,
        requestedDtype: error.dtype ?? state.dtype,
        diagnostics,
      }, null, 2))}</pre></details>
    </div>
  `;
  showToast(message.title);
  console.error("[Kokoro Benchmark] Operation failed", { ...error, friendly: message });
  updateGenerateButton();
}

function friendlyError(error) {
  const raw = `${error.name ?? ""} ${error.message ?? ""}`;
  const category = error.failureCategory ?? (error.stage === "generate" ? "inference" : "unknown-load");
  if (/out of memory|memory allocation|allocate.*memory|oom|not enough memory|memoryerror|array buffer allocation/i.test(raw)) {
    return {
      title: "Parece que Safari se quedó sin memoria.",
      body: "El error menciona memoria. Safari también puede cerrar una pestaña por presión de memoria sin exponer la causa; consulta el detalle técnico antes de concluirlo.",
    };
  }
  if (error.stage === "voice") {
    return {
      title: "No se pudieron cargar los datos de la voz.",
      body: "Comprueba la conexión con Hugging Face y vuelve a intentarlo. Esta descarga se hace antes de iniciar el cronómetro de generación.",
    };
  }
  if (category === "download-load") {
    return {
      title: "Fallo de descarga/carga",
      body: "Los datos disponibles sitúan el fallo durante una solicitud o lectura de un recurso. Esto no demuestra una incompatibilidad de WebGPU ni de operadores. Revisa el asset, bytes, URL y estado HTTP del diagnóstico.",
    };
  }
  if (category === "webgpu-initialization") {
    return {
      title: "Fallo al inicializar WebGPU",
      body: "El error contiene una señal explícita de inicialización del proveedor WebGPU. No confirma por sí solo que un operador del modelo sea incompatible.",
    };
  }
  if (category === "model-initialization") {
    return {
      title: "Fallo al inicializar modelo/ONNX Runtime",
      body: "Transformers.js marcó como terminados los recursos observados antes del fallo. Kokoro.js no expone el punto exacto de inicialización de ONNX Runtime.",
    };
  }
  if (error.stage === "generate" || category === "inference") {
    return {
      title: "Fallo durante la inferencia",
      body: "El modelo ya había terminado de cargar, pero la generación no se completó. El detalle conserva el error original y los datos disponibles.",
    };
  }
  return {
    title: "Fallo desconocido durante la carga",
    body: "La información expuesta no permite asignar con seguridad una causa más concreta. Backend solicitado: " + (error.backend === "webgpu" ? "WebGPU" : "WASM") + ". El detalle técnico indica qué datos están disponibles y cuáles no.",
  };
}

function renderLoadProgress(detail = {}) {
  let percent = Number.isFinite(detail.progress) ? detail.progress : 0;
  if (percent > 1) percent /= 100;
  const normalizedPercent = Math.max(0, Math.min(1, percent));
  const file = String(detail.file || "recursos del modelo").split("/").pop();
  let status = detail.status === "done" || normalizedPercent >= 1 ? `Recurso ${file} leído; preparando el modelo…` : `Descargando ${file}…`;
  if (detail.loaded && detail.total) status += ` ${formatBytes(detail.loaded)} / ${formatBytes(detail.total)}`;
  setProgress(Math.round(normalizedPercent * 100), status);
}

function setProgress(percent, text) {
  els.progressRegion.hidden = false;
  els.progressBar.style.width = `${Math.max(0, Math.min(100, percent))}%`;
  els.progressText.textContent = text;
}

function setBusy(busy, label = "") {
  state.busy = busy;
  els.backendButtons.forEach((button) => { button.disabled = busy || (button.dataset.backend === "webgpu" && !state.webgpu.available); });
  els.quantization.disabled = busy;
  els.voice.disabled = busy;
  els.testButtons.forEach((button) => { button.disabled = busy; });
  els.text.disabled = busy;
  els.loadButton.textContent = busy && label.startsWith("Cargando") ? label : "Load model";
  els.generateButton.textContent = busy && label.startsWith("Generando") ? label : "Generate audio";
  updateGenerateButton();
}

function populateVoices(voices) {
  if (!voices || typeof voices !== "object") return;
  const currentVoice = els.voice.value || "af_heart";
  const entries = Object.entries(voices);
  if (!entries.length) return;
  els.voice.innerHTML = entries.map(([id, voice]) => {
    const language = voice.language === "en-us" ? "Inglés estadounidense" : voice.language === "en-gb" ? "Inglés británico" : voice.language;
    return `<option value="${escapeAttribute(id)}">${escapeHtml(`${id} · ${language} · ${voice.gender ?? "voz"}`)}</option>`;
  }).join("");
  els.voice.value = entries.some(([id]) => id === currentVoice) ? currentVoice : entries[0][0];
  els.voice.disabled = state.busy;
  updateGenerateButton();
}

function recordResult(data) {
  const url = URL.createObjectURL(data.audio);
  const characters = [...data.text].length;
  const words = countWords(data.text);
  const rtf = data.durationSeconds > 0 ? data.generationMs / 1000 / data.durationSeconds : null;
  const result = {
    ...data,
    audioUrl: url,
    characters,
    words,
    rtf,
    realtimeMultiple: rtf && rtf > 0 ? 1 / rtf : null,
    createdAt: new Date(),
    loadMs: state.loadMs,
  };
  state.results.unshift(result);
  els.latestSection.hidden = false;
  els.resultStatus.textContent = "Éxito";
  els.resultStatus.className = "badge success";
  els.latestResult.innerHTML = renderResult(result, true);
  renderHistory();
  setStatus("Generación terminada", "success");
}

function renderResult(result, includeText) {
  const backend = result.config.backend === "webgpu" ? "WebGPU" : "WASM";
  const option = MODEL_OPTIONS[result.config.backend].find((item) => item.dtype === result.config.dtype);
  const rtf = result.rtf === null ? "No calculable" : `${result.rtf.toFixed(3)}×`;
  const speed = result.realtimeMultiple === null ? "No calculable" : `${result.realtimeMultiple.toFixed(2)}× tiempo real`;
  return `
    <div class="metric-grid">
      ${metric("Backend solicitado", backend)}
      ${metric("Backend confirmado", "No expuesto por Kokoro.js")}
      ${metric("Modelo / cuantización", `Kokoro 82M · ${option?.title ?? result.config.dtype}`)}
      ${metric("Voz", escapeHtml(result.voice))}
      ${metric("Caracteres / palabras", `${formatInteger(result.characters)} / ${formatInteger(result.words)}`)}
      ${metric("Tiempo de carga", formatDurationMs(result.loadMs))}
      ${metric("Carga de voz (fuera de generación)", formatDurationMs(result.voiceLoadMs))}
      ${metric("Tiempo de generación", formatDurationMs(result.generationMs))}
      ${metric("Duración real del audio", formatDuration(result.durationSeconds))}
      ${metric("RTF", rtf)}
      ${metric("Velocidad", speed)}
      ${metric("Tamaño del WAV", formatBytes(result.audioBytes))}
      ${metric("Secciones sintetizadas", String(result.chunkCount))}
    </div>
    <p class="backend-disclosure">Se solicitó ${escapeHtml(backend)} al cargar el modelo. La API pública de Kokoro.js 1.2.1 no informa el proveedor de ejecución confirmado.</p>
    <audio class="audio-player" controls playsinline preload="metadata" src="${escapeAttribute(result.audioUrl)}">Tu navegador no puede reproducir este audio.</audio>
    ${includeText ? `<details class="result-text"><summary>Texto usado (${formatInteger(result.characters)} caracteres)</summary><p>${escapeHtml(result.text)}</p></details>` : ""}
  `;
}

function metric(label, value) {
  return `<div class="metric"><dt>${escapeHtml(label)}</dt><dd>${value}</dd></div>`;
}

function renderHistory() {
  els.historySection.hidden = state.results.length === 0;
  els.historyList.innerHTML = state.results.map((result, index) => {
    const backend = result.config.backend === "webgpu" ? "WebGPU" : "WASM";
    const configLabel = `${backend} · ${result.config.dtype.toUpperCase()}`;
    const rtf = result.rtf === null ? "—" : result.rtf.toFixed(3);
    return `
      <article class="history-entry">
        <div class="history-title"><span class="history-index">${String(state.results.length - index).padStart(2, "0")}</span><strong>${escapeHtml(configLabel)}</strong><span class="history-test">${escapeHtml(result.testName)}</span></div>
        <div class="history-metrics"><span>RTF <b>${rtf}</b></span><span>Generación <b>${formatDurationMs(result.generationMs)}</b></span><span>Audio <b>${formatDuration(result.durationSeconds)}</b></span><span>Carga <b>${formatDurationMs(result.loadMs)}</b></span></div>
        <audio class="audio-player compact-player" controls playsinline preload="none" src="${escapeAttribute(result.audioUrl)}">Tu navegador no puede reproducir este audio.</audio>
      </article>
    `;
  }).join("");
}

function clearHistory() {
  state.results.forEach((result) => URL.revokeObjectURL(result.audioUrl));
  state.results = [];
  els.historySection.hidden = true;
  els.latestSection.hidden = true;
  els.historyList.innerHTML = "";
}

function stopWorker() {
  if (!state.worker) return;
  state.worker.removeEventListener("message", onWorkerMessage);
  state.worker.removeEventListener("error", onWorkerError);
  state.worker.removeEventListener("messageerror", onWorkerMessageError);
  state.worker.terminate();
  state.worker = null;
}

function setStatus(text, type = "idle") {
  els.statusText.textContent = text;
  els.status.className = `status-pill ${type}`;
}

function showError(message) {
  showToast(message);
  setStatus("Requiere atención", "error");
}

function showToast(message) {
  els.toast.textContent = message;
  els.toast.hidden = false;
  window.clearTimeout(state.toastTimer);
  state.toastTimer = window.setTimeout(() => { els.toast.hidden = true; }, 6500);
}

function checkInterruptedOperation() {
  if (sessionStorage.getItem("kokoro-benchmark-pending") !== "1") return;
  sessionStorage.removeItem("kokoro-benchmark-pending");
  els.latestSection.hidden = false;
  els.resultStatus.textContent = "Prueba interrumpida";
  els.resultStatus.className = "badge warning";
  els.latestResult.innerHTML = `<div class="error-panel interrupted"><strong>La página volvió a abrirse durante una operación.</strong><p>Safari no informa de forma fiable si cerró la pestaña por memoria u otra causa. El resultado anterior se perdió; vuelve a cargar un solo modelo y empieza con Short.</p></div>`;
  setStatus("La operación anterior se interrumpió", "error");
}

function mainThreadFailureDiagnostics(stage, error, phase) {
  return {
    category: stage === "generate" ? "inference" : "unknown-load",
    phase,
    requestedBackend: state.backend,
    modelId: MODEL_ID,
    dtypeRequested: state.dtype,
    webgpuAdapterProbe: state.backend === "webgpu" ? state.webgpu : "not requested",
    webgpuDevice: "unavailable: not exposed by the library",
    onnxRuntimeInitialization: "unavailable",
    lastKnownAssetProgress: state.latestLoadProgress ?? "unavailable",
    originalError: error ? {
      name: error.name ?? "unavailable",
      message: error.message ?? String(error),
      stack: error.stack ?? "unavailable",
      cause: error.cause?.message ?? "unavailable",
    } : "unavailable",
    unavailable: ["Safari does not reliably expose why it terminated a page or worker."],
  };
}

function countWords(text) {
  return text.trim() ? text.trim().split(/\s+/u).length : 0;
}

function formatDuration(seconds) {
  if (!Number.isFinite(seconds)) return "—";
  const minutes = Math.floor(seconds / 60);
  const remaining = seconds - minutes * 60;
  return minutes > 0 ? `${minutes}:${remaining.toFixed(1).padStart(4, "0")} min` : `${remaining.toFixed(2)} s`;
}

function formatDurationMs(milliseconds) {
  return Number.isFinite(milliseconds) ? `${(milliseconds / 1000).toFixed(2)} s` : "—";
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return "—";
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KiB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MiB`;
}

function formatInteger(value) {
  return new Intl.NumberFormat("es-MX").format(value);
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/gu, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

function escapeAttribute(value) {
  return escapeHtml(value).replace(/`/gu, "&#96;");
}

boot();
