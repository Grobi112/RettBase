# RettBase: Dokumente-Modul – Kontext

> Kontextdokument für das Dokumente-Modul. Speichert Struktur, Features und Implementierungsdetails für zukünftige Sessions.
>
> **Commit:** `7e37cf067634618cdd94533844005fdca670b3fe`

## 1. Übersicht

- **Modul-ID:** `dokumente`
- **Bereich:** Firmenweit (keine Bereichs-Trennung) – alle Bereiche eines Kunden sehen dieselben Ordner und Dokumente
- **Daten:** Firestore (Ordner, Dokument-Metadaten, Lesebestätigungen) + Firebase Storage (Dateien)

## 2. Firestore-Struktur

```
kunden/{companyId}/
  dokumente_ordner/{folderId}
    - name, parentId, companyId, createdAt, createdBy, order
  dokumente/{docId}
    - folderId, name, fileUrl, filePath, priority, lesebestaetigungNoetig
    - companyId, createdAt, createdBy, createdByName
    gelesen/{userId}
      - at (Timestamp)
```

## 3. Firebase Storage

```
kunden/{companyId}/dokumente/{timestamp}_{filename}
```

- Erlaubte Dateitypen: PDF, DOC, DOCX
- Dateititel = Dateiname der hochgeladenen Datei

## 4. Features

| Feature | Beschreibung |
|---------|--------------|
| Ordner anlegen | Root-Ordner und Unterordner (hierarchisch) |
| Ordner umbenennen | Name in Firestore aktualisieren |
| Ordner löschen | Cascade: alle Dokumente (Storage + Firestore), Unterordner rekursiv, dann Ordner |
| Dokument hochladen | PDF, DOC, DOCX – Web- und Native-kompatibel (Bytes statt File) |
| Priorität ändern | wichtig / mittel / niedrig |
| Dokument löschen | Storage-Datei, Firestore-Dokument, Lesebestätigungen – endgültig |
| Lesebestätigung | Optional pro Dokument; „Als gelesen markieren“ |

## 5. Rollen und Rechte

| Aktion | Rollen |
|--------|--------|
| Ordner anlegen, umbenennen, löschen | superadmin, admin, geschaeftsfuehrung, rettungsdienstleitung, leiterssd, wachleitung, mpg-beauftragter, desinfektor |
| Dokument hochladen | Alle (authentifiziert) |
| Priorität ändern, Dokument löschen | Wie Ordner-Verwaltung |
| Lesen, Lesebestätigung | Alle (authentifiziert) |

## 6. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| lib/screens/dokumente_screen.dart | Hauptscreen, Root-Ordner-Übersicht |
| lib/screens/dokumente_ordner_screen.dart | Ordnerinhalt, Unterordner, Dokumente, Upload, Priorität/Löschen |
| lib/screens/dokumente_einstellungen_screen.dart | Ordnerstruktur verwalten (Anlegen, Umbenennen, Löschen) |
| lib/services/dokumente_service.dart | Firestore + Storage, alle CRUD-Operationen |
| lib/models/dokumente_model.dart | DokumenteOrdner, DokumenteDatei |

## 7. Technische Details

- **Upload:** `Uint8List` + `fileName` statt `File` – funktioniert auf Web und Native
- **Löschen:** Endgültig – keine Papierkorb-Funktion
- **Ordner-Löschen:** Rekursiv; Dokumente in Storage löschen (deleteDokument), dann Unterordner, dann Ordner
- **Dashboard:** `case 'dokumente'` → DokumenteScreen mit companyId, userRole
