// Service Worker für RettBase
// Automatische Updates durch Versionsverwaltung

// 🔥 WICHTIG: Ändere diese Version bei jedem Update!
const CACHE_VERSION = '1.0.2';
const CACHE_NAME = `rettbase-cache-v${CACHE_VERSION}`;

// Dateien, die gecacht werden sollen
const CACHE_FILES = [
  '/',
  '/dashboard.html',
  '/home.html',
  '/login.html',
  '/firebase-config.js',
  '/auth.js',
  '/dashboard.js',
  '/modules.js',
  '/RBapp.png',
  '/manifest.json',
  // CSS und JS Dateien
  '/kunden/admin/telefonliste.html',
  '/kunden/admin/telefonliste.js',
  '/kunden/admin/telefonliste.css',
  // Weitere wichtige Dateien können hier hinzugefügt werden
];

// Install Event - Cache wird erstellt
self.addEventListener('install', (event) => {
  console.log(`📦 Service Worker installiert (Version: ${CACHE_VERSION})`);
  
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log(`✅ Cache "${CACHE_NAME}" erstellt`);
        // Cache wichtige Dateien
        return cache.addAll(CACHE_FILES).catch((error) => {
          console.warn('⚠️ Einige Dateien konnten nicht gecacht werden:', error);
          // Fortfahren auch wenn einige Dateien fehlschlagen
        });
      })
  );
  
  // Service Worker sofort aktivieren (ohne Warten auf andere Tabs)
  self.skipWaiting();
});

// Activate Event - Alte Caches werden gelöscht
self.addEventListener('activate', (event) => {
  console.log(`🔄 Service Worker aktiviert (Version: ${CACHE_VERSION})`);
  
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          // Lösche alle Caches, die nicht die aktuelle Version sind
          if (cacheName !== CACHE_NAME) {
            console.log(`🗑️ Lösche alten Cache: ${cacheName}`);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
  
  // Übernehme sofort die Kontrolle über alle Clients
  return self.clients.claim();
});

// Fetch Event - Anfragen werden aus dem Cache bedient
self.addEventListener('fetch', (event) => {
  // Nur GET-Requests cachen
  if (event.request.method !== 'GET') {
    return;
  }
  
  // Ignoriere Firebase- und externe Requests
  const url = new URL(event.request.url);
  if (
    url.origin.includes('firebase') ||
    url.origin.includes('googleapis') ||
    url.origin.includes('gstatic') ||
    url.origin.includes('google.com')
  ) {
    return;
  }
  
  event.respondWith(
    caches.match(event.request)
      .then((cachedResponse) => {
        // Wenn im Cache vorhanden, verwende Cache
        if (cachedResponse) {
          return cachedResponse;
        }
        
        // Sonst: Lade vom Netzwerk und cache das Ergebnis
        return fetch(event.request)
          .then((response) => {
            // Nur erfolgreiche Responses cachen
            if (!response || response.status !== 200 || response.type !== 'basic') {
              return response;
            }
            
            // Clone der Response (Response kann nur einmal verwendet werden)
            const responseToCache = response.clone();
            
            caches.open(CACHE_NAME)
              .then((cache) => {
                cache.put(event.request, responseToCache);
              });
            
            return response;
          })
          .catch(() => {
            // Bei Netzwerkfehler: Versuche Fallback
            if (event.request.destination === 'document') {
              return caches.match('/dashboard.html');
            }
          });
      })
  );
});

// Message Event - Für manuelle Cache-Updates
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    console.log('⏭️ Skip Waiting - Service Worker wird sofort aktiviert');
    self.skipWaiting();
  }
  
  if (event.data && event.data.type === 'CLEAR_CACHE') {
    console.log('🗑️ Cache wird gelöscht...');
    caches.delete(CACHE_NAME).then(() => {
      console.log('✅ Cache gelöscht');
    });
  }
});
