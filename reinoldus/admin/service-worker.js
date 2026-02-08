const CACHE_NAME = "protect-alert-auto-cache";
const FILES_TO_CACHE = [
  "/",
  "/admin.html",
  "/admin-users.html",
  "/admin-users.js",
  "/home.html",
  "/js/firebase-config.js"
];

// 📦 Installation: Cache initial aufbauen
self.addEventListener("install", (event) => {
  self.skipWaiting(); // sofort aktiv
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(FILES_TO_CACHE);
    })
  );
});

// 🧹 Alte Caches beim Aktivieren löschen
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) return caches.delete(key);
        })
      )
    )
  );
  self.clients.claim();
});

// 🔁 Netzwerk zuerst versuchen, dann Cache – bei Änderung automatisch aktualisieren
self.addEventListener("fetch", (event) => {
  const request = event.request;

  // Nur GET-Anfragen abfangen
  if (request.method !== "GET") return;

  event.respondWith(
    (async () => {
      try {
        // 🚀 1. Versuch: neue Version aus dem Netz holen
        const networkResponse = await fetch(request, { cache: "no-store" });

        // 2. Alte Version im Cache ersetzen
        const cache = await caches.open(CACHE_NAME);
        cache.put(request, networkResponse.clone());

        // 🔔 Falls sich was geändert hat, Clients updaten
        self.clients.matchAll().then((clients) => {
          clients.forEach((client) => client.postMessage({ type: "NEW_VERSION" }));
        });

        return networkResponse;
      } catch (err) {
        // 3. Falls offline, alte gecachte Version verwenden
        const cachedResponse = await caches.match(request);
        return cachedResponse || Response.error();
      }
    })()
  );
});
