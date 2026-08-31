'use strict';

const CACHE = 'rm-portfolio-v2';

const PRECACHE = [
  '/', '/index.html', '/about.html', '/projects.html', '/contact.html',
  '/css/style.css', '/js/main.js',
];

/* Install — pre-cache core assets, then skip the waiting phase immediately.
   skipWaiting() here (not in activate) means the new SW activates as soon
   as the install completes, without waiting for existing tabs to close. */
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(PRECACHE))
      .then(() => self.skipWaiting())
  );
});

/* Activate — delete every cache that isn't the current version, then
   claim all open clients so they are immediately controlled by this SW.
   The page-side controllerchange listener will trigger a reload only when
   a previous SW was already controlling the tab (i.e. this is an update,
   not a first install). */
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(k => k !== CACHE).map(k => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

/* Fetch — network-first for same-origin GET requests.
   Fresh content is always preferred; cache is the offline fallback only. */
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  if (url.origin !== self.location.origin) return;

  e.respondWith(
    fetch(e.request, { cache: 'no-cache' })
      .then(response => {
        if (response.ok) {
          caches.open(CACHE).then(c => c.put(e.request, response.clone()));
        }
        return response;
      })
      .catch(() => caches.match(e.request))
  );
});
