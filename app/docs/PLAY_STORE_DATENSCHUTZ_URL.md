# Datenschutz-URL für Google Play (RECORD_AUDIO)

Die Play Console verlangt eine **öffentliche HTTPS-URL** zur Datenschutzerklärung, solange die App `RECORD_AUDIO` deklariert (Mikrofon für **Sprachnachrichten im Chat**).

## Option A: Eigene Domain (z. B. rettbase.de)

Wenn du ohnehin eine Website hast: eine Seite **„Datenschutz“** anlegen und die **volle URL** in der Play Console unter Datenschutzerklärung eintragen.

## Option B: Firebase Hosting (Projekt `rett-fe0fa`)

1. Vorlage anpassen: **`web/datenschutz.html`** – Platzhalter `[Firmenname]`, `[Kontakt-E-Mail]`, `[Datum]` ersetzen (rechtlich prüfen lassen).
2. Web-Build erzeugen (kopiert `web/` nach `build/web`):
   ```bash
   cd app && flutter build web
   ```
3. Hosting deployen:
   ```bash
   firebase deploy --only hosting
   ```
4. URL in der Play Console eintragen, z. B.  
   `https://rett-fe0fa.web.app/datenschutz.html`  
   (exakte Domain siehst du in der Firebase Console unter Hosting.)

## Option C: Google Sites (ohne Code)

1. [Google Sites](https://sites.google.com) → neue Site → eine Seite „Datenschutz“ mit deinem Text.
2. Site **veröffentlichen** (öffentlich).
3. Die veröffentlichte **HTTPS-URL** in der Play Console eintragen.

---

**Wichtig:** Kein Rechtsrat – Text von Fachperson anpassen. Die Vorlage in `web/datenschutz.html` ist nur ein Startpunkt.
