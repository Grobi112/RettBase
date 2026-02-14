# Flutter WebApp – zentrale Hostung und Deployment

Die WebApp kann **zentral** auf einer Domain gehostet werden (z.B. `app.rettbase.de`), nicht als Subdomain pro Kunde. Die Kunden-ID wird wie in der nativen App gewählt.

---

## 1. Cloud Function deployen (einmalig)

```bash
cd /Users/mikefullbeck/RettBase/app
npm install --prefix functions
firebase deploy --project rett-fe0fa --only functions
```

---

## 2. auth-callback.html deployen

Die Datei `rettbase/auth-callback.html` muss mit der RettBase-Web-App auf alle Kunden-Subdomains deployed werden (admin.rettbase.de, firma.rettbase.de, …).

---

## 3. Firebase-Projekt

Alle RettBase-Systeme nutzen **rett-fe0fa** (firebase-config.js, auth-callback.html, Office-Functions).

---

## 4. Flutter WebApp deployen

```bash
cd /Users/mikefullbeck/RettBase/app
flutter build web
firebase deploy --project rett-fe0fa --only hosting
```

Die App liegt dann z.B. unter `rett-fe0fa.web.app` oder Ihrer konfigurierten Domain.

---

## 5. Firebase-Tools aktuell halten

```bash
npm install -g firebase-tools
```

---

## 6. Authorized Domains in Firebase

Unter [Firebase Console → Authentication → Authorized domains](https://console.firebase.google.com/project/rett-fe0fa/authentication/settings) müssen alle Domains eingetragen sein, auf denen die WebApp läuft:

- Ihre zentrale Domain (z.B. `app.rettbase.de`, `rett-fe0fa.web.app`)
- `localhost` für lokale Tests

---

## Hinweise zu Cloud Functions

- **Runtime:** Node.js 20 (Node 22 wird bei 1st-Gen-Functions nicht unterstützt)
- **firebase-functions:** v5.x mit `require("firebase-functions/v1")` für 1st gen
- **functions.config():** Nicht verwendet – keine params-Migration erforderlich
