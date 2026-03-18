import UserNotifications

/// Läuft bei JEDEM Push – auch wenn die App komplett beendet ist.
/// Stellt sicher, dass Badge + Ton + Nachricht angezeigt werden.
class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // Badge aus Payload übernehmen (falls nicht gesetzt)
        if let aps = request.content.userInfo["aps"] as? [String: Any],
           let badge = aps["badge"] as? NSNumber {
            bestAttemptContent.badge = badge
        }
        // Bei Alarm-Push: Custom-Sound aus Payload beibehalten (voller Lautstärke).
        // Bei anderen Push-Typen: Standardton.
        let isAlarm = (request.content.userInfo["type"] as? String) == "alarm"
        if !isAlarm {
            bestAttemptContent.sound = .default
        }

        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
