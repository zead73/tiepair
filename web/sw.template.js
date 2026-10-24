/* Tiepair service worker: keeps the whole game on the device so it opens and
   plays with no connection once it has been loaded once. build.sh fills in the
   two values below (a fingerprint of every file, and the list of files), so each
   new build gets its own cache and the old one is deleted. Browsers only allow
   service workers on https pages (and localhost). */
const VERSION = '__VERSION__';
const FILES = __FILES__;
const CACHE = 'tiepair-' + VERSION;

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE)
      .then(function (cache) {
        // 'reload': always fetch fresh copies, never the browser's own HTTP cache
        return cache.addAll(FILES.map(function (f) { return new Request(f, { cache: 'reload' }); }));
      })
      .then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys()
      .then(function (keys) {
        return Promise.all(keys
          .filter(function (k) { return k.indexOf('tiepair-') === 0 && k !== CACHE; })
          .map(function (k) { return caches.delete(k); }));
      })
      .then(function () { return self.clients.claim(); })
  );
});

// Everything the game needs is in the cache (it is filled all at once), so answer
// from it first and only go to the network for something it does not hold.
self.addEventListener('fetch', function (event) {
  var req = event.request;
  if (req.method !== 'GET') return;
  var url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  event.respondWith(
    caches.match(req, { ignoreSearch: true }).then(function (hit) {
      return hit || fetch(req);
    })
  );
});
