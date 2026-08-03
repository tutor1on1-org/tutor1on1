class BrowserJsonlStore {
  const BrowserJsonlStore();

  static final Map<String, List<Map<String, dynamic>>> _rows =
      <String, List<Map<String, dynamic>>>{};

  Future<void> append(String key, Map<String, dynamic> payload) async {
    (_rows[key] ??= <Map<String, dynamic>>[]).add(
      Map<String, dynamic>.from(payload),
    );
  }

  Future<List<Map<String, dynamic>>> read(String key) async =>
      (_rows[key] ?? const <Map<String, dynamic>>[])
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
}
