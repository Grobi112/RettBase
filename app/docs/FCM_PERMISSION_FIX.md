# FCM Permission Fix – cloudmessaging.messages.create denied

## Problem
`Permission 'cloudmessaging.messages.create' denied on resource '//cloudresourcemanager.googleapis.com/projects/rett-fe0fa'`

## Checklist (alle Punkte prüfen)

### 1. Cloud Resource Manager API aktivieren
Der Fehler verweist auf `cloudresourcemanager.googleapis.com` – die FCM API ruft diese API intern auf.

1. https://console.cloud.google.com/apis/library/cloudresourcemanager.googleapis.com?project=rett-fe0fa
2. **„Aktivieren“** klicken (falls noch nicht aktiv)

### 2. Richtige IAM-Rolle (wichtig)
Laut Stack Overflow hat **„Firebase Cloud Messaging Admin“** (firebasenotifications) **NICHT** die Berechtigung `cloudmessaging.messages.create`.

**Rollen, die die Berechtigung HABEN:**
- **Firebase Admin** (`roles/firebase.admin`) ← diese verwenden
- Firebase Grow Admin
- Firebase Admin SDK Administrator Service Agent

**In IAM prüfen:**
1. https://console.cloud.google.com/iam-admin/iam?project=rett-fe0fa
2. `rett-fe0fa@appspot.gserviceaccount.com` bearbeiten
3. **„Firebase Cloud Messaging Admin“** (firebasenotifications) **entfernen**, falls vorhanden
4. **„Firebase Admin“** (`roles/firebase.admin`) **hinzufügen** – nicht „Firebase Cloud Messaging Admin“

### 3. Projekt-ID
Die Function nutzt jetzt explizit `projectId: "rett-fe0fa"` (kein process.env).

### 4. Deploy und Test
```bash
cd app && firebase deploy --only functions:onNewChatMessage
```
Dann neue Chat-Nachricht senden und Logs prüfen.
