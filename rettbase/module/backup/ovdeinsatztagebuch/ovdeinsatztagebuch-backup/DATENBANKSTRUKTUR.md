# Datenbankstruktur für OVD Einsatztagebuch

## Firestore-Struktur

### 1. Tage (Täglich erstelltes Einsatztagebuch)
**Pfad:** `kunden/{companyId}/ovdEinsatztagebuchTage/{dayId}`

- `dayId` Format: `DD.MM.YYYY` (z.B. `01.12.2024`)

```json
{
  "datum": "01.12.2024",
  "createdAt": [TIMESTAMP],
  "closed": false,
  "createdBy": "userId",
  "createdByName": "user@example.com"
}
```

### 2. Einträge (Ereignisse im Tagebuch)
**Pfad:** `kunden/{companyId}/ovdEinsatztagebuchTage/{dayId}/eintraege/{eintragId}`

```json
{
  "datum": "01.12.2024",
  "uhrzeit": "14:30:00",
  "ereignis": "Einsatzbeginn",
  "text": "Einsatzmeldung über Leitstelle",
  "diensthabenderOvd": "user@example.com",
  "createdAt": [TIMESTAMP],
  "createdBy": "userId",
  "createdByName": "user@example.com",
  "updatedAt": [TIMESTAMP],
  "updatedBy": "userId"
}
```

### 3. Einstellungen (Konfiguration)
**Pfad:** `kunden/{companyId}/ovdEinsatztagebuchConfig`

```json
{
  "editAllowedRoles": ["superadmin", "admin"],
  "updatedAt": [TIMESTAMP]
}
```

## Automatische Anlage

- Beim ersten Zugriff auf einen Tag wird automatisch das Tagebuch-Dokument erstellt
- Einträge werden manuell über das UI hinzugefügt
- Live-Updates über Firestore `onSnapshot`

## Berechtigungen

- **Aktueller Tag (nicht abgeschlossen)**: Alle berechtigten Benutzer können Einträge hinzufügen/bearbeiten
- **Abgeschlossene Tage**: Nur Rollen aus `editAllowedRoles` können bearbeiten (standardmäßig: superadmin, admin)
