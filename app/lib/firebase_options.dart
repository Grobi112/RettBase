// Firebase: rettbase-app. Web-App und Native App getrennt behandeln –
// nur „web“ ändern bei Auftrag „Web-App anpassen“, nur android/ios/macos bei „Native App anpassen“.

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

  // ========== WEB APP – gleicher API-Key wie Native, damit gleiche Auth (112@admin.rettbase.de) ==========
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCl67Qcs2Z655Y0507NG6o9WCL4twr65uc',
    appId: '1:339125193380:web:350966b45a875fae8eb431',
    messagingSenderId: '339125193380',
    projectId: 'rettbase-app',
    authDomain: 'rettbase-app.firebaseapp.com',
    storageBucket: 'rettbase-app.firebasestorage.app',
  );

  // ========== NATIVE APP (nur bei explizitem Auftrag „Native App anpassen“ ändern) ==========
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCl67Qcs2Z655Y0507NG6o9WCL4twr65uc',
    appId: '1:339125193380:android:e30bb095d25bdd9e8eb431',
    messagingSenderId: '339125193380',
    projectId: 'rettbase-app',
    storageBucket: 'rettbase-app.firebasestorage.app',
  );

  /// iOS – rettbase-app
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCl67Qcs2Z655Y0507NG6o9WCL4twr65uc',
    appId: '1:339125193380:ios:9fdf0e80f69673058eb431',
    messagingSenderId: '339125193380',
    projectId: 'rettbase-app',
    storageBucket: 'rettbase-app.firebasestorage.app',
    iosBundleId: 'com.mikefullbeck.rettbase',
  );

  /// macOS – rettbase-app
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCl67Qcs2Z655Y0507NG6o9WCL4twr65uc',
    appId: '1:339125193380:ios:9fdf0e80f69673058eb431',
    messagingSenderId: '339125193380',
    projectId: 'rettbase-app',
    storageBucket: 'rettbase-app.firebasestorage.app',
    iosBundleId: 'com.mikefullbeck.rettbase',
  );
}
