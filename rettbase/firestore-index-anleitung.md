# Firestore Index für Collection Group Query erstellen

## Problem
Die Collection Group Query auf `users` mit dem Feld `email` benötigt einen Index.

## Lösung

### Option 1: Automatisch über den Fehlerlink
1. Öffne den Link aus der Fehlermeldung im Browser
2. Klicke auf "Index erstellen" in der Firebase Console
3. Warte, bis der Index erstellt wurde (kann einige Minuten dauern)

### Option 2: Manuell in Firebase Console
1. Gehe zu Firebase Console → Firestore Database → Indexes
2. Klicke auf "Create Index"
3. Wähle:
   - **Collection ID**: `users` (Collection Group)
   - **Fields to index**:
     - `email` (Ascending)
4. Klicke auf "Create"

### Option 3: Über firestore.indexes.json (für automatische Bereitstellung)
Erstelle eine Datei `firestore.indexes.json` im Projekt-Root:

```json
{
  "indexes": [
    {
      "collectionGroup": "users",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        {
          "fieldPath": "email",
          "order": "ASCENDING"
        }
      ]
    }
  ]
}
```

Dann deploye mit: `firebase deploy --only firestore:indexes`








