/// Cache, um doppelte ensureUsersDoc-Aufrufe innerhalb kurzer Zeit zu vermeiden.
/// Login ruft ensureUsersDoc auf; das Dashboard wird direkt danach geladen – ein zweiter
/// Aufruf ist dann redundant (idempotent, aber kostet Latenz).
class EnsureUsersDocCache {
  static String? _lastCompanyId;
  static DateTime? _lastRecordedAt;

  static const _ttlSeconds = 15;

  static void record(String companyId) {
    _lastCompanyId = companyId.trim().toLowerCase();
    _lastRecordedAt = DateTime.now();
  }

  static bool shouldSkip(String companyId) {
    final cid = companyId.trim().toLowerCase();
    final last = _lastRecordedAt;
    if (last == null || _lastCompanyId != cid) return false;
    return DateTime.now().difference(last).inSeconds < _ttlSeconds;
  }
}
