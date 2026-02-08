# Firebase Cloud Functions für RettBase E-Mail-Modul

Diese Cloud Functions ermöglichen den Versand von externen E-Mails über Strato SMTP für das interne E-Mail-System.

## Einrichtung

### 1. Firebase CLI installieren

```bash
npm install -g firebase-tools
```

### 2. Firebase Login

```bash
firebase login
```

### 3. Projekt initialisieren (falls noch nicht geschehen)

```bash
firebase init functions
```

**WICHTIG:** Wenn du `firebase init functions` ausführst, musst du als Functions-Verzeichnis `module/office/functions` angeben (nicht das Standard-Verzeichnis `functions`).

### 4. Dependencies installieren

```bash
cd module/office/functions
npm install
```

### 5. SMTP-Konfiguration setzen

Setze die SMTP-Daten als Environment Variables:

```bash
firebase functions:config:set smtp.host="smtp.strato.de"
firebase functions:config:set smtp.port="587"
firebase functions:config:set smtp.user="mail@rettbase.de"
firebase functions:config:set smtp.pass="88Avalon88!"
```

**WICHTIG:** Das Passwort sollte sicher gespeichert werden. Alternativ kann man auch Firebase Secret Manager verwenden.

### 6. Funktionen deployen

```bash
firebase deploy --only functions
```

## Funktionen

### `sendEmail`

Versendet eine E-Mail über Strato SMTP.

**Parameter:**
- `to`: Empfänger-E-Mail-Adresse
- `subject`: Betreff
- `body`: Nachrichtentext
- `fromEmail`: Absender-E-Mail (optional, Standard: mail@rettbase.de)
- `fromName`: Absender-Name (optional, Standard: "RettBase")

**Beispiel-Aufruf (vom Frontend):**

```javascript
import { getFunctions, httpsCallable } from "firebase/functions";

const functions = getFunctions();
const sendEmail = httpsCallable(functions, "sendEmail");

const result = await sendEmail({
  to: "empfaenger@example.com",
  subject: "Test-E-Mail",
  body: "Dies ist eine Test-E-Mail",
  fromEmail: "max.mustermann@rettbase.de",
  fromName: "Max Mustermann"
});
```

## Sicherheit

- Die Funktion prüft, ob der Benutzer authentifiziert ist
- SMTP-Credentials werden als Environment Variables gespeichert (nicht im Code)
- Für Produktion sollte Firebase Secret Manager verwendet werden

## Hinweis

Diese Functions sind speziell für das E-Mail-Modul in `module/office/` entwickelt und befinden sich daher im selben Verzeichnis für bessere Organisation.

