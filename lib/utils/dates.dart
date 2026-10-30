import 'package:intl/intl.dart';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isToday(DateTime d, DateTime now) => sameDay(d, now);
bool isTomorrow(DateTime d, DateTime now) =>
    sameDay(d.add(const Duration(days: 1)), now);
bool isOverdue(DateTime d, DateTime now) =>
    d.isBefore(DateTime(now.year, now.month, now.day));

/// "Today", "Tomorrow" or a short calendar date like "12 Aug".
String dayLabel(DateTime d, DateTime now) {
  if (sameDay(d, now)) return 'Today';
  if (sameDay(d.add(const Duration(days: 1)), now)) return 'Tomorrow';
  return DateFormat('d MMM').format(d);
}

/// Compact relative time: "just now", "2h ago", "3d ago", "14 Jan".
String timeAgo(DateTime d, DateTime now) {
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return DateFormat('d MMM').format(d);
}
