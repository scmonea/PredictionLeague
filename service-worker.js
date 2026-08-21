// Minimal service worker: caches the app's static files so the site loads
// instantly (and mostly works offline) once a friend has visited it once.
// This is what makes "Add to Home Screen" feel like a real app rather than
// just a bookmark.

const CACHE_NAME = 'prediction-league-v3';
const FILES_TO_CACHE = [
  'index.html',
  'predict.html',
  'player.html',
  'scoring.html',
  'styles.css',
  'supabase-client.js',
  'league-scoring.js',
  'manifest.json',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(FILES_TO_CACHE)));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))))
  );
});

// Network-first: try the real network so odds/predictions stay fresh,
// fall back to the cached copy if there's no connection.
self.addEventListener('fetch', (event) => {
  event.respondWith(fetch(event.request).catch(() => caches.match(event.request)));
});
