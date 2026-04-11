// Profil / İstatistik / Kazanç — aynı "iş günü" penceresi [start, end).

class BusinessDayBounds {
  final DateTime start;
  final DateTime end;

  const BusinessDayBounds({required this.start, required this.end});
}

/// [resetHour]: SharedPreferences `daily_reset_hour` (0–23). Profil kartı ile aynı mantık.
/// Dönüş: [start, end) — end hariç.
BusinessDayBounds getBusinessDayBounds(DateTime now, int resetHour) {
  final h = resetHour.clamp(0, 23);
  late final DateTime start;
  if (now.hour >= h) {
    start = DateTime(now.year, now.month, now.day, h);
  } else {
    final y = now.subtract(const Duration(days: 1));
    start = DateTime(y.year, y.month, y.day, h);
  }
  final end = start.add(const Duration(days: 1));
  return BusinessDayBounds(start: start, end: end);
}

/// Teslim zamanı [start, end) aralığında mı? (yerel saat, end hariç.)
bool isDateTimeInRange(DateTime? t, DateTime start, DateTime end) {
  if (t == null) return false;
  return !t.isBefore(start) && t.isBefore(end);
}
