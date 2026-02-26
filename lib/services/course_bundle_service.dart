import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/skill_tree.dart';

class CourseBundleService {
  static const String promptMetadataEntryPath =
      '_family_teacher/prompt_bundle.json';

  Future<File> createBundleFromFolder(
    String folderPath, {
    Map<String, dynamic>? promptMetadata,
  }) async {
    final normalized = p.normalize(folderPath);
    final folder = Directory(normalized);
    if (!folder.existsSync()) {
      throw StateError('Course folder not found: $normalized');
    }
    final tempDir = await getTemporaryDirectory();
    final safeName = _sanitizeName(p.basename(normalized));
    final zipPath = p.join(
      tempDir.path,
      'bundle_${safeName}_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    encoder.addDirectory(folder, includeDirName: false);
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
    final archive = ZipDecoder().decodeBuffer(input);
    input.close();
    _validateArchivePaths(archive);
    extractArchiveToDisk(archive, targetPath);
    return _resolveExtractedCourseRoot(targetPath);
  }

  Future<Map<String, dynamic>?> readPromptMetadataFromBundleFile(
    File bundleFile,
  ) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }
    final input = InputFileStream(bundleFile.path);
    final archive = ZipDecoder().decodeBuffer(input);
    input.close();
    for (final file in archive) {
      if (!file.isFile) {
        continue;
      }
      final normalizedName = p.normalize(file.name).replaceAll('\\', '/');
      if (normalizedName != promptMetadataEntryPath) {
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
    extractArchiveToDisk(archive, targetPath);
    return _resolveExtractedCourseRoot(targetPath);
  }

  Future<void> validateBundleForImport(File bundleFile) async {
    if (!bundleFile.existsSync()) {
      throw StateError('Bundle file not found: ${bundleFile.path}');
    }

    final input = InputFileStream(bundleFile.path);
    final archive = ZipDecoder().decodeBuffer(input);
    input.close();
    _validateArchivePaths(archive);

    final fileEntries = archive.files.where((entry) {
      if (!entry.isFile) {
        return false;
      }
      final normalized = _normalizeArchivePath(entry.name);
      if (normalized.isEmpty) {
        return false;
      }
      if (normalized == promptMetadataEntryPath) {
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
      final contentsName = root.isEmpty ? 'contents.txt' : '$root/contents.txt';
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
      if (!names.contains(lectureName) && !names.contains(legacyLectureName)) {
        missingLectures.add(node.id);
      }
    }

    if (missingLectures.isNotEmpty) {
      throw StateError(
        'Bundle is missing lecture files for ids: ${missingLectures.join(', ')}',
      );
    }
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
}
