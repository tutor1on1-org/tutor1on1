import 'dart:convert';

import 'package:web/web.dart' as web;

class BrowserJsonlStore {
  const BrowserJsonlStore();

  static const int _maxCharsPerLog = 1000000;

  Future<void> append(String key, Map<String, dynamic> payload) async {
    final storageKey = _storageKey(key);
    final current = web.window.localStorage.getItem(storageKey) ?? '';
    final nextLine = jsonEncode(payload);
    var next = current.isEmpty ? nextLine : '$current\n$nextLine';
    if (next.length > _maxCharsPerLog) {
      final trimAt = next.indexOf('\n', next.length - _maxCharsPerLog);
      next = trimAt < 0
          ? next.substring(next.length - _maxCharsPerLog)
          : next.substring(trimAt + 1);
    }
    web.window.localStorage.setItem(storageKey, next);
  }

  Future<List<Map<String, dynamic>>> read(String key) async {
    final raw = web.window.localStorage.getItem(_storageKey(key)) ?? '';
    return _decodeRows(raw);
  }

  List<Map<String, dynamic>> _decodeRows(String raw) {
    if (raw.trim().isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final rows = <Map<String, dynamic>>[];
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) {
        continue;
      }
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Browser log row is not a JSON object.');
      }
      rows.add(decoded);
    }
    return rows;
  }

  String _storageKey(String key) => 'tutor1on1:log:$key';
}
