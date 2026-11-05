// Service Worker básico para permitir la instalación de la PWA
const CACHE_NAME = 'grupo-jk-cache-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  // Manejo de red directo con fallback silencioso
  event.respondWith(
    fetch(event.request).catch(() => caches.match(event.request))
  );
});
