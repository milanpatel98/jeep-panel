import { defineConfig } from 'vite'

// The build bundled inside the iPhone app: relative paths, served from the app's Web/ folder.
export default defineConfig({
  base: './',
  publicDir: 'public',
  build: { target: 'es2020', chunkSizeWarningLimit: 1200, outDir: 'ios/JeepApp/Web', emptyOutDir: true },
})
