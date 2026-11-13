import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { VitePWA } from 'vite-plugin-pwa';
export default defineConfig({ plugins: [react(), tailwindcss(), VitePWA({ registerType: 'autoUpdate', includeAssets: ['favicon.svg'], manifest: { name: 'Vivah Guest & Room Manager', short_name: 'Vivah', description: 'Private wedding guest and room allocation manager', theme_color: '#7c3f52', background_color: '#fbf8f6', display: 'standalone', start_url: '/', icons: [{ src: '/pwa-192.png', sizes: '192x192', type: 'image/png' }, { src: '/pwa-512.png', sizes: '512x512', type: 'image/png' }] }, workbox: { navigateFallback: '/index.html', globPatterns: ['**/*.{js,css,html,ico,png,svg,webmanifest}'] } })], server: { port: 5173 } });
