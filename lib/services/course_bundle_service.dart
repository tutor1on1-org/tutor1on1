import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

class CourseBundleService {
  static const String promptMetadataEntryPath = kCurrentPromptMetadataEntryPath;
  static final RegExp _idPattern = RegExp(r'^(\d+(?:\.\d+)*)\s*(.+)$');

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
    final safeName = _sanitizeName(p.basename(normalized));
    final zipPath = p.join(
      tempDir.path,
      'bundle_${safeName}_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    for (final entry in requiredEntries) {
      encoder.addFile(entry.file, entry.archivePath);
    }
    File? metadataFile;
    if (promptMetadata != null) {
      metadataFile = File(
        p.join(
          tempDir.path,
          'prompt_bundle_${DateTime.now().millisecondsSinceEpoch}.json',
        ),
      );
      await metadataFile.writeAsString(
        jsonEncode(promptMetadata),
        encoding: utf8,
      );
      encoder.addFile(metadataFile, promptMetadataEntryPath);
    }
    encoder.close();
    if (metadataFile != null && metadataFile.existsSync()) {
      await metadataFile.delete();
    }
    final bundleFile = File(zipPath);
    await validateBundleForImport(bundleFile);
    return bundleFile;
  }

  Future<String> createTempBundlePath({String? label}) async {
    final tempDir = await getTemporaryDirectory();
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
    final input = InputFileStream(bundleFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      _validateArchivePaths(archive);
      // archive.extractArchiveToDisk is async in archive 3.x. Must await to
      // avoid returning before contents/context files are written.
      await extractArchiveToDisk(archive, targetPath);
    } finally {
      input.close();
    }
    return _resolveExtractedCourseRoot(targetPath);
  }

  Future<Map<String, dynamic>?> readPromptMetadataFromBundleFile(
    File bundleFile,
  ) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }
    final input = InputFileStream(bundleFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
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
      input.close();
    }
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
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    _validateArchivePaths(archive);
    // archive.extractArchiveToDisk is async in archive 3.x. Must await to
    // avoid returning before contents/context files are written.
    await extractArchiveToDisk(archive, targetPath);
    return _resolveExtractedCourseRoot(targetPath);
  }

  Future<void> validateBundleForImport(File bundleFile) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }

    final input = InputFileStream(bundleFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      _validateArchivePaths(archive);

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
      input.close();
    }
  }

  Future<String> computeBundleSemanticHash(File bundleFile) async {
    return computeBundleSemanticHashFromBundle(bundleFile);
  }

  Future<String> computeBundleSemanticHashFromBundle(
    File bundleFile, {
    Map<String, dynamic>? promptMetadataOverride,
  }) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }
    final input = InputFileStream(bundleFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      final files = <_BundleSemanticFile>[];
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
            data: normalizePromptMetadataJson(promptMetadataOverride),
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
      input.close();
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
    final input = InputFileStream(sourceBundle.path);
    try {
      final sourceArchive = ZipDecoder().decodeBuffer(input);
      final archive = Archive();
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
      await targetFile.writeAsBytes(bytes, flush: true);
      await validateBundleForImport(targetFile);
      return targetFile;
    } finally {
      input.close();
    }
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
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'downloaded_courses'));
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return root;
  }

  void _validateArchivePaths(Archive archive) {
    for (final file in archive) {
      final normalized = p.normalize(file.name);
      if (p.isAbsolute(normalized)) {
        throw FormatException('Bundle contains invalid path: ${file.name}');
      }
      final parts = p.split(normalized);
      if (parts.contains('..')) {
        throw FormatException('Bundle contains invalid path: ${file.name}');
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
        continue;
      }
      if (legacyLectureFile.existsSync()) {
        addEntry(legacyLectureFile);
        continue;
      }
      throw StateError('Missing file: ${lectureFile.path}');
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

  List<int> _normalizePromptMetadataBytes(List<int> rawData) {
    final decoded = jsonDecode(utf8.decode(rawData));
    final cleaned = _normalizePromptMetadataValue(_removeGeneratedFields(decoded));
    final canonical = _canonicalJsonEncode(cleaned);
    return utf8.encode(canonical);
  }

  List<int> normalizePromptMetadataJson(Map<String, dynamic> value) {
    final cleaned = _normalizePromptMetadataValue(_removeGeneratedFields(value));
    final canonical = _canonicalJsonEncode(cleaned);
    return utf8.encode(canonical);
  }

  Object? _normalizePromptMetadataValue(Object? value) {
    if (value is! Map) {
      return value;
    }
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      normalized[entry.key.toString()] = entry.value;
    }
    final schema = normalized['schema'];
    if (schema is String && isSupportedPromptBundleSchema(schema)) {
      normalized['schema'] = kCurrentPromptBundleSchema;
    }
    return normalized;
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
      final line = lineById[node.id] ??
          (node.rawLine.isNotEmpty ? node.rawLine : '${node.id} ${node.title}');
      fingerprints[node.id] = _kpFingerprint(
        line: line,
        lectureText: lectureText,
      );
    }
    return _CourseKpSnapshot(kpFingerprints: fingerprints);
  }

  Future<_CourseKpSnapshot> _loadBundleSnapshot(File bundleFile) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }

    final input = InputFileStream(bundleFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      _validateArchivePaths(archive);
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
        final line = lineById[node.id] ??
            (node.rawLine.isNotEmpty
                ? node.rawLine
                : '${node.id} ${node.title}');
        fingerprints[node.id] = _kpFingerprint(
          line: line,
          lectureText: lectureText,
        );
      }

      return _CourseKpSnapshot(kpFingerprints: fingerprints);
    } finally {
      input.close();
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
  }) {
    final normalizedLine = _normalizeTextForHash(line);
    final normalizedLecture = _normalizeTextForHash(lectureText);
    final payload = '$normalizedLine\u0000$normalizedLecture';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  String _normalizeTextForHash(String input) {
    return input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
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
