import { defineConfig } from 'vite'

export default defineConfig({
  base: '/jeep-panel/',
  build: { target: 'es2020', chunkSizeWarningLimit: 1200 },
})
