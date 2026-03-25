import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/skill_tree.dart';
import 'course_bundle_service.dart';

class CourseChapterArtifact {
  CourseChapterArtifact({
    required this.chapterKey,
    required this.zipPath,
    required this.sizeBytes,
  });

  final String chapterKey;
  final String zipPath;
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
        'chapter_key': chapterKey,
        'zip_path': zipPath,
        'size_bytes': sizeBytes,
      };

  factory CourseChapterArtifact.fromJson(Map<String, dynamic> json) {
    return CourseChapterArtifact(
      chapterKey: (json['chapter_key'] as String?) ?? '',
      zipPath: (json['zip_path'] as String?) ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class CourseArtifactManifest {
  CourseArtifactManifest({
    required this.courseVersionId,
    required this.folderPath,
    required this.contentBundlePath,
    required this.chapters,
    required this.builtAt,
  });

  final int courseVersionId;
  final String folderPath;
  final String contentBundlePath;
  final List<CourseChapterArtifact> chapters;
  final DateTime builtAt;

  Map<String, dynamic> toJson() => {
        'course_version_id': courseVersionId,
        'folder_path': folderPath,
        'content_bundle_path': contentBundlePath,
        'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
        'built_at': builtAt.toUtc().toIso8601String(),
      };

  factory CourseArtifactManifest.fromJson(Map<String, dynamic> json) {
    final rawChapters = json['chapters'];
    final chapters = rawChapters is List
        ? rawChapters
            .whereType<Map<String, dynamic>>()
            .map(CourseChapterArtifact.fromJson)
            .toList()
        : <CourseChapterArtifact>[];
    final builtAt = DateTime.tryParse((json['built_at'] as String?) ?? '');
    return CourseArtifactManifest(
      courseVersionId: (json['course_version_id'] as num?)?.toInt() ?? 0,
      folderPath: (json['folder_path'] as String?) ?? '',
      contentBundlePath: (json['content_bundle_path'] as String?) ?? '',
      chapters: chapters,
      builtAt: builtAt?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}

class PreparedCourseUploadBundle {
  PreparedCourseUploadBundle({
    required this.bundleFile,
    required this.hash,
  });

  final File bundleFile;
  final String hash;
}

class CourseArtifactService {
  CourseArtifactService({
    Future<Directory> Function()? artifactsRootProvider,
    CourseBundleService? bundleService,
  })  : _artifactsRootProvider = artifactsRootProvider,
        _bundleService = bundleService ?? CourseBundleService();

  final Future<Directory> Function()? _artifactsRootProvider;
  final CourseBundleService _bundleService;

  Future<CourseArtifactManifest> rebuildCourseArtifacts({
    required int courseVersionId,
    required String folderPath,
  }) async {
    if (courseVersionId <= 0) {
      throw StateError('Course version id must be positive.');
    }
    final normalizedFolderPath = p.normalize(folderPath);
    final sourceFolder = Directory(normalizedFolderPath);
    if (!sourceFolder.existsSync()) {
      throw StateError('Course folder not found: $normalizedFolderPath');
    }

    final courseDir = await _resolveCourseArtifactDirectory(courseVersionId);
    if (courseDir.existsSync()) {
      await courseDir.delete(recursive: true);
    }
    await courseDir.create(recursive: true);

    final tempContentBundle =
        await _bundleService.createBundleFromFolder(normalizedFolderPath);
    final contentBundlePath = p.join(courseDir.path, 'content_bundle.zip');
    final contentBundle = File(contentBundlePath);
    await tempContentBundle.copy(contentBundle.path);
    if (tempContentBundle.existsSync()) {
      await tempContentBundle.delete();
    }

    final chaptersDir = Directory(p.join(courseDir.path, 'chapters'));
    await chaptersDir.create(recursive: true);
    final chapterArtifacts = await _buildChapterArchives(
      folderPath: normalizedFolderPath,
      outputDirectory: chaptersDir,
    );

    final manifest = CourseArtifactManifest(
      courseVersionId: courseVersionId,
      folderPath: normalizedFolderPath,
      contentBundlePath: contentBundle.path,
      chapters: chapterArtifacts,
      builtAt: DateTime.now().toUtc(),
    );
    await _writeManifest(courseDir, manifest);
    return manifest;
  }

  Future<CourseArtifactManifest?> readCourseArtifacts(
      int courseVersionId) async {
    if (courseVersionId <= 0) {
      throw StateError('Course version id must be positive.');
    }
    final courseDir = await _resolveCourseArtifactDirectory(courseVersionId);
    final manifestFile = File(p.join(courseDir.path, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      return null;
    }
    final decoded = jsonDecode(await manifestFile.readAsString(encoding: utf8));
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Course artifact manifest is invalid.');
    }
    return CourseArtifactManifest.fromJson(decoded);
  }

  Future<PreparedCourseUploadBundle> prepareUploadBundle({
    required int courseVersionId,
    required Map<String, dynamic>? promptMetadata,
    required String bundleLabel,
  }) async {
    final manifest = await readCourseArtifacts(courseVersionId);
    if (manifest == null) {
      throw StateError(
        'Cached course artifacts are missing for course version '
        '$courseVersionId.',
      );
    }
    final contentBundle = File(manifest.contentBundlePath);
    if (!contentBundle.existsSync()) {
      throw StateError(
        'Cached course content bundle is missing: ${contentBundle.path}',
      );
    }
    final bundleFile = await _bundleService.cloneBundleWithPromptMetadata(
      sourceBundle: contentBundle,
      promptMetadata: promptMetadata,
      label: bundleLabel,
    );
    final hash = await _bundleService.computeBundleSemanticHashFromBundle(
      contentBundle,
      promptMetadataOverride: promptMetadata,
    );
    return PreparedCourseUploadBundle(
      bundleFile: bundleFile,
      hash: hash,
    );
  }

  Future<String> computeUploadHash({
    required int courseVersionId,
    required Map<String, dynamic>? promptMetadata,
  }) async {
    final manifest = await readCourseArtifacts(courseVersionId);
    if (manifest == null) {
      throw StateError(
        'Cached course artifacts are missing for course version '
        '$courseVersionId.',
      );
    }
    final contentBundle = File(manifest.contentBundlePath);
    if (!contentBundle.existsSync()) {
      throw StateError(
        'Cached course content bundle is missing: ${contentBundle.path}',
      );
    }
    return _bundleService.computeBundleSemanticHashFromBundle(
      contentBundle,
      promptMetadataOverride: promptMetadata,
    );
  }

  Future<void> _writeManifest(
    Directory courseDir,
    CourseArtifactManifest manifest,
  ) async {
    final manifestFile = File(p.join(courseDir.path, 'manifest.json'));
    await manifestFile.writeAsString(
      jsonEncode(manifest.toJson()),
      encoding: utf8,
    );
  }

  Future<List<CourseChapterArtifact>> _buildChapterArchives({
    required String folderPath,
    required Directory outputDirectory,
  }) async {
    final normalizedFolder = p.normalize(folderPath);
    final contentsSource = await _resolveContentsSource(normalizedFolder);
    final contentsText = await contentsSource.readAsString(encoding: utf8);
    final parseResult = SkillTreeParser().parse(contentsText);
    if (parseResult.nodes.isEmpty) {
      throw StateError('${p.basename(contentsSource.path)}: no nodes found.');
    }

    final groups = <String, Map<String, File>>{};
    final commonEntries = await _collectCommonEntries(normalizedFolder);
    for (final node in parseResult.nodes.values) {
      if (node.isPlaceholder) {
        continue;
      }
      final chapterKey = _topLevelChapterKey(node.id);
      final group = groups.putIfAbsent(chapterKey, () {
        return <String, File>{
          for (final entry in commonEntries) entry.archivePath: entry.file,
        };
      });
      final lectureSource = _resolveLectureFile(
        folderPath: normalizedFolder,
        nodeId: node.id,
      );
      final archivePath = _normalizeArchivePath(
        p.relative(lectureSource.path, from: normalizedFolder),
      );
      group[archivePath] = lectureSource;
    }

    final chapters = <CourseChapterArtifact>[];
    final sortedKeys = groups.keys.toList()..sort(_compareChapterKeys);
    for (final chapterKey in sortedKeys) {
      final zipName = 'chapter_${_sanitizeName(chapterKey)}.zip';
      final zipPath = p.join(outputDirectory.path, zipName);
      final encoder = ZipFileEncoder();
      encoder.create(zipPath);
      final entries = groups[chapterKey]!.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      for (final entry in entries) {
        encoder.addFile(entry.value, entry.key);
      }
      encoder.close();
      final zipFile = File(zipPath);
      chapters.add(
        CourseChapterArtifact(
          chapterKey: chapterKey,
          zipPath: zipFile.path,
          sizeBytes: await zipFile.length(),
        ),
      );
    }
    return chapters;
  }

  Future<File> _resolveContentsSource(String folderPath) async {
    final contentsFile = File(p.join(folderPath, 'contents.txt'));
    if (contentsFile.existsSync()) {
      return contentsFile;
    }
    final contextFile = File(p.join(folderPath, 'context.txt'));
    if (contextFile.existsSync()) {
      return contextFile;
    }
    throw StateError(
      'Missing file: ${p.join(folderPath, 'contents.txt')} '
      '(or ${p.join(folderPath, 'context.txt')})',
    );
  }

  Future<List<_CourseArtifactEntry>> _collectCommonEntries(
    String folderPath,
  ) async {
    final entries = <_CourseArtifactEntry>[];
    final contents = File(p.join(folderPath, 'contents.txt'));
    if (contents.existsSync()) {
      entries.add(
          _CourseArtifactEntry(file: contents, archivePath: 'contents.txt'));
    }
    final context = File(p.join(folderPath, 'context.txt'));
    if (context.existsSync()) {
      entries
          .add(_CourseArtifactEntry(file: context, archivePath: 'context.txt'));
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
        final archivePath = _normalizeArchivePath(
          p.relative(file.path, from: folderPath),
        );
        entries.add(_CourseArtifactEntry(file: file, archivePath: archivePath));
      }
    }
    return entries;
  }

  File _resolveLectureFile({
    required String folderPath,
    required String nodeId,
  }) {
    final lectureFile = File(p.join(folderPath, '${nodeId}_lecture.txt'));
    if (lectureFile.existsSync()) {
      return lectureFile;
    }
    final legacyLecture = File(p.join(folderPath, nodeId, 'lecture.txt'));
    if (legacyLecture.existsSync()) {
      return legacyLecture;
    }
    throw StateError('Missing lecture file for node "$nodeId".');
  }

  String _topLevelChapterKey(String nodeId) {
    final trimmed = nodeId.trim();
    if (trimmed.isEmpty) {
      throw StateError('Course node id must not be empty.');
    }
    return trimmed.split('.').first.trim();
  }

  int _compareChapterKeys(String left, String right) {
    final leftNumber = int.tryParse(left);
    final rightNumber = int.tryParse(right);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    return left.compareTo(right);
  }

  String _sanitizeName(String value) {
    return value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  }

  String _normalizeArchivePath(String input) {
    return p
        .normalize(input)
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
  }

  Future<Directory> _resolveCourseArtifactDirectory(int courseVersionId) async {
    final root = await _resolveArtifactsRoot();
    final directory = Directory(p.join(root.path, 'course_$courseVersionId'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  Future<Directory> _resolveArtifactsRoot() async {
    if (_artifactsRootProvider != null) {
      final root = await _artifactsRootProvider();
      if (!root.existsSync()) {
        root.createSync(recursive: true);
      }
      return root;
    }
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'sync_artifacts', 'courses'));
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return root;
  }
}

class _CourseArtifactEntry {
  _CourseArtifactEntry({
    required this.file,
    required this.archivePath,
  });

  final File file;
  final String archivePath;
}
