# WebApp-Login einrichten

Die **native App** und die **WebApp** nutzen dieselben Firebase Auth Nutzer.  
Es müssen **keine Nutzer neu angelegt** werden – nur einmalig die Firebase-Konfiguration für Web ergänzen.

---

## 1. Firebase: Authorized Domains (einmalig)

Firebase erlaubt Web-Login nur von explizit freigegebenen Domains.

### Schritte

1. Öffne: **[Firebase Console → rett-fe0fa → Authentication → Settings → Authorized domains](https://console.firebase.google.com/project/rett-fe0fa/authentication/settings)**

2. Klicke auf **„Domain hinzufügen“** und trage ein:
   - **Lokal testen:** `localhost`
   - **Produktion:** die Domain, auf der die WebApp läuft (z.B. `rett-fe0fa.web.app`, `admin.rettbase.de`, `www.rettbase.de`)

3. Speichern – fertig. Alle Nutzer (112, E-Mails, Personalnummern) funktionieren danach in der WebApp.

---

## 2. WebApp lokal starten

```bash
cd /Users/mikefullbeck/RettBase/app
flutter run -d chrome
```

Unter `http://localhost:XXXX` sollte der Login mit Kunde `admin` und `112` funktionieren.

---

## 3. WebApp deployen (optional)

```bash
cd /Users/mikefullbeck/RettBase/app
./scripts/deploy_web.sh
```

Oder manuell:

```bash
flutter build web
firebase deploy --project rett-fe0fa --only hosting
```

---

## Hinweise

- **Nutzer:** Alle bestehenden Nutzer (112@admin.rettbase.de, E-Mail-Logins, Personalnummern) bleiben unverändert.
- **Änderung:** Nur die Authorized Domains in Firebase – einmal pro Domain.
- **Projekt:** rett-fe0fa (nicht rettbase-global)
