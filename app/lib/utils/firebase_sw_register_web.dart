import 'dart:html' as html;

/// Registriert firebase-messaging-sw nach dem ersten Frame.
/// Wird benötigt, wenn Flutter zuerst seinen SW lädt (schneller Start auf Chrome Mobile).
/// Unser SW übernimmt danach für Push bei geschlossener App.
void registerFirebaseMessagingSwDeferred() {
  if (html.window.navigator.serviceWorker == null) return;
  html.window.navigator.serviceWorker!.register(
    '/firebase-messaging-sw.js',
    {'scope': '/'},
  ).then((_) {}).catchError((_) {});
}
