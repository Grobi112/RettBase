# Wachbuch – Firestore-Datenbankstruktur

Analog zum Einsatztagebuch-OVD, eigene Collections für das Wachbuch.

## Collections

### 1. Tage
**Pfad:** `kunden/{companyId}/wachbuchTage/{dayId}`

- `dayId` Format: `DD.MM.YYYY` (z.B. `02.02.2025`)

Felder: `datum`, `createdAt`, `closed`, `createdBy`, `createdByName`

### 2. Einträge (Subcollection)
**Pfad:** `kunden/{companyId}/wachbuchTage/{dayId}/eintraege/{eintragId}`

Felder: `datum`, `uhrzeit`, `ereignis`, `text`, `eintragendePerson`, `createdAt`, `createdBy`, `createdByName`, `updatedAt`, `updatedBy`

### 3. Ereignisse (Master-Daten)
**Pfad:** `kunden/{companyId}/wachbuchEreignisse/{ereignisId}`

Felder: `name`, `order`, `active`, `createdAt`

### 4. Konfiguration
**Pfad:** `kunden/{companyId}/wachbuchConfig/config`

Felder: `editAllowedRoles` (Array, z.B. `["superadmin", "admin", "leiterssd"]`)
