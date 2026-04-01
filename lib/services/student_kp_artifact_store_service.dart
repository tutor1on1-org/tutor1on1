import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StudentKpArtifactManifestItem {
  StudentKpArtifactManifestItem({
    required this.artifactId,
    required this.sha256,
    required this.baseSha256,
    required this.lastModified,
    required this.storageFile,
    required this.deleted,
  });

  final String artifactId;
  final String sha256;
  final String baseSha256;
  final String lastModified;
  final String storageFile;
  final bool deleted;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'artifact_id': artifactId,
        'sha256': sha256,
        'base_sha256': baseSha256,
        'last_modified': lastModified,
        'storage_file': storageFile,
        'deleted': deleted,
      };

  factory StudentKpArtifactManifestItem.fromJson(Map<String, dynamic> json) {
    return StudentKpArtifactManifestItem(
      artifactId: (json['artifact_id'] as String? ?? '').trim(),
      sha256: (json['sha256'] as String? ?? '').trim(),
      baseSha256: (json['base_sha256'] as String? ?? '').trim(),
      lastModified: (json['last_modified'] as String? ?? '').trim(),
      storageFile: (json['storage_file'] as String? ?? '').trim(),
      deleted: json['deleted'] == true,
    );
  }

  StudentKpArtifactManifestItem copyWith({
    String? artifactId,
    String? sha256,
    String? baseSha256,
    String? lastModified,
    String? storageFile,
    bool? deleted,
  }) {
    return StudentKpArtifactManifestItem(
      artifactId: artifactId ?? this.artifactId,
      sha256: sha256 ?? this.sha256,
      baseSha256: baseSha256 ?? this.baseSha256,
      lastModified: lastModified ?? this.lastModified,
      storageFile: storageFile ?? this.storageFile,
      deleted: deleted ?? this.deleted,
    );
  }
}

class StudentKpArtifactManifest {
  StudentKpArtifactManifest({
    required this.remoteUserId,
    required this.state2,
    required this.updatedAt,
    required this.items,
  });

  final int remoteUserId;
  final String state2;
  final String updatedAt;
  final Map<String, StudentKpArtifactManifestItem> items;

  factory StudentKpArtifactManifest.empty(int remoteUserId) {
    final now = DateTime.now().toUtc().toIso8601String();
    return StudentKpArtifactManifest(
      remoteUserId: remoteUserId,
      state2: StudentKpArtifactStoreService.buildState2(
        const <StudentKpArtifactManifestItem>[],
      ),
      updatedAt: now,
      items: <String, StudentKpArtifactManifestItem>{},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'remote_user_id': remoteUserId,
        'state2': state2,
        'updated_at': updatedAt,
        'items': items.values.toList(growable: false)
          ..sort((left, right) => left.artifactId.compareTo(right.artifactId)),
      };

  factory StudentKpArtifactManifest.fromJson(Map<String, dynamic> json) {
    final itemMap = <String, StudentKpArtifactManifestItem>{};
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map<String, dynamic>) {
          continue;
        }
        final item = StudentKpArtifactManifestItem.fromJson(raw);
        if (item.artifactId.isEmpty) {
          continue;
        }
        itemMap[item.artifactId] = item;
      }
    }
    return StudentKpArtifactManifest(
      remoteUserId: (json['remote_user_id'] as num?)?.toInt() ?? 0,
      state2: (json['state2'] as String? ?? '').trim(),
      updatedAt: (json['updated_at'] as String? ?? '').trim(),
      items: itemMap,
    );
  }

  StudentKpArtifactManifest copyWith({
    int? remoteUserId,
    String? state2,
    String? updatedAt,
    Map<String, StudentKpArtifactManifestItem>? items,
  }) {
    return StudentKpArtifactManifest(
      remoteUserId: remoteUserId ?? this.remoteUserId,
      state2: state2 ?? this.state2,
      updatedAt: updatedAt ?? this.updatedAt,
      items: items ?? this.items,
    );
  }
}

class LocalArtifactBuildInput {
  LocalArtifactBuildInput({
    required this.artifactId,
    required this.lastModified,
    required this.payload,
  });

  final String artifactId;
  final DateTime lastModified;
  final Map<String, dynamic> payload;
}

class LocalArtifactBuildResult {
  LocalArtifactBuildResult({
    required this.artifactId,
    required this.sha256,
    required this.lastModified,
    required this.bytes,
  });

  final String artifactId;
  final String sha256;
  final String lastModified;
  final Uint8List bytes;
}

class StudentKpArtifactStoreService {
  StudentKpArtifactStoreService({
    Future<Directory> Function()? rootDirectoryProvider,
  }) : _rootDirectoryProvider = rootDirectoryProvider;

  final Future<Directory> Function()? _rootDirectoryProvider;

  static const String artifactState2Version = 'artifact_state2_v1';
  static const String payloadEntryName = 'payload.json';
  static const String _cutoverMarkerFileName = 'cutover_initialized.json';
  static final DateTime _zipModifiedAt = DateTime.utc(1980, 1, 1);

  Future<StudentKpArtifactManifest> loadManifest(int remoteUserId) async {
    final file = await _manifestFile(remoteUserId);
    if (!file.existsSync()) {
      return StudentKpArtifactManifest.empty(remoteUserId);
    }
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final manifest = StudentKpArtifactManifest.fromJson(decoded);
    if (manifest.remoteUserId != remoteUserId) {
      return StudentKpArtifactManifest.empty(remoteUserId);
    }
    return manifest;
  }

  Future<void> saveManifest(StudentKpArtifactManifest manifest) async {
    final file = await _manifestFile(manifest.remoteUserId);
    file.parent.createSync(recursive: true);
    final items = manifest.items.values
        .where((item) => item.artifactId.isNotEmpty)
        .toList(growable: false)
      ..sort((left, right) => left.artifactId.compareTo(right.artifactId));
    final normalized = manifest.copyWith(
      state2: buildState2(items),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      items: <String, StudentKpArtifactManifestItem>{
        for (final item in items) item.artifactId: item,
      },
    );
    await file.writeAsString(jsonEncode(normalized.toJson()), flush: true);
  }

  Future<Uint8List?> readArtifactBytes({
    required int remoteUserId,
    required StudentKpArtifactManifestItem item,
  }) async {
    if (item.storageFile.trim().isEmpty || item.deleted) {
      return null;
    }
    final file = await _artifactFile(
      remoteUserId: remoteUserId,
      storageFile: item.storageFile,
    );
    if (!file.existsSync()) {
      return null;
    }
    return Uint8List.fromList(await file.readAsBytes());
  }

  Future<void> writeArtifactBytes({
    required int remoteUserId,
    required String storageFile,
    required Uint8List bytes,
  }) async {
    final file = await _artifactFile(
      remoteUserId: remoteUserId,
      storageFile: storageFile,
    );
    file.parent.createSync(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> deleteArtifactFile({
    required int remoteUserId,
    required String storageFile,
  }) async {
    final file = await _artifactFile(
      remoteUserId: remoteUserId,
      storageFile: storageFile,
    );
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<void> clearUserArtifacts(int remoteUserId) async {
    final dir = await _userRoot(remoteUserId);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  Future<bool> isCutoverInitialized() async {
    final marker = await _cutoverMarkerFile();
    return marker.existsSync();
  }

  Future<void> markCutoverInitialized() async {
    final marker = await _cutoverMarkerFile();
    marker.parent.createSync(recursive: true);
    await marker.writeAsString(
      jsonEncode(<String, dynamic>{
        'initialized_at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> clearAllArtifacts() async {
    final root = await _rootDirectory();
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  }

  String storageFileNameForArtifact(String artifactId) {
    final encoded =
        base64Url.encode(utf8.encode(artifactId)).replaceAll('=', '');
    return '$encoded.zip';
  }

  LocalArtifactBuildResult buildArtifact(LocalArtifactBuildInput input) {
    final payloadBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(_canonicalizeJson(input.payload)),
      ),
    );
    final archive = Archive();
    final file = ArchiveFile.noCompress(
      payloadEntryName,
      payloadBytes.length,
      payloadBytes,
    )
      ..mode = 0x180
      ..lastModTime = _zipModifiedAt.millisecondsSinceEpoch ~/ 1000
      ..crc32 = getCrc32(payloadBytes);
    archive.addFile(file);
    final zipBytes = ZipEncoder().encode(
      archive,
      level: 0,
      modified: _zipModifiedAt,
    );
    if (zipBytes == null || zipBytes.isEmpty) {
      throw StateError('Failed to encode student artifact zip.');
    }
    final digest = sha256.convert(zipBytes).toString();
    return LocalArtifactBuildResult(
      artifactId: input.artifactId.trim(),
      sha256: digest,
      lastModified: input.lastModified.toUtc().toIso8601String(),
      bytes: Uint8List.fromList(zipBytes),
    );
  }

  Map<String, dynamic> readPayload(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    for (final entry in archive) {
      if (!entry.isFile) {
        continue;
      }
      if (_normalizeArchivePath(entry.name) != payloadEntryName) {
        continue;
      }
      final content = entry.content;
      if (content is! List<int>) {
        throw StateError('Student artifact payload entry is unreadable.');
      }
      final decoded = jsonDecode(utf8.decode(content));
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Student artifact payload must be a JSON object.');
      }
      return decoded;
    }
    throw StateError('Student artifact payload.json missing.');
  }

  static String buildState2(Iterable<StudentKpArtifactManifestItem> items) {
    final normalized = items
        .where((item) =>
            !item.deleted &&
            item.artifactId.trim().isNotEmpty &&
            item.sha256.trim().isNotEmpty)
        .toList(growable: false)
      ..sort((left, right) => left.artifactId.compareTo(right.artifactId));
    final builder = StringBuffer();
    for (final item in normalized) {
      builder
        ..write(item.artifactId.trim())
        ..write('|')
        ..write(item.sha256.trim())
        ..write('\n');
    }
    return '$artifactState2Version:${sha256.convert(utf8.encode(builder.toString()))}';
  }

  static dynamic _canonicalizeJson(dynamic value) {
    if (value is Map) {
      final entries = value.entries
          .where((entry) => entry.key is String)
          .map((entry) =>
              MapEntry(entry.key as String, _canonicalizeJson(entry.value)))
          .where((entry) => entry.value != null)
          .toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
      return <String, dynamic>{
        for (final entry in entries) entry.key: entry.value,
      };
    }
    if (value is List) {
      return value
          .map(_canonicalizeJson)
          .where((entry) => entry != null)
          .toList(growable: false);
    }
    return value;
  }

  Future<File> _manifestFile(int remoteUserId) async {
    final dir = await _userRoot(remoteUserId);
    return File(p.join(dir.path, 'manifest.json'));
  }

  Future<File> _cutoverMarkerFile() async {
    final root = await _rootDirectory();
    return File(p.join(root.path, _cutoverMarkerFileName));
  }

  Future<File> _artifactFile({
    required int remoteUserId,
    required String storageFile,
  }) async {
    final dir = await _userRoot(remoteUserId);
    return File(p.join(dir.path, 'artifacts', storageFile));
  }

  Future<Directory> _userRoot(int remoteUserId) async {
    final root = await _rootDirectory();
    return Directory(p.join(root.path, '$remoteUserId'));
  }

  Future<Directory> _rootDirectory() async {
    if (_rootDirectoryProvider != null) {
      final root = await _rootDirectoryProvider();
      if (!root.existsSync()) {
        root.createSync(recursive: true);
      }
      return root;
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final root = Directory(
      p.join(
        docsDir.path,
        'sync_artifacts',
        'student_kp',
      ),
    );
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return root;
  }

  String _normalizeArchivePath(String input) {
    return input.replaceAll('\\', '/').trim();
  }
}
