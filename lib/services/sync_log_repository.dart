import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'settings_repository.dart';

class SyncTransferLogItem {
  SyncTransferLogItem({
    required this.direction,
    required this.fileName,
    required this.sizeBytes,
    this.courseSubject,
    this.remoteCourseId,
    this.bundleId,
    this.bundleVersionId,
    this.hash,
    this.source,
  });

  final String direction;
  final String fileName;
  final int sizeBytes;
  final String? courseSubject;
  final int? remoteCourseId;
  final int? bundleId;
  final int? bundleVersionId;
  final String? hash;
  final String? source;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'direction': direction,
      'file_name': fileName,
      'size_bytes': sizeBytes,
      'course_subject': courseSubject,
      'remote_course_id': remoteCourseId,
      'bundle_id': bundleId,
      'bundle_version_id': bundleVersionId,
      'hash': hash,
      'source': source,
    };
  }
}

class SyncLogRepository {
  SyncLogRepository(this._settingsRepository);

  final SettingsRepository _settingsRepository;
  Future<void> _writeQueue = Future.value();

  Future<void> appendSummary({
    required String domain,
    required String actorRole,
    required int actorUserId,
    required List<SyncTransferLogItem> uploaded,
    required List<SyncTransferLogItem> downloaded,
  }) async {
    if (uploaded.isEmpty && downloaded.isEmpty) {
      return;
    }
    _writeQueue = _writeQueue.then((_) async {
      final file = await _resolveFile();
      final payload = <String, dynamic>{
        'created_at': DateTime.now().toIso8601String(),
        'event': 'sync_summary',
        'domain': domain,
        'actor_role': actorRole,
        'actor_user_id': actorUserId,
        'uploaded_count': uploaded.length,
        'downloaded_count': downloaded.length,
        'uploaded_bytes': uploaded.fold<int>(
          0,
          (total, item) => total + item.sizeBytes,
        ),
        'downloaded_bytes': downloaded.fold<int>(
          0,
          (total, item) => total + item.sizeBytes,
        ),
        'uploaded': uploaded.map((item) => item.toJson()).toList(),
        'downloaded': downloaded.map((item) => item.toJson()).toList(),
      };
      await file.writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
    return _writeQueue;
  }

  Future<File> _resolveFile() async {
    final settings = await _settingsRepository.load();
    final logDirectory = (settings.logDirectory ?? '').trim();
    final filePath = logDirectory.isNotEmpty
        ? p.join(logDirectory, 'sync_logs.jsonl')
        : p.join(Directory.current.path, 'sync_logs.jsonl');
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
}
