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
    final db = context.read<AppDatabase>();
    final courses = await db.watchCourseVersions(widget.teacherId).first;
    final scopes = <_PromptScope>[];
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
        name: 'learn',
        title: l10n.promptLearn,
      ),
      _PromptItem(
        name: 'review',
        title: l10n.promptReview,
      ),
      _PromptItem(
        name: 'summarize',
        title: l10n.promptSummarize,
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
              value: _selectedScope,
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
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
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

  Future<void> _openEditor(
    BuildContext context,
    PromptRepository promptRepo,
    _PromptItem item,
    String? currentContent,
    {String? courseKey,
    int? studentId}
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final defaultContent = await promptRepo.loadAppendPrompt(
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
    if (context.mounted) {
      _showMessage(context, l10n.promptSaved);
    }
  }

  Future<void> _showCurrentPreview(
    BuildContext context,
    PromptRepository promptRepo,
    String promptName, {
    String? courseKey,
    int? studentId,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final preview = await promptRepo.buildPromptPreview(
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
    String? courseKey,
    int? studentId,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final current = await promptRepo.buildPromptPreview(
      name: promptName,
      teacherId: widget.teacherId,
      courseKey: courseKey,
      studentId: studentId,
      includeSystem: false,
    );
    final historical = await promptRepo.buildPromptPreview(
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
    final info = _variableDescriptions();
    final allowed = _validator.allowedVariables(promptName).toList()..sort();
    return allowed.map((variable) {
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
      'student_summary':
          'Saved summary for this student/course/kp (falls back to the session summary).',
    };
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
    this.courseKey,
    this.studentId,
  });

  _PromptScope.courseScope({
    required String label,
    required String courseKey,
  })  : label = label,
        courseKey = courseKey,
        studentId = null;

  final String label;
  final String? courseKey;
  final int? studentId;
}
