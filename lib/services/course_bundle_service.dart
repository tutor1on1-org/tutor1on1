import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import 'file_system.dart';
import 'storage_directories.dart';

import '../models/skill_tree.dart';
import 'prompt_bundle_compat.dart';

class CourseKpDiffSummary {
  const CourseKpDiffSummary({
    required this.addedCount,
    required this.removedCount,
    required this.updatedCount,
  });

  final int addedCount;
  final int removedCount;
  final int updatedCount;

  bool get hasChanges => addedCount > 0 || removedCount > 0 || updatedCount > 0;
}

class CourseBundleSafetyLimits {
  const CourseBundleSafetyLimits({
    this.maxCompressedBytes = browserMaxCompressedBytes,
    this.maxUncompressedBytes = browserMaxUncompressedBytes,
    this.maxEntryCount = browserMaxEntryCount,
    this.maxExpansionRatio = browserMaxExpansionRatio,
  })  : assert(maxCompressedBytes > 0),
        assert(maxUncompressedBytes > 0),
        assert(maxEntryCount > 0),
        assert(maxExpansionRatio > 0);

  // The server accepts larger archival transfers, but the Chrome client fully
  // buffers ZIP input and therefore enforces a smaller memory-safe ceiling.
  static const int serverDefaultMaxBundleBytes = 1024 * 1024 * 1024;
  static const int browserMaxCompressedBytes = 64 * 1024 * 1024;
  static const int browserMaxUncompressedBytes = 256 * 1024 * 1024;
  static const int browserMaxEntryCount = 10000;
  static const int browserMaxExpansionRatio = 100;

  static const CourseBundleSafetyLimits defaults = CourseBundleSafetyLimits();

  final int maxCompressedBytes;
  final int maxUncompressedBytes;
  final int maxEntryCount;
  final int maxExpansionRatio;
}

class CourseBundleService {
  CourseBundleService({
    this.safetyLimits = CourseBundleSafetyLimits.defaults,
  });

  static const String promptMetadataEntryPath = kCurrentPromptMetadataEntryPath;
  static const int _backgroundBundleThresholdBytes = 256 * 1024;
  static const List<String> _questionLevels = <String>[
    'easy',
    'medium',
    'hard',
  ];
  static final RegExp _idPattern = RegExp(r'^(\d+(?:\.\d+)*)\s*(.+)$');

  final CourseBundleSafetyLimits safetyLimits;

  void validateCompressedByteLength(int byteLength) {
    if (byteLength < 0 || byteLength > safetyLimits.maxCompressedBytes) {
      throw FormatException(
        'Course bundle exceeds the '
        '${safetyLimits.maxCompressedBytes}-byte compressed limit.',
      );
    }
  }

  Future<File> createBundleFromFolder(
    String folderPath, {
    Map<String, dynamic>? promptMetadata,
  }) async {
    final normalized = p.normalize(folderPath);
    final folder = Directory(normalized);
    if (!folder.existsSync()) {
      throw StateError('Course folder not found: $normalized');
    }
    final requiredEntries = await _collectRequiredBundleEntries(normalized);
    final tempDir = await getTemporaryDirectory();
    await tempDir.create(recursive: true);
    final safeName = _sanitizeName(p.basename(normalized));
    final zipPath = p.join(
      tempDir.path,
      'bundle_${safeName}_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    final archive = Archive();
    for (final entry in requiredEntries) {
      final bytes = await entry.file.readAsBytes();
      archive.addFile(
        ArchiveFile(entry.archivePath, bytes.length, bytes),
      );
    }
    if (promptMetadata != null) {
      final bytes = utf8.encode(jsonEncode(promptMetadata));
      archive.addFile(
        ArchiveFile(promptMetadataEntryPath, bytes.length, bytes),
      );
    }
    final encoded = ZipEncoder().encode(archive);
    archive.clearSync();
    if (encoded == null) {
      throw StateError('Failed to encode course bundle.');
    }
    final bundleFile = File(zipPath);
    await bundleFile.writeAsBytes(encoded, flush: true);
    await validateBundleForImport(bundleFile);
    return bundleFile;
  }

  Future<String> createTempBundlePath({String? label}) async {
    final tempDir = await getTemporaryDirectory();
    await tempDir.create(recursive: true);
    final safeName = _sanitizeName(label ?? 'course');
    return p.join(
      tempDir.path,
      'bundle_${safeName}_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
  }

  Future<String> extractBundleFromFile({
    required File bundleFile,
    required String courseName,
  }) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }
    final root = await _ensureDownloadRoot();
    final safeName = _sanitizeName(courseName);
    final targetPath = p.join(
      root.path,
      '${safeName}_${DateTime.now().millisecondsSinceEpoch}',
    );
    final targetDir = Directory(targetPath);
    targetDir.createSync(recursive: true);
    final archive = _decodeBundle(await _readBundleBytes(bundleFile));
    try {
      await _extractArchiveSafely(archive, targetPath);
    } finally {
      archive.clearSync();
    }
    return _resolveExtractedCourseRoot(targetPath);
  }

  Future<String> extractBundleScaffoldFromFile({
    required File bundleFile,
    required String courseName,
  }) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }
    final root = await _ensureDownloadRoot();
    final safeName = _sanitizeName(courseName);
    final targetPath = p.join(
      root.path,
      '${safeName}_${DateTime.now().millisecondsSinceEpoch}',
    );
    final targetDir = Directory(targetPath);
    targetDir.createSync(recursive: true);
    final indexed = _indexBundleArchive(await _readBundleBytes(bundleFile));
    final contentsBytes = indexed.entryByName[indexed.selectedContentsName];
    if (contentsBytes == null) {
      throw StateError('Bundle is missing contents.txt or context.txt.');
    }
    await File(p.join(targetPath, 'contents.txt')).writeAsBytes(
      contentsBytes,
      flush: true,
    );
    if (indexed.selectedContextName.isNotEmpty) {
      final contextBytes = indexed.entryByName[indexed.selectedContextName];
      if (contextBytes != null) {
        await File(p.join(targetPath, 'context.txt')).writeAsBytes(
          contextBytes,
          flush: true,
        );
      }
    }
    return targetPath;
  }

  Future<Map<String, dynamic>?> readPromptMetadataFromBundleFile(
    File bundleFile,
  ) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }
    final bytes = await _readBundleBytes(bundleFile);
    if (kIsWeb || bundleFile.lengthSync() < _backgroundBundleThresholdBytes) {
      return _readPromptMetadataFromBytes(bytes);
    }
    final limits = safetyLimits;
    return Isolate.run<Map<String, dynamic>?>(() {
      return CourseBundleService(
        safetyLimits: limits,
      )._readPromptMetadataFromBytes(bytes);
    });
  }

  Future<String> extractBundleFromBytes({
    required Uint8List bytes,
    required String courseName,
  }) async {
    final root = await _ensureDownloadRoot();
    final safeName = _sanitizeName(courseName);
    final targetPath = p.join(
      root.path,
      '${safeName}_${DateTime.now().millisecondsSinceEpoch}',
    );
    final targetDir = Directory(targetPath);
    targetDir.createSync(recursive: true);
    final archive = _decodeBundle(bytes);
    try {
      await _extractArchiveSafely(archive, targetPath);
    } finally {
      archive.clearSync();
    }
    return _resolveExtractedCourseRoot(targetPath);
  }

  Future<void> validateBundleForImport(File bundleFile) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }
    final bytes = await _readBundleBytes(bundleFile);
    if (kIsWeb || bundleFile.lengthSync() < _backgroundBundleThresholdBytes) {
      _validateBundleForImportBytes(bytes);
      return;
    }
    final limits = safetyLimits;
    await Isolate.run<void>(() {
      CourseBundleService(
        safetyLimits: limits,
      )._validateBundleForImportBytes(bytes);
    });
  }

  Future<String> computeBundleSemanticHash(File bundleFile) async {
    return computeBundleSemanticHashFromBundle(bundleFile);
  }

  Future<String> computeBundleByteHash(File bundleFile) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }
    final bytes = await _readBundleBytes(bundleFile);
    return sha256.convert(bytes).toString();
  }

  Future<String> computeBundleSemanticHashFromBundle(
    File bundleFile, {
    Map<String, dynamic>? promptMetadataOverride,
  }) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }
    final bytes = await _readBundleBytes(bundleFile);
    final normalizedOverride = promptMetadataOverride == null
        ? null
        : Map<String, dynamic>.from(promptMetadataOverride);
    if (kIsWeb || bundleFile.lengthSync() < _backgroundBundleThresholdBytes) {
      return _computeBundleSemanticHashFromBytes(
        bytes,
        promptMetadataOverride: normalizedOverride,
      );
    }
    final limits = safetyLimits;
    return Isolate.run<String>(() {
      return CourseBundleService(safetyLimits: limits)
          ._computeBundleSemanticHashFromBytes(
        bytes,
        promptMetadataOverride: normalizedOverride,
      );
    });
  }

  Future<String?> readTextEntryFromBundleFile({
    required File bundleFile,
    required List<String> candidateRelativePaths,
  }) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }
    final normalizedCandidates = candidateRelativePaths
        .map(_normalizeArchivePath)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalizedCandidates.isEmpty) {
      return null;
    }
    final indexed = _indexBundleArchive(await _readBundleBytes(bundleFile));
    final candidateNames = <String>{
      ...normalizedCandidates,
      if (indexed.selectedRoot.isNotEmpty)
        ...normalizedCandidates.map(
            (value) => _normalizeArchivePath('${indexed.selectedRoot}/$value')),
    };
    for (final name in candidateNames) {
      final entryBytes = indexed.entryByName[name];
      if (entryBytes == null) {
        continue;
      }
      return utf8.decode(entryBytes);
    }
    return null;
  }

  Map<String, dynamic>? _readPromptMetadataFromBytes(List<int> bytes) {
    Archive? archive;
    try {
      archive = _decodeBundle(bytes);
      for (final file in archive) {
        if (!file.isFile) {
          continue;
        }
        final normalizedName = p.normalize(file.name).replaceAll('\\', '/');
        if (!isSupportedPromptMetadataEntryPath(normalizedName)) {
          continue;
        }
        final content = utf8.decode(file.content as List<int>);
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw StateError('Prompt metadata is invalid.');
      }
      return null;
    } finally {
      archive?.clearSync();
    }
  }

  void _validateBundleForImportBytes(List<int> bytes) {
    Archive? archive;
    try {
      archive = _decodeBundle(bytes);

      final fileEntries = archive.files.where((entry) {
        if (!entry.isFile) {
          return false;
        }
        final normalized = _normalizeArchivePath(entry.name);
        if (normalized.isEmpty) {
          return false;
        }
        if (isSupportedPromptMetadataEntryPath(normalized)) {
          return false;
        }
        if (normalized.startsWith('__MACOSX/')) {
          return false;
        }
        final segments = normalized.split('/');
        if (segments.any((segment) => segment.startsWith('._'))) {
          return false;
        }
        return true;
      }).toList();

      if (fileEntries.isEmpty) {
        throw StateError('Bundle is empty or contains only metadata files.');
      }

      final names = fileEntries
          .map((entry) => _normalizeArchivePath(entry.name))
          .where((name) => name.isNotEmpty)
          .toSet();
      final entryByName = <String, ArchiveFile>{};
      for (final entry in fileEntries) {
        final normalized = _normalizeArchivePath(entry.name);
        if (normalized.isNotEmpty) {
          entryByName[normalized] = entry;
        }
      }

      final roots = _candidateRoots(names);
      if (roots.isEmpty) {
        throw StateError('Bundle is missing contents.txt or context.txt.');
      }

      var selectedRoot = '';
      var selectedContentsName = '';
      for (final root in roots) {
        final contentsName =
            root.isEmpty ? 'contents.txt' : '$root/contents.txt';
        final contextName = root.isEmpty ? 'context.txt' : '$root/context.txt';
        if (entryByName.containsKey(contentsName)) {
          selectedRoot = root;
          selectedContentsName = contentsName;
          break;
        }
        if (entryByName.containsKey(contextName)) {
          selectedRoot = root;
          selectedContentsName = contextName;
          break;
        }
      }

      if (selectedContentsName.isEmpty) {
        throw StateError('Bundle is missing contents.txt or context.txt.');
      }

      final contentsEntry = entryByName[selectedContentsName];
      if (contentsEntry == null) {
        throw StateError('Bundle is missing contents.txt or context.txt.');
      }

      final contentsBytes = _entryBytes(contentsEntry);
      final contentsText = utf8.decode(contentsBytes);
      final parser = SkillTreeParser();
      final parseResult = parser.parse(contentsText);
      if (parseResult.nodes.isEmpty) {
        throw StateError('Bundle contents has no skill nodes.');
      }

      final missingLectures = <String>[];
      for (final node in parseResult.nodes.values) {
        if (node.isPlaceholder) {
          continue;
        }
        final lectureName = selectedRoot.isEmpty
            ? '${node.id}_lecture.txt'
            : '$selectedRoot/${node.id}_lecture.txt';
        final legacyLectureName = selectedRoot.isEmpty
            ? '${node.id}/lecture.txt'
            : '$selectedRoot/${node.id}/lecture.txt';
        if (!names.contains(lectureName) &&
            !names.contains(legacyLectureName)) {
          missingLectures.add(node.id);
        }
      }

      if (missingLectures.isNotEmpty) {
        throw StateError(
          'Bundle is missing lecture files for ids: ${missingLectures.join(', ')}',
        );
      }
    } finally {
      archive?.clearSync();
    }
  }

  String _computeBundleSemanticHashFromBytes(
    List<int> bytes, {
    Map<String, dynamic>? promptMetadataOverride,
  }) {
    Archive? archive;
    try {
      archive = _decodeBundle(bytes);
      final files = <_BundleSemanticFile>[];
      var sawPromptMetadata = false;
      for (final entry in archive.files) {
        if (!entry.isFile) {
          continue;
        }
        final name = _normalizeArchivePath(entry.name);
        if (name.isEmpty) {
          continue;
        }
        if (name.startsWith('__MACOSX/')) {
          continue;
        }
        if (_hasAppleDoubleSegment(name)) {
          continue;
        }
        var semanticName = name;
        var data = _entryBytes(entry);
        if (isSupportedPromptMetadataEntryPath(name)) {
          sawPromptMetadata = true;
          semanticName = promptMetadataEntryPath;
          if (promptMetadataOverride != null) {
            continue;
          }
          data = _normalizePromptMetadataBytes(data);
        }
        files.add(_BundleSemanticFile(name: semanticName, data: data));
      }
      if (promptMetadataOverride != null) {
        files.add(
          _BundleSemanticFile(
            name: promptMetadataEntryPath,
            data: _normalizePromptMetadataJsonForSemanticHash(
              promptMetadataOverride,
            ),
          ),
        );
      } else if (!sawPromptMetadata) {
        files.add(
          _BundleSemanticFile(
            name: promptMetadataEntryPath,
            data: _normalizePromptMetadataJsonForSemanticHash(
              _emptyPromptMetadataDocument(),
            ),
          ),
        );
      }
      files.sort((left, right) => left.name.compareTo(right.name));

      final digestCollector = _DigestCollector();
      final sink = sha256.startChunkedConversion(digestCollector);
      for (final file in files) {
        sink.add(utf8.encode(file.name));
        sink.add(const <int>[0]);
        sink.add(file.data);
        sink.add(const <int>[0]);
      }
      sink.close();
      final digest = digestCollector.digest;
      if (digest == null) {
        throw StateError('Failed to compute semantic hash.');
      }
      return digest.toString();
    } finally {
      archive?.clearSync();
    }
  }

  List<int> _cloneBundleWithPromptMetadataBytes({
    required List<int> sourceBytes,
    Map<String, dynamic>? promptMetadata,
  }) {
    Archive? sourceArchive;
    Archive? archive;
    try {
      sourceArchive = _decodeBundle(sourceBytes);
      archive = Archive();
      for (final entry in sourceArchive.files) {
        if (!entry.isFile) {
          continue;
        }
        final normalizedName = _normalizeArchivePath(entry.name);
        if (normalizedName.isEmpty) {
          continue;
        }
        if (isSupportedPromptMetadataEntryPath(normalizedName)) {
          if (promptMetadata == null) {
            archive.addFile(
              ArchiveFile(
                entry.name,
                entry.size,
                _entryBytes(entry),
              ),
            );
          }
          continue;
        }
        archive.addFile(
          ArchiveFile(
            entry.name,
            entry.size,
            _entryBytes(entry),
          ),
        );
      }
      if (promptMetadata != null) {
        final normalizedBytes = normalizePromptMetadataJson(promptMetadata);
        archive.addFile(
          ArchiveFile(
            promptMetadataEntryPath,
            normalizedBytes.length,
            normalizedBytes,
          ),
        );
      }
      final bytes = ZipEncoder().encode(archive);
      if (bytes == null) {
        throw StateError('Failed to encode cached course bundle.');
      }
      return bytes;
    } finally {
      archive?.clearSync();
      sourceArchive?.clearSync();
    }
  }

  Future<File> cloneBundleWithPromptMetadata({
    required File sourceBundle,
    Map<String, dynamic>? promptMetadata,
    String? label,
  }) async {
    if (!sourceBundle.existsSync()) {
      throw StateError('Bundle file not found: ${sourceBundle.path}');
    }
    final targetPath = await createTempBundlePath(label: label);
    final targetFile = File(targetPath);
    final sourceBytes = await _readBundleBytes(sourceBundle);
    final normalizedPromptMetadata = promptMetadata == null
        ? null
        : Map<String, dynamic>.from(promptMetadata);
    if (kIsWeb || sourceBundle.lengthSync() < _backgroundBundleThresholdBytes) {
      final bytes = _cloneBundleWithPromptMetadataBytes(
        sourceBytes: sourceBytes,
        promptMetadata: normalizedPromptMetadata,
      );
      await targetFile.writeAsBytes(bytes, flush: true);
      await validateBundleForImport(targetFile);
      return targetFile;
    }
    final limits = safetyLimits;
    final bytes = await Isolate.run<List<int>>(() {
      return CourseBundleService(safetyLimits: limits)
          ._cloneBundleWithPromptMetadataBytes(
        sourceBytes: sourceBytes,
        promptMetadata: normalizedPromptMetadata,
      );
    });
    await targetFile.writeAsBytes(bytes, flush: true);
    await validateBundleForImport(targetFile);
    return targetFile;
  }

  Future<CourseKpDiffSummary> compareCourseFolderWithBundle({
    required String folderPath,
    required File bundleFile,
  }) async {
    final localSnapshot = await _loadFolderSnapshot(folderPath);
    final remoteSnapshot = await _loadBundleSnapshot(bundleFile);

    final localIds = localSnapshot.kpFingerprints.keys.toSet();
    final remoteIds = remoteSnapshot.kpFingerprints.keys.toSet();
    final added = localIds.difference(remoteIds).length;
    final removed = remoteIds.difference(localIds).length;
    var updated = 0;
    for (final kpId in localIds.intersection(remoteIds)) {
      if (localSnapshot.kpFingerprints[kpId] !=
          remoteSnapshot.kpFingerprints[kpId]) {
        updated++;
      }
    }
    return CourseKpDiffSummary(
      addedCount: added,
      removedCount: removed,
      updatedCount: updated,
    );
  }

  Future<Directory> _ensureDownloadRoot() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'downloaded_courses'));
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return root;
  }

  _IndexedBundleArchive _indexBundleArchive(List<int> bytes) {
    Archive? archive;
    try {
      archive = _decodeBundle(bytes);
      final entryByName = <String, List<int>>{};
      for (final entry in archive.files) {
        if (!entry.isFile) {
          continue;
        }
        final name = _normalizeArchivePath(entry.name);
        if (name.isEmpty) {
          continue;
        }
        if (name.startsWith('__MACOSX/')) {
          continue;
        }
        if (_hasAppleDoubleSegment(name)) {
          continue;
        }
        entryByName[name] = _entryBytes(entry);
      }
      if (entryByName.isEmpty) {
        throw StateError('Bundle is empty or contains only metadata files.');
      }
      final roots = _candidateRoots(
        entryByName.keys
            .where((name) => !isSupportedPromptMetadataEntryPath(name))
            .toSet(),
      );
      if (roots.isEmpty) {
        throw StateError('Bundle is missing contents.txt or context.txt.');
      }
      var selectedRoot = '';
      var selectedContentsName = '';
      var selectedContextName = '';
      for (final root in roots) {
        final contentsName =
            root.isEmpty ? 'contents.txt' : '$root/contents.txt';
        final contextName = root.isEmpty ? 'context.txt' : '$root/context.txt';
        if (entryByName.containsKey(contentsName)) {
          selectedRoot = root;
          selectedContentsName = contentsName;
          selectedContextName =
              entryByName.containsKey(contextName) ? contextName : '';
          break;
        }
        if (entryByName.containsKey(contextName)) {
          selectedRoot = root;
          selectedContentsName = contextName;
          selectedContextName = contextName;
          break;
        }
      }
      if (selectedContentsName.isEmpty) {
        throw StateError('Bundle is missing contents.txt or context.txt.');
      }
      return _IndexedBundleArchive(
        entryByName: entryByName,
        selectedRoot: selectedRoot,
        selectedContentsName: selectedContentsName,
        selectedContextName: selectedContextName,
      );
    } finally {
      archive?.clearSync();
    }
  }

  Future<Uint8List> _readBundleBytes(File bundleFile) async {
    validateCompressedByteLength(bundleFile.lengthSync());
    final bytes = await bundleFile.readAsBytes();
    validateCompressedByteLength(bytes.length);
    return bytes;
  }

  Archive _decodeBundle(List<int> bytes) {
    validateCompressedByteLength(bytes.length);
    _preflightZipDirectory(bytes);
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    try {
      _validateArchiveMetadata(archive);
      _validateArchivePaths(archive);
      return _materializeArchiveSafely(archive);
    } catch (_) {
      archive.clearSync();
      rethrow;
    }
  }

  void _validateArchiveMetadata(Archive archive) {
    if (archive.files.length > safetyLimits.maxEntryCount) {
      throw FormatException(
        'Course bundle contains more than '
        '${safetyLimits.maxEntryCount} entries.',
      );
    }
    var totalUncompressedBytes = 0;
    for (final entry in archive.files) {
      final uncompressedBytes = entry.size;
      final compressedBytes = entry.rawContent?.length ?? 0;
      if (uncompressedBytes < 0 || compressedBytes < 0) {
        throw const FormatException('Course bundle has an invalid entry size.');
      }
      totalUncompressedBytes += uncompressedBytes;
      if (totalUncompressedBytes > safetyLimits.maxUncompressedBytes) {
        throw FormatException(
          'Course bundle exceeds the '
          '${safetyLimits.maxUncompressedBytes}-byte uncompressed limit.',
        );
      }
      _validateExpansionRatio(
        uncompressedBytes: uncompressedBytes,
        compressedBytes: compressedBytes,
      );
    }
  }

  Archive _materializeArchiveSafely(Archive archive) {
    final materialized = Archive();
    var totalUncompressedBytes = 0;
    try {
      for (final entry in archive.files) {
        final content = _materializeEntrySafely(entry);
        totalUncompressedBytes += content.length;
        if (totalUncompressedBytes > safetyLimits.maxUncompressedBytes) {
          throw FormatException(
            'Course bundle exceeds the '
            '${safetyLimits.maxUncompressedBytes}-byte uncompressed limit.',
          );
        }
        final safeEntry = ArchiveFile(entry.name, content.length, content)
          ..mode = entry.mode
          ..ownerId = entry.ownerId
          ..groupId = entry.groupId
          ..lastModTime = entry.lastModTime
          ..isFile = entry.isFile
          ..isSymbolicLink = entry.isSymbolicLink
          ..nameOfLinkedFile = entry.nameOfLinkedFile
          ..crc32 = entry.crc32
          ..comment = entry.comment
          ..compress = entry.compress;
        materialized.addFile(safeEntry);
      }
      archive.clearSync();
      return materialized;
    } catch (_) {
      materialized.clearSync();
      rethrow;
    }
  }

  Uint8List _materializeEntrySafely(ArchiveFile entry) {
    final rawContent = entry.rawContent;
    if (rawContent == null) {
      throw const FormatException('Course bundle entry could not be read.');
    }
    final output = _BoundedOutputStream(entry.size);
    try {
      switch (entry.compressionType) {
        case ArchiveFile.STORE:
          output.writeInputStream(rawContent);
          break;
        case ArchiveFile.DEFLATE:
          Inflate.stream(rawContent, output);
          break;
        default:
          throw FormatException(
            'Course bundle uses an unsupported compression method: '
            '${entry.compressionType}',
          );
      }
    } on FormatException {
      rethrow;
    } on RangeError catch (error) {
      throw FormatException(
        'Course bundle entry is malformed: ${entry.name} ($error)',
      );
    } on StateError catch (error) {
      throw FormatException(
        'Course bundle entry is malformed: ${entry.name} ($error)',
      );
    }
    if (output.length != entry.size) {
      throw FormatException(
        'Course bundle entry size mismatch: ${entry.name}',
      );
    }
    final content = output.bytes;
    final expectedCrc = entry.crc32;
    if (expectedCrc != null && getCrc32(content) != expectedCrc) {
      throw FormatException('Course bundle entry CRC failed: ${entry.name}');
    }
    return content;
  }

  void _validateExpansionRatio({
    required int uncompressedBytes,
    required int compressedBytes,
  }) {
    if (uncompressedBytes == 0) {
      return;
    }
    if (compressedBytes == 0 ||
        uncompressedBytes > compressedBytes * safetyLimits.maxExpansionRatio) {
      throw FormatException(
        'Course bundle exceeds the '
        '${safetyLimits.maxExpansionRatio}:1 expansion-ratio limit.',
      );
    }
  }

  void _preflightZipDirectory(List<int> bytes) {
    const eocdSignature = 0x06054b50;
    const zip64LocatorSignature = 0x07064b50;
    const zip64EocdSignature = 0x06064b50;
    const centralDirectoryEntrySignature = 0x02014b50;
    const centralDirectoryDigitalSignature = 0x05054b50;
    const localFileHeaderSignature = 0x04034b50;
    const eocdSize = 22;
    const maximumZipCommentBytes = 0xffff;
    const centralDirectoryEntrySize = 46;
    const localFileHeaderSize = 30;

    if (bytes.length < eocdSize) {
      throw const FormatException('Course bundle is not a valid ZIP archive.');
    }
    final minimumOffset = bytes.length - eocdSize - maximumZipCommentBytes;
    var eocdOffset = -1;
    for (var offset = bytes.length - eocdSize;
        offset >= (minimumOffset < 0 ? 0 : minimumOffset);
        offset--) {
      if (_readUint32(bytes, offset) != eocdSignature) {
        continue;
      }
      final commentLength = _readUint16(bytes, offset + 20);
      if (offset + eocdSize + commentLength == bytes.length) {
        eocdOffset = offset;
        break;
      }
    }
    if (eocdOffset < 0) {
      throw const FormatException('Course bundle is not a valid ZIP archive.');
    }

    var declaredEntryCount = _readUint16(bytes, eocdOffset + 10);
    var directorySize = _readUint32(bytes, eocdOffset + 12);
    var directoryOffset = _readUint32(bytes, eocdOffset + 16);
    final zip64LocatorOffset = eocdOffset - 20;
    final hasZip64Locator = zip64LocatorOffset >= 0 &&
        _readUint32(bytes, zip64LocatorOffset) == zip64LocatorSignature;
    if (hasZip64Locator) {
      final zip64OffsetHigh = _readUint32(bytes, zip64LocatorOffset + 12);
      final zip64Offset = _readUint32(bytes, zip64LocatorOffset + 8);
      if (zip64OffsetHigh != 0 ||
          zip64Offset + 56 > bytes.length ||
          _readUint32(bytes, zip64Offset) != zip64EocdSignature) {
        throw const FormatException('Course bundle has invalid ZIP64 data.');
      }
      final entryCountHigh = _readUint32(bytes, zip64Offset + 36);
      if (entryCountHigh != 0) {
        throw FormatException(
          'Course bundle contains more than '
          '${safetyLimits.maxEntryCount} entries.',
        );
      }
      declaredEntryCount = _readUint32(bytes, zip64Offset + 32);
      final directorySizeHigh = _readUint32(bytes, zip64Offset + 44);
      final directoryOffsetHigh = _readUint32(bytes, zip64Offset + 52);
      if (directorySizeHigh != 0 || directoryOffsetHigh != 0) {
        throw const FormatException('Course bundle ZIP64 data is too large.');
      }
      directorySize = _readUint32(bytes, zip64Offset + 40);
      directoryOffset = _readUint32(bytes, zip64Offset + 48);
    }
    if (declaredEntryCount > safetyLimits.maxEntryCount) {
      throw FormatException(
        'Course bundle contains more than '
        '${safetyLimits.maxEntryCount} entries.',
      );
    }

    final directoryEnd = directoryOffset + directorySize;
    if (directoryOffset < 0 ||
        directoryEnd < directoryOffset ||
        directoryEnd > eocdOffset) {
      throw const FormatException(
        'Course bundle has an invalid central directory.',
      );
    }
    var entryCount = 0;
    var totalUncompressedBytes = 0;
    var offset = directoryOffset;
    while (offset < directoryEnd) {
      if (offset + 4 > directoryEnd) {
        throw const FormatException(
          'Course bundle has an invalid central directory.',
        );
      }
      final signature = _readUint32(bytes, offset);
      if (signature == centralDirectoryDigitalSignature) {
        if (offset + 6 > directoryEnd) {
          throw const FormatException(
            'Course bundle has an invalid central directory.',
          );
        }
        offset += 6 + _readUint16(bytes, offset + 4);
        continue;
      }
      if (signature != centralDirectoryEntrySignature ||
          offset + centralDirectoryEntrySize > directoryEnd) {
        throw const FormatException(
          'Course bundle has an invalid central directory.',
        );
      }
      final versionMadeBy = _readUint16(bytes, offset + 4);
      final flags = _readUint16(bytes, offset + 8);
      final compressionMethod = _readUint16(bytes, offset + 10);
      final expectedCrc = _readUint32(bytes, offset + 16);
      final compressedBytes = _readUint32(bytes, offset + 20);
      final uncompressedBytes = _readUint32(bytes, offset + 24);
      if (compressedBytes == 0xffffffff || uncompressedBytes == 0xffffffff) {
        throw const FormatException(
          'Course bundle ZIP64 entries exceed browser safety limits.',
        );
      }
      totalUncompressedBytes += uncompressedBytes;
      if (totalUncompressedBytes > safetyLimits.maxUncompressedBytes) {
        throw FormatException(
          'Course bundle exceeds the '
          '${safetyLimits.maxUncompressedBytes}-byte uncompressed limit.',
        );
      }
      _validateExpansionRatio(
        uncompressedBytes: uncompressedBytes,
        compressedBytes: compressedBytes,
      );
      final fileNameLength = _readUint16(bytes, offset + 28);
      final extraFieldLength = _readUint16(bytes, offset + 30);
      final commentLength = _readUint16(bytes, offset + 32);
      final externalFileAttributes = _readUint32(bytes, offset + 38);
      final localHeaderOffset = _readUint32(bytes, offset + 42);
      if ((flags & 0x41) != 0) {
        throw const FormatException(
          'Encrypted course bundle entries are not supported.',
        );
      }
      if (compressionMethod != ArchiveFile.STORE &&
          compressionMethod != ArchiveFile.DEFLATE) {
        throw FormatException(
          'Course bundle uses an unsupported compression method: '
          '$compressionMethod',
        );
      }
      final creatorSystem = versionMadeBy >> 8;
      final unixFileType = (externalFileAttributes >> 16) & 0xf000;
      if (creatorSystem == 3 && unixFileType == 0xa000) {
        throw const FormatException(
          'Course bundle symbolic links are not supported.',
        );
      }
      _validateLocalZipEntry(
        bytes,
        localHeaderOffset: localHeaderOffset,
        centralDirectoryOffset: directoryOffset,
        flags: flags,
        compressionMethod: compressionMethod,
        expectedCrc: expectedCrc,
        compressedBytes: compressedBytes,
        uncompressedBytes: uncompressedBytes,
        localFileHeaderSignature: localFileHeaderSignature,
        localFileHeaderSize: localFileHeaderSize,
      );
      offset += centralDirectoryEntrySize +
          fileNameLength +
          extraFieldLength +
          commentLength;
      if (offset > directoryEnd) {
        throw const FormatException(
          'Course bundle has an invalid central directory.',
        );
      }
      entryCount++;
      if (entryCount > safetyLimits.maxEntryCount) {
        throw FormatException(
          'Course bundle contains more than '
          '${safetyLimits.maxEntryCount} entries.',
        );
      }
    }
    if (offset != directoryEnd || entryCount != declaredEntryCount) {
      throw const FormatException(
        'Course bundle central-directory entry count is invalid.',
      );
    }
  }

  void _validateLocalZipEntry(
    List<int> bytes, {
    required int localHeaderOffset,
    required int centralDirectoryOffset,
    required int flags,
    required int compressionMethod,
    required int expectedCrc,
    required int compressedBytes,
    required int uncompressedBytes,
    required int localFileHeaderSignature,
    required int localFileHeaderSize,
  }) {
    if (localHeaderOffset < 0 ||
        localHeaderOffset + localFileHeaderSize > centralDirectoryOffset ||
        _readUint32(bytes, localHeaderOffset) != localFileHeaderSignature) {
      throw const FormatException(
        'Course bundle has an invalid local file header.',
      );
    }
    final localFlags = _readUint16(bytes, localHeaderOffset + 6);
    final localCompressionMethod = _readUint16(bytes, localHeaderOffset + 8);
    if (localFlags != flags || localCompressionMethod != compressionMethod) {
      throw const FormatException(
        'Course bundle local and central headers do not match.',
      );
    }
    final localFileNameLength = _readUint16(bytes, localHeaderOffset + 26);
    final localExtraFieldLength = _readUint16(bytes, localHeaderOffset + 28);
    final dataOffset = localHeaderOffset +
        localFileHeaderSize +
        localFileNameLength +
        localExtraFieldLength;
    final dataEnd = dataOffset + compressedBytes;
    if (dataOffset < localHeaderOffset ||
        dataEnd < dataOffset ||
        dataEnd > centralDirectoryOffset) {
      throw const FormatException(
        'Course bundle compressed entry data is truncated.',
      );
    }
    if ((flags & 0x08) == 0) {
      if (_readUint32(bytes, localHeaderOffset + 14) != expectedCrc ||
          _readUint32(bytes, localHeaderOffset + 18) != compressedBytes ||
          _readUint32(bytes, localHeaderOffset + 22) != uncompressedBytes) {
        throw const FormatException(
          'Course bundle local and central entry sizes do not match.',
        );
      }
      return;
    }

    var descriptorOffset = dataEnd;
    if (descriptorOffset + 12 > centralDirectoryOffset) {
      throw const FormatException(
        'Course bundle data descriptor is truncated.',
      );
    }
    if (_readUint32(bytes, descriptorOffset) == 0x08074b50) {
      descriptorOffset += 4;
      if (descriptorOffset + 12 > centralDirectoryOffset) {
        throw const FormatException(
          'Course bundle data descriptor is truncated.',
        );
      }
    }
    if (_readUint32(bytes, descriptorOffset) != expectedCrc ||
        _readUint32(bytes, descriptorOffset + 4) != compressedBytes ||
        _readUint32(bytes, descriptorOffset + 8) != uncompressedBytes) {
      throw const FormatException(
        'Course bundle data descriptor does not match its central header.',
      );
    }
  }

  int _readUint16(List<int> bytes, int offset) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw const FormatException('Course bundle ZIP data is truncated.');
    }
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  int _readUint32(List<int> bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw const FormatException('Course bundle ZIP data is truncated.');
    }
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  Future<void> _extractArchiveSafely(
    Archive archive,
    String targetPath,
  ) async {
    final normalizedTarget = p.normalize(targetPath);
    for (final entry in archive.files) {
      final normalizedName = _normalizeArchivePath(entry.name);
      if (normalizedName.isEmpty || normalizedName == '.') {
        continue;
      }
      final destination = p.normalize(
        p.joinAll(<String>[
          normalizedTarget,
          ...p.posix.split(normalizedName),
        ]),
      );
      if (!p.isWithin(normalizedTarget, destination)) {
        throw FormatException('Bundle contains invalid path: ${entry.name}');
      }
      if (!entry.isFile) {
        await Directory(destination).create(recursive: true);
        continue;
      }
      final output = File(destination);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(_entryBytes(entry), flush: true);
    }
  }

  void _validateArchivePaths(Archive archive) {
    for (final entry in archive) {
      final rawName = entry.name;
      final posixName = rawName.replaceAll('\\', '/');
      final segments = posixName.split('/');
      final invalid = rawName.contains('\u0000') ||
          p.posix.isAbsolute(posixName) ||
          p.windows.isAbsolute(rawName) ||
          segments.contains('..') ||
          segments.any((segment) => segment.contains(':')) ||
          entry.isSymbolicLink;
      if (invalid) {
        throw FormatException('Bundle contains invalid path: $rawName');
      }
    }
  }

  String _resolveExtractedCourseRoot(String extractedRootPath) {
    if (_hasContentsAtRoot(extractedRootPath)) {
      return extractedRootPath;
    }
    final rootDir = Directory(extractedRootPath);
    if (!rootDir.existsSync()) {
      return extractedRootPath;
    }
    final candidates = rootDir
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((dir) => _hasContentsAtRoot(dir.path))
        .toList();
    if (candidates.length == 1) {
      return candidates.first.path;
    }
    return extractedRootPath;
  }

  bool _hasContentsAtRoot(String rootPath) {
    final contents = File(p.join(rootPath, 'contents.txt'));
    if (contents.existsSync()) {
      return true;
    }
    final context = File(p.join(rootPath, 'context.txt'));
    return context.existsSync();
  }

  Set<String> _candidateRoots(Set<String> names) {
    final roots = <String>{};
    for (final name in names) {
      if (name == 'contents.txt' || name == 'context.txt') {
        roots.add('');
        continue;
      }
      if (name.endsWith('/contents.txt') || name.endsWith('/context.txt')) {
        final idx = name.lastIndexOf('/');
        if (idx > 0) {
          roots.add(name.substring(0, idx));
        }
      }
    }
    return roots;
  }

  String _normalizeArchivePath(String input) {
    return p
        .normalize(input)
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
  }

  bool _hasAppleDoubleSegment(String name) {
    final segments = name.split('/');
    return segments.any((segment) => segment.startsWith('._'));
  }

  List<int> _entryBytes(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) {
      return content;
    }
    if (content is List<int>) {
      return List<int>.from(content);
    }
    throw StateError('Unsupported archive entry content type.');
  }

  String _sanitizeName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'course';
    }
    final sanitized = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    if (sanitized.isEmpty) {
      return 'course';
    }
    return sanitized;
  }

  Future<List<_BundleFolderEntry>> _collectRequiredBundleEntries(
    String folderPath,
  ) async {
    final contentsFile = File(p.join(folderPath, 'contents.txt'));
    final contextFile = File(p.join(folderPath, 'context.txt'));
    final hasContents = contentsFile.existsSync();
    final hasContext = contextFile.existsSync();
    if (!hasContents && !hasContext) {
      throw StateError(
        'Missing file: ${p.join(folderPath, 'contents.txt')} '
        '(or ${p.join(folderPath, 'context.txt')})',
      );
    }
    final contentsSource = hasContents ? contentsFile : contextFile;
    final contentsText = await contentsSource.readAsString(encoding: utf8);
    final parseResult = SkillTreeParser().parse(contentsText);
    if (parseResult.nodes.isEmpty) {
      throw StateError('${p.basename(contentsSource.path)}: no nodes found.');
    }
    for (final node in parseResult.nodes.values) {
      if (node.isPlaceholder) {
        throw StateError(
          '${p.basename(contentsSource.path)}: missing parent id "${node.id}".',
        );
      }
    }
    _parseContentsLineById(contentsText, p.basename(contentsSource.path));

    final entriesByPath = <String, _BundleFolderEntry>{};
    void addEntry(File file) {
      final relPath = _normalizeArchivePath(
        p.relative(file.path, from: folderPath),
      );
      if (relPath.isEmpty) {
        return;
      }
      if (relPath.startsWith('__MACOSX/')) {
        return;
      }
      if (_hasAppleDoubleSegment(relPath)) {
        return;
      }
      entriesByPath.putIfAbsent(
        relPath,
        () => _BundleFolderEntry(file: file, archivePath: relPath),
      );
    }

    if (hasContents) {
      addEntry(contentsFile);
    }
    if (hasContext) {
      addEntry(contextFile);
    }

    for (final node in parseResult.nodes.values) {
      if (node.isPlaceholder) {
        continue;
      }
      final lectureFile = File(p.join(folderPath, '${node.id}_lecture.txt'));
      final legacyLectureFile =
          File(p.join(folderPath, node.id, 'lecture.txt'));
      if (lectureFile.existsSync()) {
        addEntry(lectureFile);
      } else if (legacyLectureFile.existsSync()) {
        addEntry(legacyLectureFile);
      } else {
        throw StateError('Missing file: ${lectureFile.path}');
      }
      _addQuestionEntriesForNode(
        folderPath: folderPath,
        nodeId: node.id,
        addEntry: addEntry,
      );
    }

    final promptsDir = Directory(p.join(folderPath, 'prompts'));
    if (promptsDir.existsSync()) {
      final promptFiles = promptsDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => p.extension(file.path).toLowerCase() == '.txt')
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
      for (final file in promptFiles) {
        addEntry(file);
      }
    }

    final entries = entriesByPath.values.toList()
      ..sort((left, right) => left.archivePath.compareTo(right.archivePath));
    if (entries.isEmpty) {
      throw StateError('Course bundle has no required files.');
    }
    return entries;
  }

  void _addQuestionEntriesForNode({
    required String folderPath,
    required String nodeId,
    required void Function(File file) addEntry,
  }) {
    for (final level in _questionLevels) {
      final flatQuestionFile = File(p.join(folderPath, '${nodeId}_$level.txt'));
      if (flatQuestionFile.existsSync()) {
        addEntry(flatQuestionFile);
      }
      final legacyQuestionFile = File(
        p.join(folderPath, nodeId, level, 'questions.txt'),
      );
      if (legacyQuestionFile.existsSync()) {
        addEntry(legacyQuestionFile);
      }
    }
  }

  List<int> _normalizePromptMetadataBytes(List<int> rawData) {
    final decoded = jsonDecode(utf8.decode(rawData));
    final cleaned =
        _normalizePromptMetadataValue(_removeGeneratedFields(decoded));
    final canonical = _canonicalJsonEncode(cleaned);
    return utf8.encode(canonical);
  }

  List<int> normalizePromptMetadataJson(Map<String, dynamic> value) {
    final cleaned =
        _normalizePromptMetadataBundleValue(_removeGeneratedFields(value));
    final canonical = _canonicalJsonEncode(cleaned);
    return utf8.encode(canonical);
  }

  List<int> _normalizePromptMetadataJsonForSemanticHash(
    Map<String, dynamic> value,
  ) {
    final cleaned =
        _normalizePromptMetadataValue(_removeGeneratedFields(value));
    final canonical = _canonicalJsonEncode(cleaned);
    return utf8.encode(canonical);
  }

  Map<String, dynamic> _emptyPromptMetadataDocument() {
    return <String, dynamic>{
      'schema': kCurrentPromptBundleSchema,
      'prompt_templates': const <Map<String, dynamic>>[],
      'student_prompt_profiles': const <Map<String, dynamic>>[],
      'student_pass_configs': const <Map<String, dynamic>>[],
    };
  }

  Object? _normalizePromptMetadataBundleValue(Object? value) {
    if (value is List) {
      return value.map(_normalizePromptMetadataBundleValue).toList();
    }
    if (value is! Map) {
      return _normalizePromptMetadataScalar(value);
    }
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      normalized[entry.key.toString()] =
          _normalizePromptMetadataBundleValue(entry.value);
    }
    final schema = normalized['schema'];
    if (schema is String && isSupportedPromptBundleSchema(schema)) {
      normalized['schema'] = kCurrentPromptBundleSchema;
    }
    return normalized;
  }

  Object? _normalizePromptMetadataValue(Object? value) {
    if (value is List) {
      return value.map(_normalizePromptMetadataValue).toList();
    }
    if (value is! Map) {
      return _normalizePromptMetadataScalar(value);
    }
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      normalized[entry.key.toString()] =
          _normalizePromptMetadataValue(entry.value);
    }
    final schema = normalized['schema'];
    if (schema is String && isSupportedPromptBundleSchema(schema)) {
      return _normalizePromptMetadataDocument(normalized);
    }
    return normalized;
  }

  Map<String, Object?> _normalizePromptMetadataDocument(
    Map<String, Object?> value,
  ) {
    return <String, Object?>{
      'schema': kCurrentPromptBundleSchema,
      'prompt_templates': _sortCanonicalMaps(
        _normalizePromptTemplateList(value['prompt_templates']),
      ),
      'student_prompt_profiles': _sortCanonicalMaps(
        _normalizePromptProfileList(value['student_prompt_profiles']),
      ),
      'student_pass_configs': _sortCanonicalMaps(
        _normalizePassConfigList(value['student_pass_configs']),
      ),
    };
  }

  List<Map<String, Object?>> _normalizePromptTemplateList(Object? raw) {
    if (raw is! List) {
      return const <Map<String, Object?>>[];
    }
    final items = <Map<String, Object?>>[];
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final normalized = <String, Object?>{};
      final promptName = _normalizeNonEmptyString(entry['prompt_name']);
      final scope = _normalizePromptMetadataScope(entry['scope']);
      final content = entry['content'];
      final studentRemoteUserId = _normalizePromptMetadataStudentRemoteUserId(
        entry['student_remote_user_id'],
        scope: scope,
      );
      if (promptName.isEmpty || scope.isEmpty || content is! String) {
        continue;
      }
      normalized['prompt_name'] = promptName;
      normalized['scope'] = scope;
      normalized['content'] = content;
      if (studentRemoteUserId != null) {
        normalized['student_remote_user_id'] = studentRemoteUserId;
      }
      items.add(normalized);
    }
    return items;
  }

  List<Map<String, Object?>> _normalizePromptProfileList(Object? raw) {
    if (raw is! List) {
      return const <Map<String, Object?>>[];
    }
    final items = <Map<String, Object?>>[];
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final scope = _normalizePromptMetadataScope(entry['scope']);
      if (scope.isEmpty) {
        continue;
      }
      final normalized = <String, Object?>{
        'scope': scope,
      };
      final studentRemoteUserId = _normalizePromptMetadataStudentRemoteUserId(
        entry['student_remote_user_id'],
        scope: scope,
      );
      if (studentRemoteUserId != null) {
        normalized['student_remote_user_id'] = studentRemoteUserId;
      }
      _copySemanticField(normalized, 'grade_level', entry['grade_level']);
      _copySemanticField(normalized, 'reading_level', entry['reading_level']);
      _copySemanticField(
        normalized,
        'preferred_language',
        entry['preferred_language'],
      );
      _copySemanticField(normalized, 'interests', entry['interests']);
      _copySemanticField(normalized, 'preferred_tone', entry['preferred_tone']);
      _copySemanticField(normalized, 'preferred_pace', entry['preferred_pace']);
      _copySemanticField(
        normalized,
        'preferred_format',
        entry['preferred_format'],
      );
      _copySemanticField(normalized, 'support_notes', entry['support_notes']);
      items.add(normalized);
    }
    return items;
  }

  List<Map<String, Object?>> _normalizePassConfigList(Object? raw) {
    if (raw is! List) {
      return const <Map<String, Object?>>[];
    }
    final items = <Map<String, Object?>>[];
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final studentRemoteUserId = _normalizePromptMetadataStudentRemoteUserId(
        entry['student_remote_user_id'],
        scope: 'student_course',
      );
      if (studentRemoteUserId == null) {
        continue;
      }
      final normalized = <String, Object?>{
        'student_remote_user_id': studentRemoteUserId,
      };
      _copySemanticField(normalized, 'easy_weight', entry['easy_weight']);
      _copySemanticField(normalized, 'medium_weight', entry['medium_weight']);
      _copySemanticField(normalized, 'hard_weight', entry['hard_weight']);
      _copySemanticField(
        normalized,
        'pass_threshold',
        entry['pass_threshold'],
      );
      items.add(normalized);
    }
    return items;
  }

  List<Map<String, Object?>> _sortCanonicalMaps(
      List<Map<String, Object?>> raw) {
    final items = List<Map<String, Object?>>.from(raw);
    items.sort(
      (left, right) =>
          _canonicalJsonEncode(left).compareTo(_canonicalJsonEncode(right)),
    );
    return items;
  }

  void _copySemanticField(
    Map<String, Object?> target,
    String key,
    Object? value,
  ) {
    final normalized = _normalizePromptMetadataScalar(value);
    if (normalized == null) {
      return;
    }
    target[key] = normalized;
  }

  Object? _normalizePromptMetadataScalar(Object? value) {
    if (value is num) {
      final asDouble = value.toDouble();
      if (asDouble.isFinite && asDouble == asDouble.roundToDouble()) {
        return asDouble.toInt();
      }
      return asDouble;
    }
    return value;
  }

  String _normalizeNonEmptyString(Object? value) {
    return value is String ? value.trim() : '';
  }

  String _normalizePromptMetadataScope(Object? value) {
    final normalized = _normalizeNonEmptyString(value);
    if (normalized == 'student') {
      return 'student_course';
    }
    return normalized;
  }

  int? _normalizePromptMetadataStudentRemoteUserId(
    Object? value, {
    required String scope,
  }) {
    if (scope != 'student_course' && scope != 'student_global') {
      return null;
    }
    final raw = _normalizePromptMetadataScalar(value);
    if (raw is int && raw > 0) {
      return raw;
    }
    if (raw is double && raw.isFinite && raw > 0) {
      return raw.toInt();
    }
    return null;
  }

  Object? _removeGeneratedFields(Object? value) {
    if (value is Map) {
      final next = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (key == 'generated_at') {
          continue;
        }
        next[key] = _removeGeneratedFields(entry.value);
      }
      return next;
    }
    if (value is List) {
      return value.map(_removeGeneratedFields).toList();
    }
    return value;
  }

  String _canonicalJsonEncode(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return jsonEncode(value);
    }
    if (value is List) {
      final parts = value.map(_canonicalJsonEncode).join(',');
      return '[$parts]';
    }
    if (value is Map) {
      final entries = value.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      final parts = entries
          .map(
            (entry) =>
                '${jsonEncode(entry.key)}:${_canonicalJsonEncode(entry.value)}',
          )
          .join(',');
      return '{$parts}';
    }
    throw StateError(
        'Unsupported prompt metadata value type: ${value.runtimeType}');
  }

  Future<_CourseKpSnapshot> _loadFolderSnapshot(String folderPath) async {
    final normalizedPath = p.normalize(folderPath);
    final folder = Directory(normalizedPath);
    if (!folder.existsSync()) {
      throw StateError('Course folder not found: $normalizedPath');
    }
    final contentsPath = p.join(normalizedPath, 'contents.txt');
    final contextPath = p.join(normalizedPath, 'context.txt');
    final contentsFile = File(contentsPath);
    final contextFile = File(contextPath);
    final contentsSource = contentsFile.existsSync()
        ? contentsFile
        : (contextFile.existsSync() ? contextFile : null);
    if (contentsSource == null) {
      throw StateError('Missing file: $contentsPath (or $contextPath)');
    }

    final contentsText = await contentsSource.readAsString(encoding: utf8);
    final parseResult = SkillTreeParser().parse(contentsText);
    if (parseResult.nodes.isEmpty) {
      throw StateError('${p.basename(contentsSource.path)}: no nodes found.');
    }
    for (final node in parseResult.nodes.values) {
      if (node.isPlaceholder) {
        throw StateError(
          '${p.basename(contentsSource.path)}: missing parent id "${node.id}".',
        );
      }
    }
    final lineById = _parseContentsLineById(
      contentsText,
      p.basename(contentsSource.path),
    );

    final fingerprints = <String, String>{};
    for (final node in parseResult.nodes.values) {
      if (node.isPlaceholder) {
        continue;
      }
      final lecturePath = p.join(normalizedPath, '${node.id}_lecture.txt');
      final legacyLecturePath = p.join(normalizedPath, node.id, 'lecture.txt');
      final lectureFile = File(lecturePath);
      final legacyLectureFile = File(legacyLecturePath);
      final lectureSource = lectureFile.existsSync()
          ? lectureFile
          : (legacyLectureFile.existsSync() ? legacyLectureFile : null);
      if (lectureSource == null) {
        throw StateError('Missing file: $lecturePath');
      }
      final lectureText = await lectureSource.readAsString(encoding: utf8);
      final questionTexts = await _readQuestionTextsFromFolder(
        folderPath: normalizedPath,
        nodeId: node.id,
      );
      final line = lineById[node.id] ??
          (node.rawLine.isNotEmpty ? node.rawLine : '${node.id} ${node.title}');
      fingerprints[node.id] = _kpFingerprint(
        line: line,
        lectureText: lectureText,
        questionTexts: questionTexts,
      );
    }
    return _CourseKpSnapshot(kpFingerprints: fingerprints);
  }

  Future<_CourseKpSnapshot> _loadBundleSnapshot(File bundleFile) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }

    final bytes = await _readBundleBytes(bundleFile);
    Archive? archive;
    try {
      archive = _decodeBundle(bytes);
      final entryByName = <String, ArchiveFile>{};
      for (final entry in archive.files) {
        if (!entry.isFile) {
          continue;
        }
        final name = _normalizeArchivePath(entry.name);
        if (name.isEmpty) {
          continue;
        }
        if (isSupportedPromptMetadataEntryPath(name)) {
          continue;
        }
        if (name.startsWith('__MACOSX/')) {
          continue;
        }
        if (_hasAppleDoubleSegment(name)) {
          continue;
        }
        entryByName[name] = entry;
      }
      if (entryByName.isEmpty) {
        throw StateError('Bundle is empty or contains only metadata files.');
      }
      final names = entryByName.keys.toSet();
      final roots = _candidateRoots(names);
      if (roots.isEmpty) {
        throw StateError('Bundle is missing contents.txt or context.txt.');
      }

      var selectedRoot = '';
      var selectedContentsName = '';
      for (final root in roots) {
        final contentsName =
            root.isEmpty ? 'contents.txt' : '$root/contents.txt';
        final contextName = root.isEmpty ? 'context.txt' : '$root/context.txt';
        if (entryByName.containsKey(contentsName)) {
          selectedRoot = root;
          selectedContentsName = contentsName;
          break;
        }
        if (entryByName.containsKey(contextName)) {
          selectedRoot = root;
          selectedContentsName = contextName;
          break;
        }
      }
      if (selectedContentsName.isEmpty) {
        throw StateError('Bundle is missing contents.txt or context.txt.');
      }

      final contentsEntry = entryByName[selectedContentsName];
      if (contentsEntry == null) {
        throw StateError('Bundle is missing contents.txt or context.txt.');
      }
      final contentsText = utf8.decode(_entryBytes(contentsEntry));
      final parseResult = SkillTreeParser().parse(contentsText);
      if (parseResult.nodes.isEmpty) {
        throw StateError('Bundle contents has no skill nodes.');
      }
      for (final node in parseResult.nodes.values) {
        if (node.isPlaceholder) {
          throw StateError(
              'Bundle contents has missing parent id "${node.id}".');
        }
      }
      final lineById =
          _parseContentsLineById(contentsText, selectedContentsName);

      final fingerprints = <String, String>{};
      for (final node in parseResult.nodes.values) {
        if (node.isPlaceholder) {
          continue;
        }
        final lectureName = selectedRoot.isEmpty
            ? '${node.id}_lecture.txt'
            : '$selectedRoot/${node.id}_lecture.txt';
        final legacyLectureName = selectedRoot.isEmpty
            ? '${node.id}/lecture.txt'
            : '$selectedRoot/${node.id}/lecture.txt';
        final lectureEntry =
            entryByName[lectureName] ?? entryByName[legacyLectureName];
        if (lectureEntry == null) {
          throw StateError(
            'Bundle is missing lecture file for id "${node.id}".',
          );
        }
        final lectureText = utf8.decode(_entryBytes(lectureEntry));
        final questionTexts = _readQuestionTextsFromBundle(
          entryByName: entryByName,
          selectedRoot: selectedRoot,
          nodeId: node.id,
        );
        final line = lineById[node.id] ??
            (node.rawLine.isNotEmpty
                ? node.rawLine
                : '${node.id} ${node.title}');
        fingerprints[node.id] = _kpFingerprint(
          line: line,
          lectureText: lectureText,
          questionTexts: questionTexts,
        );
      }

      return _CourseKpSnapshot(kpFingerprints: fingerprints);
    } finally {
      archive?.clearSync();
    }
  }

  Map<String, String> _parseContentsLineById(
      String contentsText, String label) {
    final lines = contentsText.split(RegExp(r'\r\n|\n|\r'));
    if (lines.isNotEmpty && lines.first.startsWith('\uFEFF')) {
      lines[0] = lines.first.substring(1);
    }
    final lineById = <String, String>{};
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final match = _idPattern.firstMatch(trimmed);
      if (match == null) {
        throw StateError('$label: invalid line "$trimmed".');
      }
      final id = match.group(1)!;
      if (lineById.containsKey(id)) {
        throw StateError('$label: duplicate id "$id".');
      }
      lineById[id] = trimmed;
    }
    return lineById;
  }

  String _kpFingerprint({
    required String line,
    required String lectureText,
    required List<String> questionTexts,
  }) {
    final normalizedLine = _normalizeTextForHash(line);
    final normalizedLecture = _normalizeTextForHash(lectureText);
    final normalizedQuestions =
        questionTexts.map(_normalizeTextForHash).join('\u0000');
    final payload =
        '$normalizedLine\u0000$normalizedLecture\u0000$normalizedQuestions';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  String _normalizeTextForHash(String input) {
    return input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  Future<List<String>> _readQuestionTextsFromFolder({
    required String folderPath,
    required String nodeId,
  }) async {
    final texts = <String>[];
    for (final relativePath in _questionRelativePaths(nodeId)) {
      final file = File(p.joinAll(<String>[
        folderPath,
        ...relativePath.split('/'),
      ]));
      if (!file.existsSync()) {
        continue;
      }
      final normalizedRelativePath = _normalizeArchivePath(relativePath);
      final text = await file.readAsString(encoding: utf8);
      texts.add('$normalizedRelativePath\u0000$text');
    }
    return texts;
  }

  List<String> _readQuestionTextsFromBundle({
    required Map<String, ArchiveFile> entryByName,
    required String selectedRoot,
    required String nodeId,
  }) {
    final texts = <String>[];
    for (final relativePath in _questionRelativePaths(nodeId)) {
      final normalizedRelativePath = _normalizeArchivePath(relativePath);
      final entryName = selectedRoot.isEmpty
          ? normalizedRelativePath
          : _normalizeArchivePath('$selectedRoot/$normalizedRelativePath');
      final entry = entryByName[entryName];
      if (entry == null) {
        continue;
      }
      final text = utf8.decode(_entryBytes(entry));
      texts.add('$normalizedRelativePath\u0000$text');
    }
    return texts;
  }

  List<String> _questionRelativePaths(String nodeId) {
    return <String>[
      for (final level in _questionLevels) ...<String>[
        '${nodeId}_$level.txt',
        '$nodeId/$level/questions.txt',
      ],
    ];
  }
}

class _BoundedOutputStream extends OutputStreamBase {
  _BoundedOutputStream(int maxBytes)
      : assert(maxBytes >= 0),
        _maxBytes = maxBytes,
        _buffer = Uint8List(
          maxBytes < _initialCapacity ? maxBytes : _initialCapacity,
        );

  static const int _initialCapacity = 32 * 1024;

  final int _maxBytes;
  Uint8List _buffer;

  @override
  int length = 0;

  Uint8List get bytes => Uint8List.view(
        _buffer.buffer,
        _buffer.offsetInBytes,
        length,
      );

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _ensureWritable(1);
    _buffer[length++] = value & 0xff;
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    final byteCount = len ?? bytes.length;
    if (byteCount < 0 || byteCount > bytes.length) {
      throw RangeError.range(byteCount, 0, bytes.length, 'len');
    }
    _ensureWritable(byteCount);
    _buffer.setRange(length, length + byteCount, bytes);
    length += byteCount;
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    final byteCount = stream.length;
    _ensureWritable(byteCount);
    writeBytes(stream.toUint8List(), byteCount);
  }

  @override
  void writeUint16(int value) {
    writeByte(value);
    writeByte(value >> 8);
  }

  @override
  void writeUint32(int value) {
    writeUint16(value);
    writeUint16(value >> 16);
  }

  @override
  void writeUint64(int value) {
    writeUint32(value);
    writeUint32(value >> 32);
  }

  List<int> subset(int start, [int? end]) {
    var normalizedStart = start < 0 ? length + start : start;
    var normalizedEnd = end ?? length;
    if (normalizedEnd < 0) {
      normalizedEnd = length + normalizedEnd;
    }
    if (normalizedStart < 0 ||
        normalizedEnd < normalizedStart ||
        normalizedEnd > length) {
      throw RangeError.range(
        normalizedStart,
        0,
        length,
        'start',
      );
    }
    return Uint8List.view(
      _buffer.buffer,
      _buffer.offsetInBytes + normalizedStart,
      normalizedEnd - normalizedStart,
    );
  }

  void _ensureWritable(int byteCount) {
    if (byteCount < 0 || byteCount > _maxBytes - length) {
      throw FormatException(
        'Course bundle entry exceeds its declared '
        '$_maxBytes-byte size.',
      );
    }
    final requiredLength = length + byteCount;
    if (requiredLength <= _buffer.length) {
      return;
    }
    var capacity = _buffer.length == 0 ? 1 : _buffer.length;
    while (capacity < requiredLength) {
      final doubled = capacity * 2;
      capacity = doubled > _maxBytes ? _maxBytes : doubled;
    }
    final expanded = Uint8List(capacity);
    expanded.setRange(0, length, _buffer);
    _buffer = expanded;
  }
}

class _BundleSemanticFile {
  _BundleSemanticFile({
    required this.name,
    required this.data,
  });

  final String name;
  final List<int> data;
}

class _BundleFolderEntry {
  _BundleFolderEntry({
    required this.file,
    required this.archivePath,
  });

  final File file;
  final String archivePath;
}

class _IndexedBundleArchive {
  _IndexedBundleArchive({
    required this.entryByName,
    required this.selectedRoot,
    required this.selectedContentsName,
    required this.selectedContextName,
  });

  final Map<String, List<int>> entryByName;
  final String selectedRoot;
  final String selectedContentsName;
  final String selectedContextName;
}

class _CourseKpSnapshot {
  _CourseKpSnapshot({
    required this.kpFingerprints,
  });

  final Map<String, String> kpFingerprints;
}

class _DigestCollector implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}
