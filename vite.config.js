import { defineConfig } from "vite";

export default defineConfig({
  // Relative asset URLs also work under GitHub Pages' /repository/ path.
  base: "./",
  worker: {
    format: "es",
  },
});
