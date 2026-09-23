import { KokoroTTS } from "kokoro-js";
import { env as transformersEnv } from "@huggingface/transformers";
import wasmModuleUrl from "../node_modules/@huggingface/transformers/dist/ort-wasm-simd-threaded.jsep.mjs?url";
import wasmBinaryUrl from "../node_modules/@huggingface/transformers/dist/ort-wasm-simd-threaded.jsep.wasm?url";

const MODEL_ID = "onnx-community/Kokoro-82M-v1.0-ONNX";
const SAMPLE_RATE = 24_000;
const MAX_CHUNK_CHARS = 280;
const voiceBuffers = new Map();
const originalFetch = self.fetch.bind(self);

// Keep the ONNX Runtime WASM engine on the Pages origin instead of its CDN default.
transformersEnv.backends.onnx.wasm.wasmPaths = {
  mjs: wasmModuleUrl,
  wasm: wasmBinaryUrl,
};

// Kokoro.js reads voice files lazily from Cache API. Keep the network fetch out of
// the generation timer even in browsers where Cache API is unavailable.
self.fetch = async (input, init) => {
  const url = typeof input === "string" ? input : input?.url;
  const cachedBytes = url ? voiceBuffers.get(url) : null;
  if (cachedBytes && (!init?.method || init.method.toUpperCase() === "GET")) {
    return new Response(cachedBytes.slice(0), {
      status: 200,
      headers: { "content-type": "application/octet-stream" },
    });
  }
  return originalFetch(input, init);
};

let tts = null;
let activeConfig = null;

self.addEventListener("message", async (event) => {
  const message = event.data;

  if (message?.type === "load") {
    await loadModel(message.config);
    return;
  }

  if (message?.type === "generate") {
    await generateAudio(message.request);
  }
});

async function loadModel(config) {
  const startedAt = performance.now();
  tts = null;
  activeConfig = null;
  const { backend, dtype } = config;

  try {
    tts = await KokoroTTS.from_pretrained(MODEL_ID, {
      dtype,
      device: backend,
      progress_callback: (progress) => {
        const detail = {
          status: progress?.status ?? "progress",
          file: progress?.file ?? progress?.name ?? "",
          progress: Number.isFinite(progress?.progress) ? progress.progress : null,
          loaded: Number.isFinite(progress?.loaded) ? progress.loaded : null,
          total: Number.isFinite(progress?.total) ? progress.total : null,
        };
        self.postMessage({ type: "load-progress", detail });
      },
    });
    activeConfig = config;

    self.postMessage({
      type: "model-loaded",
      modelId: MODEL_ID,
      voices: tts.voices,
      loadMs: performance.now() - startedAt,
      config,
      backendConfirmation: "not-exposed",
    });
    console.info("[Kokoro Benchmark] Model loaded", {
      modelId: MODEL_ID,
      backendRequested: backend,
      dtype,
      backendConfirmation: "not exposed by Kokoro.js public API",
    });
  } catch (error) {
    console.error("[Kokoro Benchmark] Model load failed", error);
    self.postMessage({
      type: "operation-error",
      stage: "load",
      backend,
      dtype,
      name: error?.name ?? "Error",
      message: error?.message ?? String(error),
      stack: error?.stack ?? "",
      elapsedMs: performance.now() - startedAt,
    });
  }
}

async function generateAudio(request) {
  if (!tts || !activeConfig) {
    self.postMessage({
      type: "operation-error",
      stage: "generate",
      message: "El modelo no está cargado. Vuelve a cargarlo antes de generar audio.",
    });
    return;
  }

  const { text, voice, testName } = request;
  let voiceLoadMs = 0;

  try {
    self.postMessage({ type: "voice-preparing", voice });
    voiceLoadMs = await prepareVoiceData(voice);
  } catch (error) {
    console.error("[Kokoro Benchmark] Voice data load failed", error);
    self.postMessage({
      type: "operation-error",
      stage: "voice",
      backend: activeConfig.backend,
      dtype: activeConfig.dtype,
      name: error?.name ?? "Error",
      message: error?.message ?? String(error),
      stack: error?.stack ?? "",
    });
    return;
  }

  const startedAt = performance.now();

  try {
    const chunks = splitIntoChunks(text);
    const parts = [];
    let sampleCount = 0;

    for (let index = 0; index < chunks.length; index += 1) {
      const rawAudio = await tts.generate(chunks[index], { voice });
      const samples = rawAudio?.audio;
      if (!samples || !Number.isFinite(samples.length)) {
        throw new Error("Kokoro no devolvió datos PCM de audio en el formato esperado.");
      }
      parts.push(samples);
      sampleCount += samples.length;
      self.postMessage({
        type: "generation-progress",
        completedChunks: index + 1,
        totalChunks: chunks.length,
      });
    }

    const generationMs = performance.now() - startedAt;
    const mergedSamples = new Float32Array(sampleCount);
    let offset = 0;
    for (const part of parts) {
      mergedSamples.set(part, offset);
      offset += part.length;
    }

    const wav = encodeWavPcm16(mergedSamples, SAMPLE_RATE);
    const durationSeconds = mergedSamples.length / SAMPLE_RATE;
    const result = {
      type: "generation-complete",
      audio: wav,
      audioBytes: wav.size,
      sampleCount: mergedSamples.length,
      sampleRate: SAMPLE_RATE,
      durationSeconds,
      generationMs,
      voiceLoadMs,
      config: activeConfig,
      voice,
      testName,
      text,
      chunkCount: chunks.length,
      backendConfirmation: "not-exposed",
    };

    self.postMessage(result);
    console.info("[Kokoro Benchmark] Generation complete", {
      backendRequested: activeConfig.backend,
      dtype: activeConfig.dtype,
      characters: [...text].length,
      words: countWords(text),
      chunkCount: chunks.length,
      generationMs,
      voiceLoadMs,
      sampleCount: mergedSamples.length,
      sampleRate: SAMPLE_RATE,
      durationSeconds,
      audioBytes: wav.size,
      rtf: durationSeconds > 0 ? generationMs / 1000 / durationSeconds : null,
    });
  } catch (error) {
    console.error("[Kokoro Benchmark] Audio generation failed", error);
    self.postMessage({
      type: "operation-error",
      stage: "generate",
      backend: activeConfig.backend,
      dtype: activeConfig.dtype,
      name: error?.name ?? "Error",
      message: error?.message ?? String(error),
      stack: error?.stack ?? "",
      elapsedMs: performance.now() - startedAt,
    });
  }
}

async function prepareVoiceData(voice) {
  const url = `https://huggingface.co/${MODEL_ID}/resolve/main/voices/${encodeURIComponent(voice)}.bin`;
  if (voiceBuffers.has(url)) return 0;
  const startedAt = performance.now();

  try {
    const cache = await caches.open("kokoro-voices");
    const cachedResponse = await cache.match(url);
    if (cachedResponse) {
      voiceBuffers.set(url, await cachedResponse.arrayBuffer());
      return performance.now() - startedAt;
    }
  } catch (error) {
    console.warn("[Kokoro Benchmark] Voice Cache API unavailable; using an in-memory buffer", error);
  }

  const response = await originalFetch(url);
  if (!response.ok) {
    throw new Error(`No se pudo descargar la voz ${voice} (HTTP ${response.status}).`);
  }
  const bytes = await response.arrayBuffer();
  voiceBuffers.set(url, bytes);

  try {
    const cache = await caches.open("kokoro-voices");
    await cache.put(url, new Response(bytes.slice(0), { headers: response.headers }));
  } catch (error) {
    console.warn("[Kokoro Benchmark] Could not cache voice file", error);
  }
  return performance.now() - startedAt;
}

function splitIntoChunks(input) {
  const normalized = input.replace(/[\r\n\t]+/gu, " ").replace(/\s+/gu, " ").trim();
  if (!normalized) throw new Error("Escribe un texto antes de generar audio.");

  const sentences = normalized.match(/[^.!?]+(?:[.!?]+["')\]]*)?(?:\s+|$)/gu) ?? [normalized];
  const chunks = [];
  let current = "";

  for (const sentence of sentences) {
    const part = sentence.trim();
    if (!part) continue;

    if (part.length > MAX_CHUNK_CHARS) {
      if (current) chunks.push(current);
      current = "";
      let remaining = part;
      while (remaining.length > MAX_CHUNK_CHARS) {
        let cut = remaining.lastIndexOf(" ", MAX_CHUNK_CHARS);
        if (cut < Math.floor(MAX_CHUNK_CHARS * 0.55)) cut = MAX_CHUNK_CHARS;
        chunks.push(remaining.slice(0, cut).trim());
        remaining = remaining.slice(cut).trim();
      }
      current = remaining;
      continue;
    }

    const combined = current ? `${current} ${part}` : part;
    if (combined.length <= MAX_CHUNK_CHARS) {
      current = combined;
    } else {
      if (current) chunks.push(current);
      current = part;
    }
  }

  if (current) chunks.push(current);
  return chunks;
}

function encodeWavPcm16(samples, sampleRate) {
  const bytes = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(bytes);
  const writeText = (offset, value) => {
    for (let index = 0; index < value.length; index += 1) {
      view.setUint8(offset + index, value.charCodeAt(index));
    }
  };

  writeText(0, "RIFF");
  view.setUint32(4, 36 + samples.length * 2, true);
  writeText(8, "WAVE");
  writeText(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeText(36, "data");
  view.setUint32(40, samples.length * 2, true);

  for (let index = 0; index < samples.length; index += 1) {
    const sample = Math.max(-1, Math.min(1, samples[index]));
    view.setInt16(44 + index * 2, sample < 0 ? sample * 0x8000 : sample * 0x7fff, true);
  }

  return new Blob([bytes], { type: "audio/wav" });
}

function countWords(text) {
  return text.trim() ? text.trim().split(/\s+/u).length : 0;
}
