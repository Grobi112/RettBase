// Firebase-Konfiguration für RettBase – gleiches Projekt wie rettbase Web-App (rett-fe0fa)
// Quelle: rettbase/firebase-config.js

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        return ios; // Fallback für Simulator
    }
  }

  // rett-fe0fa – gleiche Datenbank wie rettbase Web-App
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
