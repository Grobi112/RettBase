// Firebase: rett-fe0fa. Web, Native und Functions nutzen dieses Projekt.
// Nach Projekt-Wechsel: ggf. `flutterfire configure` für korrekte Android/iOS App-IDs ausführen.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return web;
      default:
        return ios;
    }
  }

  // ========== WEB APP – rett-fe0fa ==========
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCBpI6-cT5PDbRzjNPsx_k03np4JK8AJtA',
    appId: '1:740721219821:web:a8e7f8070f875866ccd4e4',
    messagingSenderId: '740721219821',
    projectId: 'rett-fe0fa',
    authDomain: 'rett-fe0fa.firebaseapp.com',
    storageBucket: 'rett-fe0fa.firebasestorage.app',
  );

  // ========== NATIVE APP – rett-fe0fa ==========
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCBpI6-cT5PDbRzjNPsx_k03np4JK8AJtA',
    appId: '1:740721219821:android:a8e7f8070f875866ccd4e4',
    messagingSenderId: '740721219821',
    projectId: 'rett-fe0fa',
    storageBucket: 'rett-fe0fa.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCBpI6-cT5PDbRzjNPsx_k03np4JK8AJtA',
    appId: '1:740721219821:ios:a8e7f8070f875866ccd4e4',
    messagingSenderId: '740721219821',
    projectId: 'rett-fe0fa',
    storageBucket: 'rett-fe0fa.firebasestorage.app',
    iosBundleId: 'com.mikefullbeck.rettbase',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCBpI6-cT5PDbRzjNPsx_k03np4JK8AJtA',
    appId: '1:740721219821:ios:a8e7f8070f875866ccd4e4',
    messagingSenderId: '740721219821',
    projectId: 'rett-fe0fa',
    storageBucket: 'rett-fe0fa.firebasestorage.app',
    iosBundleId: 'com.mikefullbeck.rettbase',
  );
}
