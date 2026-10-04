import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A single JSON file in the app support folder. Writes are debounced and
/// atomic (write to a temp file, then rename) so a crash mid-save never
/// loses the queue.
class Store {
  Store([this._dirOverride]);
  final Directory? _dirOverride;
  File? _file;
  Timer? _debounce;
  Map<String, dynamic> Function()? _pending;

  Future<File> _target() async {
    if (_file != null) return _file!;
    final dir = _dirOverride ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return _file = File('${dir.path}${Platform.pathSeparator}haul.json');
  }

  Future<Map<String, dynamic>> load() async {
    try {
      final f = await _target();
      if (!f.existsSync()) return {};
      final j = jsonDecode(await f.readAsString());
      return j is Map<String, dynamic> ? j : {};
    } catch (_) {
      return {};
    }
  }

  void save(Map<String, dynamic> Function() snapshot) {
    _pending = snapshot;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), flush);
  }

  Future<void> flush() async {
    _debounce?.cancel();
    final snap = _pending;
    _pending = null;
    if (snap == null) return;
    try {
      final f = await _target();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(snap()), flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      // Persistence is best-effort; never take the UI down over it.
    }
  }
}
