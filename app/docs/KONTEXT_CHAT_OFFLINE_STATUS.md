# Chat: Offline-Queue & Zustellungsstatus

## 1. Offline-Queueing

**Ziel:** Nachrichten werden bei fehlendem Netz lokal gespeichert und automatisch versendet, sobald wieder Netz verfügbar ist.

### Ablauf
- Nutzer tippt Nachricht (Text + optional Bilder) und sendet
- **Online:** Nachricht geht direkt an Firestore
- **Offline:** Nachricht wird in Hive gespeichert (`chat_pending_messages`), erscheint mit Uhr-Icon in der Chat-Liste
- Bei Netzverbindung (WiFi, Mobil, Ethernet): `ChatOfflineQueue.onConnectivityChanged` feuert → `processOfflineQueue()` sendet alle ausstehenden Nachrichten
- Zusätzlich: Beim Öffnen des Chat-Screens wird `processOfflineQueue()` aufgerufen (falls App im Hintergrund war)

### Relevante Dateien
- `lib/services/chat_offline_queue.dart` – Hive-Queue, Connectivity-Check
- `lib/services/chat_service.dart` – `sendMessageOrQueue`, `processOfflineQueue`, Connectivity-Listener
- `lib/screens/chat_screen.dart` – `_pendingMessages`, Timer zum Entfernen nach Versand

### Pakete
- `connectivity_plus` – Netzwerk-Status
- `hive` / `hive_flutter` – lokale Persistenz

### Web
- Offline-Queue nur auf Native (iOS, Android, macOS) – auf Web wird direkt gesendet

---

## 2. Zustellungsstatus (WhatsApp-Style)

**Symbole:**
- **1 Haken (grau)** = Verschickt (in Firestore)
- **2 Haken (grau)** = Auf Gerät des Empfängers angekommen
- **2 Haken (blau)** = Gelesen

### Firestore-Struktur
- **Message:** `deliveredTo: [uid, ...]` – Empfänger, die die Nachricht erhalten haben
- **Chat:** `lastReadAt: { uid: Timestamp }` – wann jeder Teilnehmer zuletzt den Chat geöffnet hat

### Ablauf
1. **Delivered:** Wenn der Empfänger die Nachricht im Stream erhält, schreibt die App `deliveredTo: arrayUnion(uid)` in das Message-Dokument
2. **Read:** Abgeleitet aus `lastReadAt[recipient] >= message.createdAt` – wenn der Empfänger den Chat geöffnet hat, gilt die Nachricht als gelesen

### Relevante Dateien
- `lib/models/chat.dart` – `ChatMessage.deliveredTo`
- `lib/services/chat_service.dart` – `streamMessages` markiert `deliveredTo` beim Empfang
- `lib/screens/chat_screen.dart` – `_buildDeliveryStatus()` zeigt Haken-Symbole
