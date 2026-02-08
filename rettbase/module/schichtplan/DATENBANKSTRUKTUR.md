# Neue Datenbankstruktur für Schichtplan

## Firestore-Struktur

### 1. Standorte (Wachen)
**Pfad:** `kunden/{companyId}/schichtplanStandorte/{standortId}`

```json
{
  "id": "standort1",
  "name": "RW Holzwickede",
  "order": 1,
  "active": true,
  "createdAt": [TIMESTAMP],
  "updatedAt": [TIMESTAMP]
}
```

### 2. Schichten (Shift-Typen)
**Pfad:** `kunden/{companyId}/schichtplanSchichten/{schichtId}`

```json
{
  "id": "RH1",
  "name": "RH1",
  "description": "Rettungshubschrauber 1",
  "order": 1,
  "active": true,
  "createdAt": [TIMESTAMP],
  "updatedAt": [TIMESTAMP]
}
```

### 3. Mitarbeiter
**Pfad:** `kunden/{companyId}/schichtplanMitarbeiter/{mitarbeiterId}`

```json
{
  "id": "mitarbeiter1",
  "vorname": "Max",
  "nachname": "Mustermann",
  "qualifikation": ["RH", "RS"],
  "fuehrerschein": "C1",
  "telefonnummer": "+49 123 456789",
  "active": true,
  "createdAt": [TIMESTAMP],
  "updatedAt": [TIMESTAMP]
}
```

### 4. Tage (bestehend, bleibt gleich)
**Pfad:** `kunden/{companyId}/schichtplan/{standortId}/tage/{dayId}`

```json
{
  "datum": "01.01.2024",
  "timestamp": [TIMESTAMP]
}
```

### 5. Schichten pro Tag (bestehend, bleibt gleich)
**Pfad:** `kunden/{companyId}/schichtplan/{standortId}/tage/{dayId}/schichten/{shiftId}`

```json
{
  "shiftName": "RH1",
  "personal1": {
    "mitarbeiterId": "mitarbeiter1",
    "name": "Max Mustermann",
    "qualifikation": ["RH"],
    "farbe": "#ffffff"
  },
  "personal2": {
    "mitarbeiterId": "mitarbeiter2",
    "name": "Anna Schmidt",
    "qualifikation": ["RS"],
    "farbe": "#ffef94"
  },
  "isTemporary": false
}
```

### 6. Bereitschaften (NEU)
**Pfad:** `kunden/{companyId}/schichtplan/{standortId}/tage/{dayId}/bereitschaften/{bereitschaftId}`

```json
{
  "mitarbeiterId": "mitarbeiter1",
  "name": "Max Mustermann",
  "zugeordneteSchicht": "RH1", // Optional: Schicht zuordnen
  "createdAt": [TIMESTAMP]
}
```

### 7. Einstellungen (Konfiguration)
**Pfad:** `kunden/{companyId}/schichtplan/config`

```json
{
  "defaultQualifikationen": ["RH", "RS", "RA", "NFS"],
  "updatedAt": [TIMESTAMP]
}
```

