import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../llm/prompt_repository.dart';
import '../../services/app_services.dart';
import '../../services/prompt_template_validator.dart';
import 'package:family_teacher/l10n/app_localizations.dart';

class PromptSettingsPage extends StatefulWidget {
  const PromptSettingsPage({super.key, required this.teacherId});

  final int teacherId;

  @override
  State<PromptSettingsPage> createState() => _PromptSettingsPageState();
}

class _PromptSettingsPageState extends State<PromptSettingsPage> {
  final _validator = PromptTemplateValidator();
  bool _loadingScopes = true;
  List<_PromptScope> _scopes = const [];
  _PromptScope? _selectedScope;
  bool _didLoadScopes = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadScopes) {
      return;
    }
    _didLoadScopes = true;
    _loadScopes();
  }

  Future<void> _loadScopes() async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final courses = await db.watchCourseVersions(widget.teacherId).first;
    final scopes = <_PromptScope>[
      _PromptScope.systemScope(label: l10n.promptScopeDefault),
    ];
    for (final course in courses) {
      final courseKey = (course.sourcePath ?? '').trim();
      if (courseKey.isEmpty) {
        continue;
      }
      scopes.add(
        _PromptScope.courseScope(
          label: course.subject,
          courseKey: courseKey,
        ),
      );
      final assignments = await db.getAssignmentsForCourse(course.id);
      for (final assignment in assignments) {
        final studentId = assignment.studentId;
        final student = await db.getUserById(studentId);
        final label =
            '${course.subject} - ${student?.username ?? studentId.toString()}';
        scopes.add(
          _PromptScope(
            label: label,
            isSystem: false,
            courseKey: courseKey,
            studentId: studentId,
          ),
        );
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _scopes = scopes;
      _selectedScope = scopes.isNotEmpty ? scopes.first : null;
      _loadingScopes = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final promptRepo = context.read<AppServices>().promptRepository;

    final items = [
      _PromptItem(
        name: 'learn_init',
        title: '${l10n.promptLearn} (Init)',
      ),
      _PromptItem(
        name: 'learn_cont',
        title: '${l10n.promptLearn} (Cont)',
      ),
      _PromptItem(
        name: 'review_init',
        title: '${l10n.promptReview} (Init)',
      ),
      _PromptItem(
        name: 'review_cont',
        title: '${l10n.promptReview} (Cont)',
      ),
      _PromptItem(
        name: 'summary',
        title: 'Summary (Final)',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.promptTemplatesTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loadingScopes)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            )
          else if (_scopes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No prompt scopes available yet.'),
            )
          else
            DropdownButtonFormField<_PromptScope>(
              initialValue: _selectedScope,
              decoration: InputDecoration(labelText: l10n.promptScopeLabel),
              items: _scopes
                  .map(
                    (scope) => DropdownMenuItem(
                      value: scope,
                      child: Text(scope.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedScope = value);
              },
            ),
          const SizedBox(height: 16),
          if (_selectedScope != null)
            _StudentPromptProfileSection(
              teacherId: widget.teacherId,
              courseKey: _selectedScope?.courseKey,
              studentId: _selectedScope?.studentId,
            ),
          if (_selectedScope != null) const SizedBox(height: 16),
          if (_selectedScope != null)
            _StudentPromptPreviewSection(
              teacherId: widget.teacherId,
              courseKey: _selectedScope?.courseKey,
              studentId: _selectedScope?.studentId,
            ),
          if (_selectedScope != null) const SizedBox(height: 24),
          if (_selectedScope != null)
            ...items.map((item) {
              final scope = _selectedScope;
              final courseKey = scope?.courseKey;
              final studentId = scope?.studentId;
              return FutureBuilder<PromptTemplate?>(
                future: db.getActivePromptTemplate(
                  teacherId: widget.teacherId,
                  promptName: item.name,
                  courseKey: courseKey,
                  studentId: studentId,
                ),
                builder: (context, snapshot) {
                  final active = snapshot.data;
                  final statusText = active == null
                      ? l10n.promptStatusDefault
                      : l10n.promptStatusCustom(
                          _formatTime(active.createdAt),
                        );
                  return ExpansionTile(
                    title: Text(item.title),
                    subtitle: Text(statusText),
                    childrenPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton(
                            onPressed: () => _openEditor(
                              context,
                              promptRepo,
                              item,
                              active?.content,
                              isSystemScope: scope?.isSystem ?? false,
                              courseKey: courseKey,
                              studentId: studentId,
                            ),
                            child: Text(l10n.editButton),
                          ),
                          TextButton(
                            onPressed: () => _showCurrentPreview(
                              context,
                              promptRepo,
                              item.name,
                              isSystemScope: scope?.isSystem ?? false,
                              courseKey: courseKey,
                              studentId: studentId,
                            ),
                            child: Text(l10n.previewButton),
                          ),
                          TextButton(
                            onPressed: () async {
                              if (scope == null) {
                                return;
                              }
                              await db.clearActivePromptTemplates(
                                teacherId: widget.teacherId,
                                promptName: item.name,
                                courseKey: courseKey,
                                studentId: studentId,
                              );
                              promptRepo.invalidatePromptCache(
                                promptName: item.name,
                              );
                              if (context.mounted) {
                                _showMessage(context, l10n.promptReverted);
                              }
                            },
                            child: Text(l10n.useDefaultButton),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.promptHistoryTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      StreamBuilder<List<PromptTemplate>>(
                        stream: db.watchPromptTemplates(
                          teacherId: widget.teacherId,
                          promptName: item.name,
                          courseKey: courseKey,
                          studentId: studentId,
                        ),
                        builder: (context, historySnapshot) {
                          final history = historySnapshot.data ?? [];
                          if (history.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(l10n.promptHistoryEmpty),
                            );
                          }
                          return Column(
                            children: history.map((entry) {
                              final snippet = _snippet(entry.content);
                              return ListTile(
                                title: Text(_formatTime(entry.createdAt)),
                                subtitle: Text(snippet),
                                trailing: Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: () => _showPromptDiff(
                                        context,
                                        promptRepo,
                                        item.name,
                                        entry,
                                        isSystemScope: scope?.isSystem ?? false,
                                        courseKey: courseKey,
                                        studentId: studentId,
                                      ),
                                      child: const Text('Diff'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        await db.setActivePromptTemplate(
                                          teacherId: widget.teacherId,
                                          promptName: item.name,
                                          templateId: entry.id,
                                          courseKey: courseKey,
                                          studentId: studentId,
                                        );
                                        promptRepo.invalidatePromptCache(
                                          promptName: item.name,
                                        );
                                        if (context.mounted) {
                                          _showMessage(
                                            context,
                                            l10n.promptActivated,
                                          );
                                        }
                                      },
                                      child: Text(l10n.useButton),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  );
                },
              );
            }).toList(),
        ],
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, PromptRepository promptRepo,
      _PromptItem item, String? currentContent,
      {required bool isSystemScope, String? courseKey, int? studentId}) async {
    final l10n = AppLocalizations.of(context)!;
    final defaultContent = isSystemScope
        ? await promptRepo.loadBundledSystemPrompt(item.name)
        : await promptRepo.loadAppendPrompt(
            item.name,
            teacherId: widget.teacherId,
            courseKey: courseKey,
            studentId: studentId,
          );
    final controller =
        TextEditingController(text: currentContent ?? defaultContent);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.promptEditTitle(item.title)),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 18,
                  minLines: 8,
                  decoration: InputDecoration(
                    labelText: l10n.promptTemplateLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.promptRequiredVars(
                    _validator.requiredVariables(item.name).join(', '),
                  ),
                ),
                Text(
                  l10n.promptAllowedVars(
                    _validator.allowedVariables(item.name).join(', '),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Prompt variables',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 6),
                ..._buildVariableRows(item.name),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'All supported variables',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 6),
                ..._buildVariableRowsForVariables(
                  _validator.allSupportedVariables().toList()..sort(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.saveButton),
          ),
        ],
      ),
    );

    if (result == null) {
      return;
    }

    final validation = _validator.validate(
      promptName: item.name,
      content: result,
      allowMissingRequired: true,
    );
    if (!validation.isValid) {
      await _showValidationErrors(context, validation);
      return;
    }

    final db = context.read<AppDatabase>();
    await db.insertPromptTemplate(
      teacherId: widget.teacherId,
      promptName: item.name,
      content: result,
      courseKey: courseKey,
      studentId: studentId,
    );
    promptRepo.invalidatePromptCache(promptName: item.name);
    if (context.mounted) {
      _showMessage(context, l10n.promptSaved);
    }
  }

  Future<void> _showCurrentPreview(
    BuildContext context,
    PromptRepository promptRepo,
    String promptName, {
    required bool isSystemScope,
    String? courseKey,
    int? studentId,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final preview = isSystemScope
        ? await promptRepo.loadResolvedSystemPrompt(
            promptName,
            teacherId: widget.teacherId,
          )
        : await promptRepo.buildPromptPreview(
            name: promptName,
            teacherId: widget.teacherId,
            courseKey: courseKey,
            studentId: studentId,
            includeSystem: false,
          );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.promptPreviewTitle),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(preview),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }

  Future<void> _showPromptDiff(
    BuildContext context,
    PromptRepository promptRepo,
    String promptName,
    PromptTemplate entry, {
    required bool isSystemScope,
    String? courseKey,
    int? studentId,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final current = isSystemScope
        ? await promptRepo.loadResolvedSystemPrompt(
            promptName,
            teacherId: widget.teacherId,
          )
        : await promptRepo.buildPromptPreview(
            name: promptName,
            teacherId: widget.teacherId,
            courseKey: courseKey,
            studentId: studentId,
            includeSystem: false,
          );
    final historical = isSystemScope
        ? entry.content
        : await promptRepo.buildPromptPreview(
            name: promptName,
            teacherId: widget.teacherId,
            courseKey: courseKey,
            studentId: studentId,
            courseAppendOverride: studentId == null ? entry.content : null,
            studentAppendOverride: studentId == null ? null : entry.content,
            includeSystem: false,
          );
    final diff = _buildUnifiedDiff(
      current,
      historical,
      fromLabel: 'current',
      toLabel: 'historical',
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diff to current'),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: SelectableText(diff),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }

  String _buildUnifiedDiff(
    String from,
    String to, {
    required String fromLabel,
    required String toLabel,
  }) {
    final fromLines = _splitLines(from);
    final toLines = _splitLines(to);
    final diffLines = _lineDiff(fromLines, toLines);
    return [
      '--- $fromLabel',
      '+++ $toLabel',
      ...diffLines,
    ].join('\n');
  }

  List<String> _splitLines(String input) {
    return input.split('\n');
  }

  List<String> _lineDiff(List<String> from, List<String> to) {
    final m = from.length;
    final n = to.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (var i = 1; i <= m; i++) {
      final fromLine = from[i - 1];
      for (var j = 1; j <= n; j++) {
        if (fromLine == to[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          final a = dp[i - 1][j];
          final b = dp[i][j - 1];
          dp[i][j] = a >= b ? a : b;
        }
      }
    }

    final result = <String>[];
    var i = m;
    var j = n;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && from[i - 1] == to[j - 1]) {
        result.add('  ${from[i - 1]}');
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        result.add('+ ${to[j - 1]}');
        j--;
      } else if (i > 0) {
        result.add('- ${from[i - 1]}');
        i--;
      }
    }
    return result.reversed.toList();
  }

  Future<void> _showValidationErrors(
    BuildContext context,
    PromptValidationResult validation,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final missing = validation.missingVariables.join(', ');
    final unknown = validation.unknownVariables.join(', ');
    final messages = <String>[];
    if (validation.missingVariables.isNotEmpty) {
      messages.add(l10n.promptMissingVars(missing));
    }
    if (validation.unknownVariables.isNotEmpty) {
      messages.add(l10n.promptUnknownVars(unknown));
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.promptValidationFailedTitle),
        content: SelectableText(messages.join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatTime(DateTime time) {
    final year = time.year.toString().padLeft(4, '0');
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  String _snippet(String content) {
    final trimmed = content.trim();
    if (trimmed.length <= 120) {
      return trimmed;
    }
    return '${trimmed.substring(0, 120)}...';
  }

  List<Widget> _buildVariableRows(String promptName) {
    final allowed = _validator.allowedVariables(promptName).toList()..sort();
    return _buildVariableRowsForVariables(allowed);
  }

  List<Widget> _buildVariableRowsForVariables(List<String> variables) {
    final info = _variableDescriptions();
    return variables.map((variable) {
      final description =
          info[variable] ?? 'Value provided by the session context.';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SelectableText.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '{{$variable}}: ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: description),
            ],
          ),
        ),
      );
    }).toList();
  }

  Map<String, String> _variableDescriptions() {
    return {
      'subject': 'Course subject from the loaded course metadata.',
      'course_version_id': 'ID of the active course version for this session.',
      'kp_key': 'Knowledge point ID of the selected node.',
      'kp_title': 'Knowledge point title from the course node.',
      'kp_description':
          'Knowledge point description from the course node (raw line).',
      'conversation_history':
          'Chat history built from messages in the current session.',
      'session_history':
          'Alias for conversation_history (same session chat history).',
      'student_input': 'Latest student input text in this session.',
      'student_intent':
          'Student-declared message intent: AUTO | HELP_REQUEST | PARTIAL_ATTEMPT | FINAL_ANSWER.',
      'student_summary':
          'Saved summary for this student/course/kp (falls back to the session summary).',
      'student_profile':
          'Resolved student profile from teacher-defined fields (level, language, interests, support notes).',
      'student_preferences':
          'Resolved student preferences from teacher-defined fields (tone, pace, format).',
      'lesson_content': 'Lesson content for the current knowledge point.',
      'types':
          'List of practice types for this knowledge point (includes OTHER).',
      'error_book_summary':
          'Aggregated mistake counts and tags for this knowledge point.',
      'practice_history_summary':
          'Compressed summary of recent practice outcomes.',
      'presented_questions':
          'Candidate question pool provided for REVIEW_INIT selection.',
      'recent_dialogue':
          'Dialogue since the last INIT turn (may be truncated).',
      'prev_json': 'Previous model JSON output for the current segment.',
      'last_evidence': 'Last evidence object from REVIEW.',
      'current_mastery_level': 'Current mastery level before SUMMARY decision.',
      'current_difficulty_level':
          'Current review difficulty level (easy/medium/hard) before selecting the next question.',
    };
  }
}

class _StudentPromptProfileSection extends StatefulWidget {
  const _StudentPromptProfileSection({
    required this.teacherId,
    required this.courseKey,
    required this.studentId,
  });

  final int teacherId;
  final String? courseKey;
  final int? studentId;

  @override
  State<_StudentPromptProfileSection> createState() =>
      _StudentPromptProfileSectionState();
}

class _StudentPromptProfileSectionState
    extends State<_StudentPromptProfileSection> {
  final _gradeLevelController = TextEditingController();
  final _readingLevelController = TextEditingController();
  final _languageController = TextEditingController();
  final _interestsController = TextEditingController();
  final _toneController = TextEditingController();
  final _paceController = TextEditingController();
  final _formatController = TextEditingController();
  final _supportNotesController = TextEditingController();

  bool _loading = true;
  DateTime? _lastSavedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _StudentPromptProfileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseKey != widget.courseKey ||
        oldWidget.studentId != widget.studentId ||
        oldWidget.teacherId != widget.teacherId) {
      _load();
    }
  }

  @override
  void dispose() {
    _gradeLevelController.dispose();
    _readingLevelController.dispose();
    _languageController.dispose();
    _interestsController.dispose();
    _toneController.dispose();
    _paceController.dispose();
    _formatController.dispose();
    _supportNotesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = context.read<AppDatabase>();
    final profile = await db.getStudentPromptProfile(
      teacherId: widget.teacherId,
      courseKey: widget.courseKey,
      studentId: widget.studentId,
    );
    if (!mounted) {
      return;
    }
    _gradeLevelController.text = profile?.gradeLevel ?? '';
    _readingLevelController.text = profile?.readingLevel ?? '';
    _languageController.text = profile?.preferredLanguage ?? '';
    _interestsController.text = profile?.interests ?? '';
    _toneController.text = profile?.preferredTone ?? '';
    _paceController.text = profile?.preferredPace ?? '';
    _formatController.text = profile?.preferredFormat ?? '';
    _supportNotesController.text = profile?.supportNotes ?? '';
    _lastSavedAt = profile?.updatedAt ?? profile?.createdAt;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final db = context.read<AppDatabase>();
    final hasAny = _hasAnyValue();
    if (!hasAny) {
      await db.deleteStudentPromptProfile(
        teacherId: widget.teacherId,
        courseKey: widget.courseKey,
        studentId: widget.studentId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _lastSavedAt = null);
      _showMessage(AppLocalizations.of(context)!.studentPromptCleared);
      return;
    }
    await db.upsertStudentPromptProfile(
      teacherId: widget.teacherId,
      courseKey: widget.courseKey,
      studentId: widget.studentId,
      gradeLevel: _gradeLevelController.text,
      readingLevel: _readingLevelController.text,
      preferredLanguage: _languageController.text,
      interests: _interestsController.text,
      preferredTone: _toneController.text,
      preferredPace: _paceController.text,
      preferredFormat: _formatController.text,
      supportNotes: _supportNotesController.text,
    );
    final refreshed = await db.getStudentPromptProfile(
      teacherId: widget.teacherId,
      courseKey: widget.courseKey,
      studentId: widget.studentId,
    );
    if (!mounted) {
      return;
    }
    setState(() => _lastSavedAt = refreshed?.updatedAt ?? refreshed?.createdAt);
    _showMessage(AppLocalizations.of(context)!.studentPromptSaved);
  }

  Future<void> _clear() async {
    _gradeLevelController.clear();
    _readingLevelController.clear();
    _languageController.clear();
    _interestsController.clear();
    _toneController.clear();
    _paceController.clear();
    _formatController.clear();
    _supportNotesController.clear();
    await _save();
  }

  bool _hasAnyValue() {
    return _gradeLevelController.text.trim().isNotEmpty ||
        _readingLevelController.text.trim().isNotEmpty ||
        _languageController.text.trim().isNotEmpty ||
        _interestsController.text.trim().isNotEmpty ||
        _toneController.text.trim().isNotEmpty ||
        _paceController.text.trim().isNotEmpty ||
        _formatController.text.trim().isNotEmpty ||
        _supportNotesController.text.trim().isNotEmpty;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatTime(DateTime time) {
    final year = time.year.toString().padLeft(4, '0');
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final helperText = _lastSavedAt == null
        ? l10n.studentPromptNotSaved
        : l10n.studentPromptLastSaved(_formatTime(_lastSavedAt!));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.studentPromptSectionTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.studentPromptSectionHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else ...[
              TextFormField(
                controller: _gradeLevelController,
                decoration: InputDecoration(
                  labelText: l10n.studentPromptGradeLabel,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _readingLevelController,
                decoration: InputDecoration(
                  labelText: l10n.studentPromptReadingLabel,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _languageController,
                decoration: InputDecoration(
                  labelText: l10n.studentPromptLanguageLabel,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _interestsController,
                decoration: InputDecoration(
                  labelText: l10n.studentPromptInterestsLabel,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _toneController,
                decoration: InputDecoration(
                  labelText: l10n.studentPromptToneLabel,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _paceController,
                decoration: InputDecoration(
                  labelText: l10n.studentPromptPaceLabel,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _formatController,
                decoration: InputDecoration(
                  labelText: l10n.studentPromptFormatLabel,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _supportNotesController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.studentPromptSupportLabel,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _loading ? null : _save,
                    child: Text(l10n.saveButton),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _loading ? null : _clear,
                    child: Text(l10n.clearButton),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      helperText,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StudentPromptPreviewSection extends StatelessWidget {
  const _StudentPromptPreviewSection({
    required this.teacherId,
    required this.courseKey,
    required this.studentId,
  });

  final int teacherId;
  final String? courseKey;
  final int? studentId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    return FutureBuilder<StudentPromptContext>(
      future: db.resolveStudentPromptContext(
        teacherId: teacherId,
        courseKey: courseKey,
        studentId: studentId,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.studentPromptPreviewError(
                  snapshot.error.toString(),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          );
        }
        final resolved = snapshot.data!;
        final profileText = resolved.profileText.trim();
        final preferenceText = resolved.preferencesText.trim();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.studentPromptPreviewTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.studentPromptPreviewProfileLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  profileText.isEmpty
                      ? l10n.studentPromptPreviewEmpty
                      : profileText,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.studentPromptPreviewPreferencesLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  preferenceText.isEmpty
                      ? l10n.studentPromptPreviewEmpty
                      : preferenceText,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PromptItem {
  _PromptItem({required this.name, required this.title});

  final String name;
  final String title;
}

class _PromptScope {
  _PromptScope({
    required this.label,
    required this.isSystem,
    this.courseKey,
    this.studentId,
  });

  _PromptScope.systemScope({
    required String label,
  })  : label = label,
        isSystem = true,
        courseKey = null,
        studentId = null;

  _PromptScope.courseScope({
    required String label,
    required String courseKey,
  })  : label = label,
        isSystem = false,
        courseKey = courseKey,
        studentId = null;

  final String label;
  final bool isSystem;
  final String? courseKey;
  final int? studentId;
}
