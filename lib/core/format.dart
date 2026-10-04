/// Small, dependency-free formatters used across the UI.
library;

String formatBytes(num? bytes) {
  if (bytes == null || !bytes.isFinite || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : (value >= 10 ? 1 : 1);
  var text = value.toStringAsFixed(digits);
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return '$text ${units[unit]}';
}

String formatSpeed(num? bytesPerSecond) {
  final b = formatBytes(bytesPerSecond);
  return b.isEmpty ? '' : '$b/s';
}

String formatDuration(num? seconds) {
  if (seconds == null || !seconds.isFinite || seconds <= 0) return '';
  final s = seconds.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// "3s", "2m", "1h 4m" — for ETAs, where precision matters less than calm.
String formatEta(num? seconds) {
  if (seconds == null || !seconds.isFinite || seconds <= 0) return '';
  final s = seconds.round();
  if (s < 60) return '${s}s';
  if (s < 3600) {
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 || m >= 10 ? '${m}m' : '${m}m ${r}s';
  }
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// Collapses a home-relative path to `~/…` for display.
String prettyPath(String path, String? home) {
  if (home != null && home.isNotEmpty && path.startsWith(home)) {
    return '~${path.substring(home.length)}';
  }
  return path;
}

String relativeTime(DateTime when, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(when);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
}
