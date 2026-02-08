# Firestore Setup für Schichtplan-Modul

## Was muss in Firestore angelegt werden?

### 1. **Globales Modul anlegen** (einmalig)

**Pfad:** `modules/schichtplan`

**Dokument-ID:** `schichtplan`

**Felder:**
```json
{
  "id": "schichtplan",
  "label": "Schichtplan",
  "url": "module/schichtplan/schichtplan.html",
  "icon": "schichtplan",
  "roles": ["superadmin", "admin", "supervisor", "user"],
  "free": true,
  "order": 2,
  "active": true,
  "createdAt": [TIMESTAMP] // Optional: Aktuelles Datum
}
```

### 2. **Modul für jede Firma aktivieren** (pro Firma)

**Pfad:** `kunden/{companyId}/modules/schichtplan`

**Dokument-ID:** `schichtplan`

**Felder:**
```json
{
  "enabled": true,
  "updatedAt": [TIMESTAMP] // Optional: Aktuelles Datum
}
```

**Beispiele:**
- Für Superadmin-Firma: `kunden/admin/modules/schichtplan`
- Für Kunden-Firma: `kunden/{kundenId}/modules/schichtplan` (z.B. `kunden/nfsunna/modules/schichtplan`)

---

## Schritt-für-Schritt Anleitung

### Option 1: Automatisch (Empfohlen)
1. Als **Superadmin** bei `admin.rettbase.de` einloggen
2. Das System erstellt automatisch das Modul und aktiviert es für die `admin`-Firma
3. Für andere Firmen: In der **Kundenverwaltung** das Modul aktivieren

### Option 2: Manuell in Firebase Console

#### Schritt 1: Globales Modul anlegen
1. Öffne Firebase Console → Firestore Database
2. Navigiere zu: `modules` (Collection)
3. Klicke auf "Dokument hinzufügen"
4. **Dokument-ID:** `schichtplan`
5. Füge folgende Felder hinzu:
   - `id` (string): `schichtplan`
   - `label` (string): `Schichtplan`
   - `url` (string): `module/schichtplan/schichtplan.html`
   - `icon` (string): `schichtplan`
   - `roles` (array): `["superadmin", "admin", "supervisor", "user"]`
   - `free` (boolean): `true`
   - `order` (number): `2`
   - `active` (boolean): `true`

#### Schritt 2: Modul für Firma aktivieren
1. Navigiere zu: `kunden` → `{companyId}` → `modules` (Subcollection)
2. Klicke auf "Dokument hinzufügen"
3. **Dokument-ID:** `schichtplan`
4. Füge folgende Felder hinzu:
   - `enabled` (boolean): `true`

**Wiederhole Schritt 2 für jede Firma, die das Modul nutzen soll!**

---

## Prüfen ob es funktioniert

1. Als Benutzer einloggen
2. Im Hamburger-Menü sollte "Schichtplan" erscheinen
3. Beim Klick sollte `module/schichtplan/schichtplan.html` geladen werden

---

## Hinweis

Falls das Modul bereits unter dem alten Namen `schichtplanlight` existiert:
- **Entweder:** Altes Modul löschen und neues `schichtplan` anlegen
- **Oder:** Altes Modul umbenennen (Dokument-ID ändern)




