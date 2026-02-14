// Firebase Messaging Service Worker – Push + Badge (setBadge-Handler).
// Flutter-SW wird in index.html blockiert – wir sind der einzige SW.
self.addEventListener('install',function(){self.skipWaiting();});
self.addEventListener('activate',function(e){e.waitUntil(self.clients.claim());});

importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCBpI6-cT5PDbRzjNPsx_k03np4JK8AJtA',
  authDomain: 'rett-fe0fa.firebaseapp.com',
  projectId: 'rett-fe0fa',
  storageBucket: 'rett-fe0fa.firebasestorage.app',
  messagingSenderId: '740721219821',
  appId: '1:740721219821:web:a8e7f8070f875866ccd4e4',
});

const messaging = firebase.messaging();

const CHAT_SUMMARY_TAG = 'rettbase-chat-summary';

messaging.onBackgroundMessage(function(payload) {
  const notif = payload.notification || {};
  const data = payload.data || {};
  const totalUnread = parseInt(data.totalUnread || data.badge || '1', 10) || 1;
  const title = notif.title || (totalUnread === 1 ? 'Neue Chat-Nachricht' : totalUnread + ' ungelesene Nachrichten');
  const body = notif.body || '';
  const notificationOptions = {
    body: body,
    icon: self.location.origin + '/icons/Icon-192.png',
    tag: CHAT_SUMMARY_TAG,
    renotify: true,
    data: data,
  };

  var p = self.registration.showNotification(title, notificationOptions);

  if (self.navigator && typeof self.navigator.setAppBadge === 'function') {
    self.navigator.setAppBadge(totalUnread).catch(function() {});
  }

  return p;
});

const BADGE_NOTIFY_TAG = 'rettbase-badge-notify';

self.addEventListener('message', function(event) {
  const data = event.data || {};
  if (data.action === 'setBadge') {
    const count = parseInt(data.count, 10) || 0;
    const showNotify = data.showNotification === true;
    if (self.navigator && typeof self.navigator.setAppBadge === 'function') {
      if (count <= 0) {
        self.navigator.clearAppBadge().catch(function() {});
      } else {
        self.navigator.setAppBadge(Math.min(99, count)).catch(function() {});
      }
    }
    if (showNotify && count > 0) {
      self.registration.showNotification(count + ' ungelesene Nachrichten', {
        tag: BADGE_NOTIFY_TAG,
        body: 'Tippen zum Öffnen',
        icon: self.location.origin + '/icons/Icon-192.png',
        silent: true,
        requireInteraction: false,
        renotify: false,
      }).catch(function() {});
    } else if (count <= 0) {
      self.registration.getNotifications().then(function(ns) {
        ns.forEach(function(n) { if (n.tag === BADGE_NOTIFY_TAG) n.close(); });
      });
    }
  }
  if (data.action === 'clearChatNotification') {
    self.registration.getNotifications().then(function(notifications) {
      notifications.forEach(function(n) {
        if (n.tag === CHAT_SUMMARY_TAG || n.tag === BADGE_NOTIFY_TAG) n.close();
      });
    });
    if (self.navigator && typeof self.navigator.clearAppBadge === 'function') {
      self.navigator.clearAppBadge().catch(function() {});
    }
  }
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const data = event.notification.data || {};
  const companyId = data.companyId || '';
  const chatId = data.chatId || '';
  const url = self.location.origin + self.location.pathname;
  const targetUrl = chatId ? (url + (url.endsWith('/') ? '' : '/') + '#chat/' + companyId + '/' + chatId) : url;
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (var i = 0; i < clientList.length; i++) {
        var client = clientList[i];
        if (client.url.indexOf(self.location.origin) === 0 && 'focus' in client) {
          client.navigate(targetUrl);
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});
