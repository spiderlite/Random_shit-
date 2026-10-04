/// Where settings and the queue are kept between launches.
abstract class KeyStore {
  Future<Map<String, dynamic>> load();

  /// Debounced; [snapshot] is called when the write actually happens.
  void save(Map<String, dynamic> Function() snapshot);

  Future<void> flush();
}
