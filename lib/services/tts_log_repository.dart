import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'settings_repository.dart';

class TtsLogEntry {
  TtsLogEntry({
    required this.createdAt,
    required this.event,
    required this.message,
    this.statusCode,
    this.baseUrl,
    this.model,
    this.voice,
    this.textSnippet,
    this.sessionId,
    this.textLength,
  });

  final DateTime createdAt;
  final String event;
  final String message;
  final int? statusCode;
  final String? baseUrl;
  final String? model;
  final String? voice;
  final String? textSnippet;
  final int? sessionId;
  final int? textLength;

  factory TtsLogEntry.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['created_at'];
    DateTime createdAt;
    if (createdRaw is String) {
      createdAt = DateTime.tryParse(createdRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }
    return TtsLogEntry(
      createdAt: createdAt,
      event: json['event'] as String? ?? 'error',
      message: json['message'] as String? ??
          json['error_message'] as String? ??
          '',
      statusCode: json['status_code'] as int?,
      baseUrl: json['base_url'] as String?,
      model: json['model'] as String?,
      voice: json['voice'] as String?,
      textSnippet: json['text_snippet'] as String?,
      sessionId: json['session_id'] as int?,
      textLength: json['text_length'] as int?,
    );
  }
}

class TtsLogRepository {
  TtsLogRepository(this._settingsRepository);

  final SettingsRepository _settingsRepository;
  Future<void> _writeQueue = Future.value();

  Future<void> appendEvent({
    required String event,
    required String message,
    required String baseUrl,
    required String model,
    required String voice,
    String? textSnippet,
    int? textLength,
    int? statusCode,
    int? sessionId,
  }) async {
    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = await _resolveFile();
        final payload = <String, dynamic>{
          'created_at': DateTime.now().toIso8601String(),
          'event': event,
          'message': _truncate(message, 800),
          'status_code': statusCode,
          'base_url': baseUrl,
          'model': model,
          'voice': voice,
          'text_snippet': _truncate(textSnippet ?? '', 8000),
          'session_id': sessionId,
          'text_length': textLength,
        };
        await file.writeAsString(
          '${jsonEncode(payload)}\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Ignore logging failures to avoid blocking TTS output.
      }
    });
    return _writeQueue;
  }

  Future<void> appendError({
    required String message,
    required String baseUrl,
    required String model,
    required String voice,
    String? textSnippet,
    int? textLength,
    int? statusCode,
    int? sessionId,
  }) {
    return appendEvent(
      event: 'error',
      message: message,
      baseUrl: baseUrl,
      model: model,
      voice: voice,
      textSnippet: textSnippet,
      textLength: textLength,
      statusCode: statusCode,
      sessionId: sessionId,
    );
  }

  Future<List<TtsLogEntry>> loadEntries() async {
    final file = await _resolveFile();
    if (!await file.exists()) {
      return [];
    }
    final bytes = await file.readAsBytes();
    final content = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter().convert(content);
    final entries = <TtsLogEntry>[];
    for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          entries.add(TtsLogEntry.fromJson(decoded));
        }
      } catch (_) {
        // Skip malformed lines.
      }
    }
    return entries.reversed.toList();
  }

  Future<File> _resolveFile() async {
    final settings = await _settingsRepository.load();
    final resolvedPath = (settings.ttsLogPath ?? '').trim();
    final filePath = resolvedPath.isNotEmpty
        ? resolvedPath
        : p.join(Directory.current.path, 'tts_logs.jsonl');
    final dir = Directory(p.dirname(filePath));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(filePath);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  String _truncate(String value, int max) {
    if (value.length <= max) {
      return value;
    }
    return value.substring(0, max);
  }
}
