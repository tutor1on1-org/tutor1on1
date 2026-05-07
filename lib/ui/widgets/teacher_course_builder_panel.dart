import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../services/app_services.dart';
import '../../services/course_builder_service.dart';

class TeacherCourseBuilderPanel extends StatefulWidget {
  const TeacherCourseBuilderPanel({
    super.key,
    required this.courseVersion,
    required this.kpKey,
    required this.kpTitle,
  });

  final CourseVersion courseVersion;
  final String kpKey;
  final String kpTitle;

  @override
  State<TeacherCourseBuilderPanel> createState() =>
      _TeacherCourseBuilderPanelState();
}

class _TeacherCourseBuilderPanelState extends State<TeacherCourseBuilderPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _messagesController = ScrollController();
  final List<_BuilderMessage> _messages = <_BuilderMessage>[];
  CourseBuilderMode _mode = CourseBuilderMode.content;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _inputController.dispose();
    _messagesController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TeacherCourseBuilderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseVersion.id != widget.courseVersion.id ||
        oldWidget.kpKey != widget.kpKey) {
      _messages.clear();
      _inputController.clear();
      _error = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Course Builder',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                SegmentedButton<CourseBuilderMode>(
                  segments: const [
                    ButtonSegment(
                      value: CourseBuilderMode.content,
                      icon: Icon(Icons.article_outlined),
                      label: Text('Content'),
                    ),
                    ButtonSegment(
                      value: CourseBuilderMode.question,
                      icon: Icon(Icons.quiz_outlined),
                      label: Text('Question'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _sending
                      ? null
                      : (selected) {
                          setState(() {
                            _mode = selected.first;
                            _error = null;
                          });
                        },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _messages.isEmpty
                    ? const Center(
                        child: Text('Ask AI to draft content or a question.'),
                      )
                    : ListView.builder(
                        controller: _messagesController,
                        padding: const EdgeInsets.all(8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isAssistant = message.role == _MessageRole.ai;
                          return Align(
                            alignment: isAssistant
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(message.text),
                                      if (isAssistant) ...[
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: _sending
                                                ? null
                                                : () => _openEditDialog(
                                                      message,
                                                    ),
                                            icon: const Icon(Icons.edit),
                                            label: const Text('Edit'),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                _error!,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    enabled: !_sending,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Teacher request',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final request = _inputController.text.trim();
    if (request.isEmpty || _sending) {
      return;
    }
    final service = context.read<AppServices>().courseBuilderService;
    setState(() {
      _sending = true;
      _error = null;
      _messages.add(
        _BuilderMessage(
          role: _MessageRole.teacher,
          mode: _mode,
          text: request,
        ),
      );
      _inputController.clear();
    });
    _scrollToBottomSoon();
    final history = _buildConversationHistory();
    try {
      final response = await service.generate(
        courseVersion: widget.courseVersion,
        kpKey: widget.kpKey,
        kpTitle: widget.kpTitle,
        mode: _mode,
        conversationHistory: history,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          _BuilderMessage(
            role: _MessageRole.ai,
            mode: _mode,
            text: response,
          ),
        );
      });
      _scrollToBottomSoon();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Course builder failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  String _buildConversationHistory() {
    return _messages.map((message) {
      final role = message.role == _MessageRole.teacher ? 'Teacher' : 'AI';
      return '$role: ${message.text.trim()}';
    }).join('\n\n');
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesController.hasClients) {
        return;
      }
      _messagesController.animateTo(
        _messagesController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openEditDialog(_BuilderMessage message) async {
    final service = context.read<AppServices>().courseBuilderService;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _CourseBuilderDiffDialog(
        service: service,
        courseVersion: widget.courseVersion,
        kpKey: widget.kpKey,
        mode: message.mode,
        incomingText: message.text,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course content saved.')),
      );
    }
  }
}

class _CourseBuilderDiffDialog extends StatefulWidget {
  const _CourseBuilderDiffDialog({
    required this.service,
    required this.courseVersion,
    required this.kpKey,
    required this.mode,
    required this.incomingText,
  });

  final CourseBuilderService service;
  final CourseVersion courseVersion;
  final String kpKey;
  final CourseBuilderMode mode;
  final String incomingText;

  @override
  State<_CourseBuilderDiffDialog> createState() =>
      _CourseBuilderDiffDialogState();
}

class _CourseBuilderDiffDialogState extends State<_CourseBuilderDiffDialog> {
  final TextEditingController _rightController = TextEditingController();
  CourseBuilderWriteMode _writeMode = CourseBuilderWriteMode.add;
  String _questionLevel = 'medium';
  String _currentText = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCurrentText();
  }

  @override
  void dispose() {
    _rightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.mode == CourseBuilderMode.content
            ? 'Edit course content'
            : 'Edit question bank',
      ),
      content: SizedBox(
        width: 920,
        height: 560,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SegmentedButton<CourseBuilderWriteMode>(
                        segments: const [
                          ButtonSegment(
                            value: CourseBuilderWriteMode.add,
                            label: Text('Add'),
                          ),
                          ButtonSegment(
                            value: CourseBuilderWriteMode.replace,
                            label: Text('Replace'),
                          ),
                        ],
                        selected: {_writeMode},
                        onSelectionChanged: _saving
                            ? null
                            : (selected) {
                                setState(() {
                                  _writeMode = selected.first;
                                  _refreshPreview();
                                });
                              },
                      ),
                      if (widget.mode == CourseBuilderMode.question)
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'easy',
                              label: Text('Easy'),
                            ),
                            ButtonSegment(
                              value: 'medium',
                              label: Text('Medium'),
                            ),
                            ButtonSegment(
                              value: 'hard',
                              label: Text('Hard'),
                            ),
                          ],
                          selected: {_questionLevel},
                          onSelectionChanged: _saving
                              ? null
                              : (selected) {
                                  setState(() {
                                    _questionLevel = selected.first;
                                  });
                                  _loadCurrentText();
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Current',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: SelectableText(_currentText),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _rightController,
                            enabled: !_saving,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              labelText: 'New',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading || _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _loadCurrentText() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final current = widget.mode == CourseBuilderMode.content
          ? await widget.service.readLessonContent(
              courseVersion: widget.courseVersion,
              kpKey: widget.kpKey,
            )
          : await widget.service.readQuestionText(
              courseVersion: widget.courseVersion,
              kpKey: widget.kpKey,
              level: _questionLevel,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _currentText = current;
        _loading = false;
        _refreshPreview();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load current text: $error';
        _loading = false;
      });
    }
  }

  void _refreshPreview() {
    _rightController.text = widget.service.buildPreviewText(
      currentText: _currentText,
      incomingText: widget.incomingText,
      writeMode: _writeMode,
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.mode == CourseBuilderMode.content) {
        await widget.service.saveLessonContent(
          courseVersion: widget.courseVersion,
          kpKey: widget.kpKey,
          text: _rightController.text,
        );
      } else {
        await widget.service.saveQuestionText(
          courseVersion: widget.courseVersion,
          kpKey: widget.kpKey,
          level: _questionLevel,
          text: _rightController.text,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = 'Failed to save: $error';
      });
    }
  }
}

enum _MessageRole {
  teacher,
  ai,
}

class _BuilderMessage {
  const _BuilderMessage({
    required this.role,
    required this.mode,
    required this.text,
  });

  final _MessageRole role;
  final CourseBuilderMode mode;
  final String text;
}
