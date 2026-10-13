import 'package:intl/intl.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 KB';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
}

String formatDateTime(DateTime dt) {
  final now = DateTime.now();
  final sameDay =
      now.year == dt.year && now.month == dt.month && now.day == dt.day;
  if (sameDay) return 'Today, ${DateFormat('h:mm a').format(dt)}';
  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday = yesterday.year == dt.year &&
      yesterday.month == dt.month &&
      yesterday.day == dt.day;
  if (isYesterday) return 'Yesterday, ${DateFormat('h:mm a').format(dt)}';
  return DateFormat('MMM d, h:mm a').format(dt);
}

String formatTime(DateTime dt) => DateFormat('h:mm a').format(dt);
