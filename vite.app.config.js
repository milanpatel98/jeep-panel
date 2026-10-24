import { defineConfig } from 'vite'
import { resolve } from 'path'

// The build bundled inside the iPhone app: relative paths, served from the app's Web/ folder.
// index.html is the phone app; embed.html is the 3D Jeep alone, for the CarPlay screen.
export default defineConfig({
  base: './',
  publicDir: 'public',
  build: {
    target: 'es2020', chunkSizeWarningLimit: 1200, outDir: 'ios/Forx/Web', emptyOutDir: true,
    rollupOptions: { input: { index: resolve(__dirname, 'index.html'), embed: resolve(__dirname, 'embed.html') } },
  },
})
