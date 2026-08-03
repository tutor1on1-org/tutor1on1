import 'dart:convert';
import 'dart:typed_data';

import '../db/app_database.dart';

/// Creates portable browser backups without relying on a host filesystem.
class BackupService {
  BackupService(this._db);

  static const _format = 'tutor1on1-browser-backup-v1';

  final AppDatabase _db;

  Future<Uint8List> exportBytes() async {
    final tables = await _userTableNames();
    final data = <String, Object?>{};
    for (final table in tables) {
      final rows =
          await _db.customSelect('SELECT * FROM ${_quote(table)}').get();
      data[table] = rows.map((row) => row.data).toList(growable: false);
    }
    final payload = <String, Object?>{
      'format': _format,
      'schemaVersion': _db.schemaVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': data,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }

  Future<void> restoreFromBytes(List<int> bytes) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> || decoded['format'] != _format) {
      throw const FormatException('Unsupported Tutor1on1 backup file.');
    }
    final backupTables = decoded['tables'];
    if (backupTables is! Map<String, dynamic>) {
      throw const FormatException('Backup tables are missing.');
    }

    final backupSchemaVersion = decoded['schemaVersion'];
    if (backupSchemaVersion is! int ||
        backupSchemaVersion != _db.schemaVersion) {
      throw FormatException(
        'Backup schema version $backupSchemaVersion does not match '
        'this app schema version ${_db.schemaVersion}.',
      );
    }

    final currentTables = (await _userTableNames()).toSet();
    final unknown =
        backupTables.keys.where((name) => !currentTables.contains(name));
    if (unknown.isNotEmpty) {
      throw FormatException(
          'Backup contains unknown tables: ${unknown.join(', ')}.');
    }
    final missing =
        currentTables.where((name) => !backupTables.containsKey(name));
    if (missing.isNotEmpty) {
      throw FormatException(
        'Backup is incomplete; missing tables: ${missing.join(', ')}.',
      );
    }

    await _db.transaction(() async {
      for (final table in currentTables) {
        await _db.customStatement('DELETE FROM ${_quote(table)}');
      }
      for (final table in currentTables) {
        final rawRows = backupTables[table];
        if (rawRows is! List) {
          throw FormatException('Invalid rows for table $table.');
        }
        final columns = await _columnNames(table);
        for (final rawRow in rawRows) {
          if (rawRow is! Map) {
            throw FormatException('Invalid row for table $table.');
          }
          final row =
              rawRow.map((key, value) => MapEntry(key.toString(), value));
          final rowColumns =
              columns.where(row.containsKey).toList(growable: false);
          if (rowColumns.isEmpty) {
            continue;
          }
          final names = rowColumns.map(_quote).join(', ');
          final placeholders = List.filled(rowColumns.length, '?').join(', ');
          await _db.customStatement(
            'INSERT INTO ${_quote(table)} ($names) VALUES ($placeholders)',
            rowColumns.map((column) => row[column]).toList(growable: false),
          );
        }
      }
    });
  }

  Future<List<String>> _userTableNames() async {
    final rows = await _db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' AND name != 'drift_schema' ORDER BY name",
        )
        .get();
    return rows
        .map((row) => row.read<String>('name'))
        .where((name) => name.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<String>> _columnNames(String table) async {
    final rows =
        await _db.customSelect('PRAGMA table_info(${_quote(table)})').get();
    return rows.map((row) => row.read<String>('name')).toList(growable: false);
  }

  String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';
}
