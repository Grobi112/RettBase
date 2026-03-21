# Android-Paketname (`applicationId`) und Play Store

Die **Application ID** darf **nicht** `com.example.*` sein – Google Play lehnt das ab (Konflikt u. a. mit `androidx-startup` Content-Provider).

In diesem Projekt:

- **`com.mikefullbeck.rettbase`** – wie die iOS-Bundle-ID, eindeutig und Play-konform.

## Firebase

Nach Änderung des Paketnamens muss in der **Firebase Console** (Projekt `rett-fe0fa`) eine **Android-App** mit genau diesem Paketnamen existieren.

1. **Projekteinstellungen** → App hinzufügen → **Android** → Paketname `com.mikefullbeck.rettbase`
2. **`google-services.json`** herunterladen und nach `android/app/google-services.json` legen (ersetzen).
3. Optional: **`flutterfire configure`** ausführen, damit `lib/firebase_options.dart` und die JSON-Datei zusammenpassen.

Ohne passende Firebase-App kann Auth/Push/Firestore auf Android fehlschlagen, auch wenn das AAB hochlädt.

## Neu bauen

```bash
cd app
flutter clean
flutter pub get
flutter build appbundle
```

**Hinweis:** Eine **bereits veröffentlichte** App unter `com.example.app` ist eine **andere** App-Identität auf dem Play Store. Mit `com.mikefullbeck.rettbase` startest du faktisch ein **neues** Store-Listing (neuer Upload-Key ist ok, aber die App-ID auf Play ist neu).
