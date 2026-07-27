import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/app_database.dart';
import '../llm/llm_models.dart';
import '../llm/llm_service.dart';
import '../llm/prompt_renderer.dart';
import '../llm/prompt_repository.dart';
import 'course_artifact_service.dart';
import 'course_source_policy.dart';
import 'prompt_variable_registry.dart';

enum CourseBuilderMode {
  content,
  question,
}

enum CourseBuilderWriteMode {
  add,
  replace,
}

class CourseBuilderService {
  CourseBuilderService({
    required AppDatabase db,
    required LlmService llmService,
    required PromptRepository promptRepository,
    required CourseArtifactService courseArtifactService,
  })  : _db = db,
        _llmService = llmService,
        _promptRepository = promptRepository,
        _courseArtifactService = courseArtifactService;

  final AppDatabase _db;
  final LlmService _llmService;
  final PromptRepository _promptRepository;
  final CourseArtifactService _courseArtifactService;
  final PromptRenderer _renderer = PromptRenderer();

  Future<CourseVersion> ensureEditableArtifacts({
    required CourseVersion courseVersion,
    Future<CourseVersion> Function(CourseVersion courseVersion)?
        repairFromServer,
  }) async {
    final artifacts =
        await _courseArtifactService.readCourseArtifacts(courseVersion.id);
    final bundlePath = artifacts?.contentBundlePath.trim() ?? '';
    if (bundlePath.isNotEmpty && File(bundlePath).existsSync()) {
      return courseVersion;
    }

    final editableSource = CourseSourcePolicy.editableSourceDirectory(
      courseVersion.sourcePath,
    );
    if (editableSource != null) {
      await _courseArtifactService.rebuildCourseArtifacts(
        courseVersionId: courseVersion.id,
        folderPath: editableSource.path,
      );
      return courseVersion;
    }

    if (repairFromServer == null) {
      throw StateError(
        'Cached course artifacts are missing for course version '
        '${courseVersion.id}. Pull the latest server bundle or save the course '
        'as an editable source folder before editing.',
      );
    }
    final repaired = await repairFromServer(courseVersion);
    final repairedArtifacts =
        await _courseArtifactService.readCourseArtifacts(repaired.id);
    final repairedBundlePath =
        repairedArtifacts?.contentBundlePath.trim() ?? '';
    if (repairedBundlePath.isEmpty || !File(repairedBundlePath).existsSync()) {
      throw StateError(
        'Course artifact repair did not produce a cached content bundle for '
        'course version ${repaired.id}.',
      );
    }
    return repaired;
  }

  Future<String> generate({
    required CourseVersion courseVersion,
    required String kpKey,
    required String kpTitle,
    required CourseBuilderMode mode,
    required String conversationHistory,
  }) async {
    final promptName = _promptNameForMode(mode);
    final existingText = mode == CourseBuilderMode.content
        ? await readLessonContent(
            courseVersion: courseVersion,
            kpKey: kpKey,
          )
        : await readAllQuestionText(
            courseVersion: courseVersion,
            kpKey: kpKey,
          );
    final template = await _promptRepository.loadPrompt(
      promptName,
      teacherId: courseVersion.teacherId,
      courseKey: _normalizeCourseKey(courseVersion.sourcePath),
    );
    final values = PromptVariableRegistry.buildTutorPromptValues(
      kpTitle: kpTitle,
      kpDescription: '',
      studentInput: '',
      recentChat: '',
      conversationHistory: conversationHistory,
      helpBias: '',
      studentSummary: '',
      studentContext: '',
      studentProfile: '',
      studentPreferences: '',
      lessonContent:
          mode == CourseBuilderMode.content ? existingText.trim() : '',
      errorBookSummary: '',
      presentedQuestions:
          mode == CourseBuilderMode.question ? existingText.trim() : '',
      activeReviewQuestionJson: 'null',
      reviewPassCounts: jsonEncode(const <String, int>{}),
      reviewFailCounts: jsonEncode(const <String, int>{}),
      reviewCorrectTotal: '0',
      reviewAttemptTotal: '0',
    );
    final rendered = _renderer.render(template, values);
    final handle = _llmService.startCall(
      promptName: promptName,
      renderedPrompt: rendered,
      context: LlmCallContext(
        teacherId: courseVersion.teacherId,
        courseVersionId: courseVersion.id,
        kpKey: kpKey,
        action: promptName,
      ),
    );
    final result = await handle.future;
    return result.responseText.trim();
  }

  Future<String> readLessonContent({
    required CourseVersion courseVersion,
    required String kpKey,
  }) async {
    return _readCourseText(
      courseVersion: courseVersion,
      candidateRelativePaths: _lessonRelativePaths(kpKey),
    );
  }

  Future<String> readQuestionText({
    required CourseVersion courseVersion,
    required String kpKey,
    required String level,
  }) async {
    final normalizedLevel = _normalizeLevel(level);
    return _readCourseText(
      courseVersion: courseVersion,
      candidateRelativePaths: _questionRelativePaths(
        kpKey,
        normalizedLevel,
      ),
    );
  }

  Future<String> readAllQuestionText({
    required CourseVersion courseVersion,
    required String kpKey,
  }) async {
    final parts = <String>[];
    for (final level in const <String>['easy', 'medium', 'hard']) {
      final text = await readQuestionText(
        courseVersion: courseVersion,
        kpKey: kpKey,
        level: level,
      );
      if (text.trim().isEmpty) {
        continue;
      }
      parts.add('${level.toUpperCase()}:\n${text.trim()}');
    }
    return parts.join('\n\n');
  }

  String buildPreviewText({
    required String currentText,
    required String incomingText,
    required CourseBuilderWriteMode writeMode,
  }) {
    final incoming = incomingText.trim();
    if (writeMode == CourseBuilderWriteMode.replace) {
      return incoming;
    }
    final current = currentText.trimRight();
    if (current.isEmpty) {
      return incoming;
    }
    if (incoming.isEmpty) {
      return current;
    }
    return '$current\n\n$incoming';
  }

  Future<void> saveLessonContent({
    required CourseVersion courseVersion,
    required String kpKey,
    required String text,
  }) async {
    await _writeCourseText(
      courseVersion: courseVersion,
      preferredRelativePath: '${kpKey}_lecture.txt',
      candidateRelativePaths: _lessonRelativePaths(kpKey),
      text: text,
    );
  }

  Future<void> saveQuestionText({
    required CourseVersion courseVersion,
    required String kpKey,
    required String level,
    required String text,
  }) async {
    final normalizedLevel = _normalizeLevel(level);
    await _writeCourseText(
      courseVersion: courseVersion,
      preferredRelativePath: '${kpKey}_$normalizedLevel.txt',
      candidateRelativePaths: _questionRelativePaths(
        kpKey,
        normalizedLevel,
      ),
      text: text,
    );
  }

  Future<String> _readCourseText({
    required CourseVersion courseVersion,
    required List<String> candidateRelativePaths,
  }) async {
    final source = _resolveEditableSourceDirectory(courseVersion);
    if (source != null) {
      final file = _firstExistingSourceFile(
        sourcePath: source.path,
        relativePaths: candidateRelativePaths,
      );
      if (file != null) {
        return file.readAsString(encoding: utf8);
      }
    }
    return await _courseArtifactService.readStoredTextEntry(
          courseVersionId: courseVersion.id,
          candidateRelativePaths: candidateRelativePaths,
        ) ??
        '';
  }

  Future<void> _writeCourseText({
    required CourseVersion courseVersion,
    required String preferredRelativePath,
    required List<String> candidateRelativePaths,
    required String text,
  }) async {
    final source = _resolveEditableSourceDirectory(courseVersion);
    if (source != null) {
      final file = _firstExistingSourceFile(
            sourcePath: source.path,
            relativePaths: candidateRelativePaths,
          ) ??
          File(p.join(source.path, preferredRelativePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(text, encoding: utf8, flush: true);
      await _courseArtifactService.rebuildCourseArtifacts(
        courseVersionId: courseVersion.id,
        folderPath: source.path,
      );
    } else {
      await _courseArtifactService.updateStoredTextEntry(
        courseVersionId: courseVersion.id,
        preferredRelativePath: preferredRelativePath,
        candidateRelativePaths: candidateRelativePaths,
        text: text,
      );
    }
    await _db.updateCourseVersion(
      id: courseVersion.id,
      subject: courseVersion.subject,
      sourcePath: courseVersion.sourcePath,
      granularity: courseVersion.granularity,
      textbookText: courseVersion.textbookText,
    );
  }

  Directory? _resolveEditableSourceDirectory(CourseVersion courseVersion) {
    return CourseSourcePolicy.editableSourceDirectory(
      courseVersion.sourcePath,
    );
  }

  File? _firstExistingSourceFile({
    required String sourcePath,
    required List<String> relativePaths,
  }) {
    for (final relativePath in relativePaths) {
      final file = File(p.join(sourcePath, relativePath));
      if (file.existsSync()) {
        return file;
      }
    }
    return null;
  }

  String _promptNameForMode(CourseBuilderMode mode) {
    switch (mode) {
      case CourseBuilderMode.content:
        return PromptVariableRegistry.courseBuilderContentPrompt;
      case CourseBuilderMode.question:
        return PromptVariableRegistry.courseBuilderQuestionPrompt;
    }
  }

  List<String> _lessonRelativePaths(String kpKey) {
    return <String>[
      '${kpKey}_lecture.txt',
      p.join(kpKey, 'lecture.txt'),
    ];
  }

  List<String> _questionRelativePaths(String kpKey, String level) {
    return <String>[
      '${kpKey}_$level.txt',
      p.join(kpKey, level, 'questions.txt'),
    ];
  }

  String _normalizeLevel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'easy' ||
        normalized == 'medium' ||
        normalized == 'hard') {
      return normalized;
    }
    throw StateError('Unsupported question level: $value');
  }

  String? _normalizeCourseKey(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return p.normalize(trimmed);
  }
}
