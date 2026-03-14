import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../constants.dart';
import '../db/app_database.dart';
import '../models/skill_tree.dart';
import 'course_artifact_service.dart';

class CourseLoadResult {
  CourseLoadResult({
    required this.success,
    required this.message,
    this.course,
  });

  final bool success;
  final String message;
  final CourseVersion? course;
}

enum CourseReloadMode { fresh, override, wipe }

class CourseReloadEntry {
  CourseReloadEntry({
    required this.id,
    required this.signature,
    required this.rawLine,
    this.sessionCount = 0,
  });

  final String id;
  final String signature;
  final String rawLine;
  final int sessionCount;
}

class CourseLoadPreview {
  CourseLoadPreview({
    required this.success,
    required this.message,
    this.normalizedPath,
    this.courseName,
    this.contents,
    this.parseResult,
    this.maxDepth,
    this.courseVersionId,
    this.hasExisting = false,
    this.deletedEntries = const [],
    this.addedEntries = const [],
    this.oldIdToNewId = const {},
  });

  final bool success;
  final String message;
  final String? normalizedPath;
  final String? courseName;
  final String? contents;
  final SkillTreeParseResult? parseResult;
  final int? maxDepth;
  final int? courseVersionId;
  final bool hasExisting;
  final List<CourseReloadEntry> deletedEntries;
  final List<CourseReloadEntry> addedEntries;
  final Map<String, String> oldIdToNewId;
}

class CourseService {
  CourseService(this._db, {CourseArtifactService? courseArtifactService})
      : _courseArtifactService = courseArtifactService;

  final AppDatabase _db;
  final CourseArtifactService? _courseArtifactService;
  static final RegExp _idPattern = RegExp(r'^(\d+(?:\.\d+)*)\s*(.+)$');

  Future<CourseLoadResult> loadCourseFromFolder({
    required int teacherId,
    required String folderPath,
    int? courseVersionId,
    String? courseNameOverride,
  }) async {
    final preview = await previewCourseLoad(
      folderPath: folderPath,
      courseVersionId: courseVersionId,
      courseNameOverride: courseNameOverride,
    );
    if (!preview.success) {
      return CourseLoadResult(
        success: false,
        message: preview.message,
      );
    }
    final mode = courseVersionId == null
        ? CourseReloadMode.fresh
        : CourseReloadMode.override;
    return applyCourseLoad(
      teacherId: teacherId,
      preview: preview,
      mode: mode,
    );
  }

  Future<CourseLoadPreview> previewCourseLoad({
    required String folderPath,
    int? courseVersionId,
    String? courseNameOverride,
  }) async {
    final normalizedPath = p.normalize(folderPath);
    final folder = Directory(normalizedPath);
    if (!folder.existsSync()) {
      return CourseLoadPreview(
        success: false,
        message: 'Folder not found: $normalizedPath',
      );
    }
    final contentsPath = p.join(normalizedPath, 'contents.txt');
    final contextPath = p.join(normalizedPath, 'context.txt');
    final contentsFile = File(contentsPath);
    final contextFile = File(contextPath);
    final contentsSource = contentsFile.existsSync()
        ? contentsFile
        : (contextFile.existsSync() ? contextFile : null);
    if (contentsSource == null) {
      return CourseLoadPreview(
        success: false,
        message: 'Missing file: $contentsPath (or $contextPath)',
      );
    }

    final contents = await contentsSource.readAsString(encoding: utf8);
    final parser = SkillTreeParser();
    final parseResult = parser.parse(contents);
    final errors = _validateContents(
      contents: contents,
      parseResult: parseResult,
      basePath: normalizedPath,
      contentsLabel: p.basename(contentsSource.path),
    );
    if (errors.isNotEmpty) {
      return CourseLoadPreview(
        success: false,
        message: errors.join('\n'),
      );
    }

    CourseVersion? existingCourse;
    if (courseVersionId != null) {
      existingCourse = await _db.getCourseVersionById(courseVersionId);
      if (existingCourse == null) {
        return CourseLoadPreview(
          success: false,
          message: 'Course version not found: $courseVersionId',
        );
      }
    }

    final maxDepth = _maxDepth(parseResult.nodes.values);
    final requestedCourseName = (courseNameOverride ?? '').trim();
    final courseName = existingCourse != null
        ? existingCourse.subject
        : (requestedCourseName.isEmpty
            ? p.basename(normalizedPath)
            : requestedCourseName);
    final oldIdToNewId = <String, String>{};
    var deletedEntries = <CourseReloadEntry>[];
    final addedEntries = <CourseReloadEntry>[];
    var hasExisting = false;

    final newEntries = _parseLineEntries(contents, parseResult);
    final newById = {for (final entry in newEntries) entry.id: entry};

    if (courseVersionId != null) {
      final oldNodes = await _db.getCourseNodes(courseVersionId);
      final progressCountRow = await (_db.selectOnly(_db.progressEntries)
            ..addColumns([_db.progressEntries.id.count()])
            ..where(
              _db.progressEntries.courseVersionId.equals(courseVersionId),
            ))
          .getSingle();
      final progressCount =
          progressCountRow.read(_db.progressEntries.id.count()) ?? 0;
      hasExisting = oldNodes.isNotEmpty || progressCount > 0;
      final oldEntries = oldNodes
          .map(
            (node) => _LineEntry(
              id: node.kpKey,
              signature: _signatureFromLine(node.description),
              rawLine: node.description,
              orderIndex: node.orderIndex,
            ),
          )
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      final oldById = {for (final entry in oldEntries) entry.id: entry};
      final sharedIds = oldById.keys.toSet().intersection(newById.keys.toSet());

      final renamed = <String>[];
      for (final id in sharedIds) {
        final oldEntry = oldById[id]!;
        final newEntry = newById[id]!;
        oldIdToNewId[id] = id;
        if (oldEntry.signature != newEntry.signature) {
          renamed.add(
            '$id: "${oldEntry.signature}" -> "${newEntry.signature}"',
          );
        }
      }
      if (renamed.isNotEmpty) {
        return CourseLoadPreview(
          success: false,
          message:
              'Node names are immutable for existing IDs. Delete and create new nodes to rename.\n'
              '${renamed.join('\n')}',
        );
      }

      final deletedIds =
          oldById.keys.where((id) => !newById.containsKey(id)).toList()..sort();
      for (final id in deletedIds) {
        final entry = oldById[id]!;
        deletedEntries.add(
          CourseReloadEntry(
            id: entry.id,
            signature: entry.signature,
            rawLine: entry.rawLine,
          ),
        );
      }

      final addedIds =
          newById.keys.where((id) => !oldById.containsKey(id)).toList()..sort();
      for (final id in addedIds) {
        final entry = newById[id]!;
        addedEntries.add(
          CourseReloadEntry(
            id: entry.id,
            signature: entry.signature,
            rawLine: entry.rawLine,
          ),
        );
      }

      if (deletedEntries.isNotEmpty) {
        final rows = await _db.customSelect(
          '''
SELECT kp_key, COUNT(*) AS session_count
FROM chat_sessions
WHERE course_version_id = ?
GROUP BY kp_key
''',
          variables: [Variable.withInt(courseVersionId)],
          readsFrom: {_db.chatSessions},
        ).get();
        final counts = <String, int>{};
        for (final row in rows) {
          final key = (row.data['kp_key'] as String?) ?? '';
          final count = (row.data['session_count'] as int?) ?? 0;
          if (key.isEmpty || count <= 0) {
            continue;
          }
          counts[key] = count;
        }
        deletedEntries = deletedEntries
            .map(
              (entry) => CourseReloadEntry(
                id: entry.id,
                signature: entry.signature,
                rawLine: entry.rawLine,
                sessionCount: counts[entry.id] ?? 0,
              ),
            )
            .toList();
      }
    }

    return CourseLoadPreview(
      success: true,
      message: 'Course preview ready.',
      normalizedPath: normalizedPath,
      courseName: courseName,
      contents: contents,
      parseResult: parseResult,
      maxDepth: maxDepth,
      courseVersionId: courseVersionId,
      hasExisting: hasExisting,
      deletedEntries: deletedEntries,
      addedEntries: addedEntries,
      oldIdToNewId: oldIdToNewId,
    );
  }

  Future<CourseLoadResult> applyCourseLoad({
    required int teacherId,
    required CourseLoadPreview preview,
    required CourseReloadMode mode,
  }) async {
    if (!preview.success ||
        preview.parseResult == null ||
        preview.normalizedPath == null ||
        preview.courseName == null ||
        preview.contents == null ||
        preview.maxDepth == null) {
      return CourseLoadResult(
        success: false,
        message: preview.message.isNotEmpty
            ? preview.message
            : 'Course preview missing required data.',
      );
    }

    final courseId = preview.courseVersionId ??
        await _db.createCourseVersion(
          teacherId: teacherId,
          subject: preview.courseName!,
          sourcePath: preview.normalizedPath,
          granularity: preview.maxDepth!,
          textbookText: preview.contents!,
        );
    var courseSubject = preview.courseName!;
    if (preview.courseVersionId != null) {
      final existing = await _db.getCourseVersionById(courseId);
      if (existing == null) {
        return CourseLoadResult(
          success: false,
          message: 'Course version not found: $courseId',
        );
      }
      courseSubject = existing.subject;
    }

    await _db.transaction(() async {
      List<ProgressEntry> progressEntries = [];
      List<ChatSession> sessions = [];
      if (mode == CourseReloadMode.override) {
        progressEntries = await (_db.select(_db.progressEntries)
              ..where((tbl) => tbl.courseVersionId.equals(courseId)))
            .get();
        sessions = await (_db.select(_db.chatSessions)
              ..where((tbl) => tbl.courseVersionId.equals(courseId)))
            .get();
      }

      await (_db.delete(_db.courseNodes)
            ..where((tbl) => tbl.courseVersionId.equals(courseId)))
          .go();
      await (_db.delete(_db.courseEdges)
            ..where((tbl) => tbl.courseVersionId.equals(courseId)))
          .go();

      var orderIndex = 0;
      for (final node in preview.parseResult!.nodes.values) {
        if (node.isPlaceholder) {
          continue;
        }
        await _db.into(_db.courseNodes).insert(
              CourseNodesCompanion.insert(
                courseVersionId: courseId,
                kpKey: node.id,
                title: node.title,
                description:
                    node.rawLine.isNotEmpty ? node.rawLine : node.title,
                orderIndex: orderIndex++,
              ),
              mode: InsertMode.insertOrReplace,
            );
      }

      for (final node in preview.parseResult!.nodes.values) {
        if (node.isPlaceholder) {
          continue;
        }
        final parentId = node.parentId;
        if (parentId == null) {
          continue;
        }
        await _db.into(_db.courseEdges).insert(
              CourseEdgesCompanion.insert(
                courseVersionId: courseId,
                fromKpKey: parentId,
                toKpKey: node.id,
              ),
            );
      }

      await (_db.update(_db.courseVersions)
            ..where((tbl) => tbl.id.equals(courseId)))
          .write(
        CourseVersionsCompanion(
          subject: Value(courseSubject),
          sourcePath: Value(preview.normalizedPath!),
          granularity: Value(preview.maxDepth!),
          textbookText: Value(preview.contents!),
          treeGenStatus: const Value('loaded'),
          treeGenRawResponse: const Value(null),
          treeGenValid: const Value(true),
          treeGenParseError: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (mode == CourseReloadMode.override) {
        final newKpKeys = preview.parseResult!.nodes.values
            .where((node) => !node.isPlaceholder)
            .map((node) => node.id)
            .toSet();
        final deletedSessionIds = sessions
            .where((session) => !newKpKeys.contains(session.kpKey))
            .map((session) => session.id)
            .toList();
        if (deletedSessionIds.isNotEmpty) {
          await (_db.delete(_db.chatMessages)
                ..where((tbl) => tbl.sessionId.isIn(deletedSessionIds)))
              .go();
          await (_db.delete(_db.llmCalls)
                ..where((tbl) => tbl.sessionId.isIn(deletedSessionIds)))
              .go();
          await (_db.delete(_db.chatSessions)
                ..where((tbl) => tbl.id.isIn(deletedSessionIds)))
              .go();
        }

        final merged = _mergeProgressEntries(
          progressEntries: progressEntries,
          oldIdToNewId: preview.oldIdToNewId,
        );

        await (_db.delete(_db.progressEntries)
              ..where((tbl) =>
                  tbl.courseVersionId.equals(courseId) &
                  tbl.kpKey.isNotValue(kTreeViewStateKpKey)))
            .go();

        for (final entry in merged.values) {
          await _db.into(_db.progressEntries).insert(
                ProgressEntriesCompanion.insert(
                  studentId: entry.studentId,
                  courseVersionId: courseId,
                  kpKey: entry.kpKey,
                  lit: Value(entry.lit),
                  litPercent: Value(
                    _deriveProgressPercent(
                      easyPassedCount: entry.easyPassedCount,
                      mediumPassedCount: entry.mediumPassedCount,
                      hardPassedCount: entry.hardPassedCount,
                      fallbackPercent: entry.litPercent,
                    ),
                  ),
                  questionLevel: const Value(null),
                  easyPassedCount: Value(entry.easyPassedCount),
                  mediumPassedCount: Value(entry.mediumPassedCount),
                  hardPassedCount: Value(entry.hardPassedCount),
                  summaryText: Value(entry.summaryText),
                  summaryRawResponse: Value(entry.summaryRawResponse),
                  summaryValid: Value(entry.summaryValid),
                  updatedAt: Value(entry.updatedAt),
                ),
                mode: InsertMode.insertOrReplace,
              );
        }

        for (final session in sessions) {
          final newId = preview.oldIdToNewId[session.kpKey];
          if (newId == null || newId == session.kpKey) {
            continue;
          }
          await (_db.update(_db.chatSessions)
                ..where((tbl) => tbl.id.equals(session.id)))
              .write(ChatSessionsCompanion(kpKey: Value(newId)));
        }
      } else if (mode == CourseReloadMode.wipe) {
        await (_db.delete(_db.progressEntries)
              ..where((tbl) => tbl.courseVersionId.equals(courseId)))
            .go();
      }
    });

    if (_courseArtifactService != null) {
      await _courseArtifactService.rebuildCourseArtifacts(
        courseVersionId: courseId,
        folderPath: preview.normalizedPath!,
      );
    }

    final course = await _db.getCourseVersionById(courseId);
    return CourseLoadResult(
      success: true,
      message: 'Course loaded.',
      course: course,
    );
  }

  List<String> _validateContents({
    required String contents,
    required SkillTreeParseResult parseResult,
    required String basePath,
    required String contentsLabel,
  }) {
    final errors = <String>[];
    if (parseResult.nodes.isEmpty) {
      errors.add('$contentsLabel: no nodes found.');
    }

    final idCounts = <String, int>{};
    final lines = contents.split(RegExp(r'\r\n|\n|\r'));
    if (lines.isNotEmpty && lines.first.startsWith('\uFEFF')) {
      lines[0] = lines.first.substring(1);
    }
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final match = _idPattern.firstMatch(trimmed);
      if (match == null) {
        errors.add('$contentsLabel: invalid line "$trimmed".');
        continue;
      }
      final id = match.group(1)!;
      idCounts[id] = (idCounts[id] ?? 0) + 1;
    }

    for (final entry in idCounts.entries) {
      if (entry.value > 1) {
        errors.add('$contentsLabel: duplicate id "${entry.key}".');
      }
    }

    for (final node in parseResult.nodes.values) {
      if (node.isPlaceholder) {
        errors.add('$contentsLabel: missing parent id "${node.id}".');
      }
    }

    for (final node in parseResult.nodes.values) {
      if (node.isPlaceholder) {
        continue;
      }
      final lecturePath = p.join(basePath, '${node.id}_lecture.txt');
      final legacyLecturePath = p.join(basePath, node.id, 'lecture.txt');
      if (!File(lecturePath).existsSync() &&
          !File(legacyLecturePath).existsSync()) {
        errors.add('Missing file: $lecturePath');
      }
    }

    return errors;
  }

  String _signatureFromLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final match = _idPattern.firstMatch(trimmed);
    if (match == null) {
      return trimmed;
    }
    var rest = match.group(2)?.trim() ?? '';
    if (rest.startsWith('.')) {
      rest = rest.substring(1).trimLeft();
    }
    return rest;
  }

  List<_LineEntry> _parseLineEntries(
    String contents,
    SkillTreeParseResult parseResult,
  ) {
    final entries = <_LineEntry>[];
    final lines = contents.split(RegExp(r'\r\n|\n|\r'));
    if (lines.isNotEmpty && lines.first.startsWith('\uFEFF')) {
      lines[0] = lines.first.substring(1);
    }
    var orderIndex = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final match = _idPattern.firstMatch(trimmed);
      if (match == null) {
        continue;
      }
      final id = match.group(1)!;
      final node = parseResult.nodes[id];
      if (node == null || node.isPlaceholder) {
        continue;
      }
      entries.add(
        _LineEntry(
          id: id,
          signature: _signatureFromLine(trimmed),
          rawLine: trimmed,
          orderIndex: orderIndex++,
        ),
      );
    }
    return entries;
  }

  Map<String, _ProgressMergeState> _mergeProgressEntries({
    required List<ProgressEntry> progressEntries,
    required Map<String, String> oldIdToNewId,
  }) {
    final merged = <String, _ProgressMergeState>{};
    for (final entry in progressEntries) {
      if (entry.kpKey == kTreeViewStateKpKey) {
        continue;
      }
      final newId = oldIdToNewId[entry.kpKey];
      if (newId == null) {
        continue;
      }
      final key = '${entry.studentId}::$newId';
      final existing = merged[key];
      if (existing == null) {
        merged[key] = _ProgressMergeState.fromEntry(entry, newId);
      } else {
        existing.merge(entry);
      }
    }
    return merged;
  }

  int _maxDepth(Iterable<SkillNode> nodes) {
    var maxDepth = 1;
    for (final node in nodes) {
      if (node.isPlaceholder) {
        continue;
      }
      final depth = node.id.split('.').length;
      if (depth > maxDepth) {
        maxDepth = depth;
      }
    }
    return maxDepth;
  }
}

class _LineEntry {
  _LineEntry({
    required this.id,
    required this.signature,
    required this.rawLine,
    required this.orderIndex,
  });

  final String id;
  final String signature;
  final String rawLine;
  final int orderIndex;
}

class _ProgressMergeState {
  _ProgressMergeState.fromEntry(ProgressEntry entry, String newKpKey)
      : studentId = entry.studentId,
        courseVersionId = entry.courseVersionId,
        kpKey = newKpKey,
        lit = entry.lit,
        litPercent = entry.litPercent,
        easyPassedCount = entry.easyPassedCount,
        mediumPassedCount = entry.mediumPassedCount,
        hardPassedCount = entry.hardPassedCount,
        summaryText = entry.summaryText,
        summaryRawResponse = entry.summaryRawResponse,
        summaryValid = entry.summaryValid,
        updatedAt = entry.updatedAt;

  final int studentId;
  final int courseVersionId;
  final String kpKey;
  bool lit;
  int litPercent;
  int easyPassedCount;
  int mediumPassedCount;
  int hardPassedCount;
  String? summaryText;
  String? summaryRawResponse;
  bool? summaryValid;
  DateTime updatedAt;

  void merge(ProgressEntry entry) {
    lit = lit || entry.lit;
    if (entry.easyPassedCount > easyPassedCount) {
      easyPassedCount = entry.easyPassedCount;
    }
    if (entry.mediumPassedCount > mediumPassedCount) {
      mediumPassedCount = entry.mediumPassedCount;
    }
    if (entry.hardPassedCount > hardPassedCount) {
      hardPassedCount = entry.hardPassedCount;
    }
    litPercent = _deriveProgressPercent(
      easyPassedCount: easyPassedCount,
      mediumPassedCount: mediumPassedCount,
      hardPassedCount: hardPassedCount,
      fallbackPercent: entry.litPercent > litPercent ? entry.litPercent : litPercent,
    );
    if (entry.updatedAt.isAfter(updatedAt)) {
      summaryText = entry.summaryText;
      summaryRawResponse = entry.summaryRawResponse;
      summaryValid = entry.summaryValid;
      updatedAt = entry.updatedAt;
    }
  }
}

int _deriveProgressPercent({
  required int easyPassedCount,
  required int mediumPassedCount,
  required int hardPassedCount,
  int fallbackPercent = 0,
}) {
  if (hardPassedCount > 0) {
    return 100;
  }
  if (mediumPassedCount > 0) {
    return 66;
  }
  if (easyPassedCount > 0) {
    return 33;
  }
  return fallbackPercent.clamp(0, 100);
}
