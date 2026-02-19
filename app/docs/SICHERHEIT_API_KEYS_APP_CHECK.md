# Sicherheit: API-Key-Einschränkung & App Check

**→ Vollständiges Runbook:** [SICHERHEIT_SETUP_RUNBOOK.md](SICHERHEIT_SETUP_RUNBOOK.md) (Schritt-für-Schritt mit Checkliste)

---

## App Check (aktuell nicht verwendet)

App Check mit reCAPTCHA wurde bewusst weggelassen. Der **Rate-Limit (5/min)** für `kundeExists` und `resolveLoginInfo` schützt ausreichend. Optional: Falls App Check später gewünscht ist, siehe Runbook Teil 1.

---

## 5. API-Key-Einschränkung (Firebase / Google Cloud)

Der API-Key in `firebase_options.dart` ist für den Client sichtbar – das ist bei Firebase üblich. Die Einschränkung erfolgt in der **Google Cloud Console**.

### Schritte

1. **Google Cloud Console → APIs & Services → Credentials**  
   https://console.cloud.google.com/apis/credentials?project=rett-fe0fa

2. **API-Key öffnen** (z. B. „Browser key“ für Web oder der Standard-Firebase-Key)

3. **Anwendungseinschränkungen**
   - **Keine Einschränkung** = jeder kann den Key nutzen (nicht empfohlen)
   - **HTTP-Referrer** (Web):  
     `https://*.rettbase.de/*`  
     `https://localhost:*/*`  
     `https://127.0.0.1:*/*`
   - **Android-Apps:** Paketname `com.mikefullbeck.rettbase` + SHA-1 des Signing-Keystores
   - **iOS-Apps:** Bundle-ID `com.mikefullbeck.rettbase`

4. **API-Einschränkungen**
   - Nur benötigte APIs zulassen (z. B. Firebase Authentication, Firestore, Cloud Functions, Storage)
   - Reduziert Missbrauch bei Key-Leak

### SHA-1 für Android ermitteln

```bash
# Debug-Keystore
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android

# Release-Keystore (eigener Pfad)
keytool -list -v -keystore /pfad/zum/release.keystore -alias dein-alias
```

### Hinweis

Firebase verwendet teils automatisch erstellte API-Keys. Prüfe, welcher Key von der Flutter-App genutzt wird (Firebase Console → Projekt-Einstellungen → Allgemein → „API-Schlüssel“) und schränke diesen gezielt ein.
