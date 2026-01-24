import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../db/app_database.dart';
import '../llm/llm_models.dart';
import '../llm/llm_providers.dart';
import '../models/tutor_action.dart';
import '../services/app_services.dart';
import '../state/settings_controller.dart';
import 'widgets/math_markdown_view.dart';

class ChatSessionPage extends StatefulWidget {
  const ChatSessionPage({
    super.key,
    required this.sessionId,
    required this.courseVersion,
    required this.node,
  });

  final int sessionId;
  final CourseVersion courseVersion;
  final CourseNode node;

  @override
  State<ChatSessionPage> createState() => _ChatSessionPageState();
}

class _ChatSessionPageState extends State<ChatSessionPage> {
  final _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  bool _summaryFailed = false;
  bool _closed = false;
  bool _loadingSession = true;
  TutorMode _mode = TutorMode.learn;
  String? _sessionModel;
  String? _sessionTitle;
  RequestHandle<dynamic>? _pending;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    final db = context.read<AppDatabase>();
    final session = await db.getSession(widget.sessionId);
    if (!mounted) {
      return;
    }
    if (session == null) {
      _closed = true;
      _summaryFailed = false;
      _sessionTitle = null;
    } else {
      _closed = false;
      _summaryFailed = session.status == 'summary_failed';
      _sessionTitle = session.title;
    }
    setState(() => _loadingSession = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final settings = context.watch<SettingsController>().settings;
    final envBaseUrl = Platform.environment['OPENAI_BASE_URL']?.trim() ?? '';
    final envModel = Platform.environment['OPENAI_MODEL']?.trim() ?? '';
    final providers = LlmProviders.defaultProviders(
      envBaseUrl: envBaseUrl,
      envModel: envModel,
    );
    final provider = (settings == null)
        ? providers.first
        : (LlmProviders.findById(providers, settings.providerId) ??
            LlmProviders.findByBaseUrl(providers, settings.baseUrl) ??
            providers.first);

    if (_loadingSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter):
            const _SendIntent(),
      },
      child: Actions(
        actions: {
          _SendIntent: CallbackAction<_SendIntent>(
            onInvoke: (_) {
              if (!_sending && !_closed) {
                _sendMessage();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                (_sessionTitle ?? '').trim().isNotEmpty
                    ? _sessionTitle!.trim()
                    : l10n.sessionTitle(widget.sessionId),
              ),
              actions: [
                if (!_closed)
                  IconButton(
                    tooltip: l10n.renameSessionButton,
                    icon: const Icon(Icons.edit),
                    onPressed: _sending ? null : _renameSession,
                  ),
              ],
            ),
            body: Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<ChatMessage>>(
                    stream: db.watchMessagesForSession(widget.sessionId),
                    builder: (context, snapshot) {
                      final messages = snapshot.data ?? [];
                      if (messages.isEmpty) {
                        return Center(child: Text(l10n.noMessagesYet));
                      }
                      final lastUserId = messages
                          .where((message) => message.role == 'user')
                          .map((message) => message.id)
                          .fold<int?>(
                            null,
                            (current, value) => current == null
                                ? value
                                : (value > current ? value : current),
                          );
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!_scrollController.hasClients) {
                          return;
                        }
                        _scrollController.jumpTo(
                          _scrollController.position.maxScrollExtent,
                        );
                      });
                      return ListView.builder(
                        controller: _scrollController,
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final label = _messageLabel(message, l10n);
                          final timeLabel = _formatTime(message.createdAt);
                          final theme = Theme.of(context);
                          final baseTextStyle = theme.textTheme.bodyMedium ??
                              const TextStyle(fontSize: 14);
                          const fontFallback = [
                            'Microsoft YaHei UI',
                            'Microsoft YaHei',
                            'Noto Sans CJK SC',
                            'Source Han Sans SC',
                            'PingFang SC',
                            'SimHei',
                          ];
                          final contentStyle = baseTextStyle.copyWith(
                            fontSize: (baseTextStyle.fontSize ?? 14) + 2,
                            height: 1.55,
                            fontFamily: 'Microsoft YaHei UI',
                            fontFamilyFallback: fontFallback,
                          );
                          final labelStyle = baseTextStyle.copyWith(
                            fontFamily: 'Microsoft YaHei UI',
                            fontFamilyFallback: fontFallback,
                          );
                          return ListTile(
                            title: Text(
                              '$label - $timeLabel',
                              style: labelStyle,
                            ),
                            subtitle: message.role == 'assistant'
                                ? MathMarkdownView(
                                    key: ValueKey('msg_${message.id}'),
                                    content: message.content,
                                    textStyle: contentStyle,
                                  )
                                : SelectableText(
                                    message.content,
                                    style: contentStyle,
                                  ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: _buildMessageActions(
                                message,
                                lastUserId,
                                l10n,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (_summaryFailed)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(l10n.summaryFailedRetry),
                        ),
                        TextButton(
                          onPressed: _showSummaryErrorDialog,
                          child: Text(l10n.detailsButton),
                        ),
                        ElevatedButton(
                          onPressed: _sending ? null : _requestSummary,
                          child: Text(l10n.retryButton),
                        ),
                      ],
                    ),
                  ),
                if (_sending) const LinearProgressIndicator(minHeight: 2),
                if (!_closed)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('chat_input'),
                            controller: _inputController,
                            focusNode: _inputFocus,
                            maxLines: 3,
                            minLines: 1,
                            enabled: !_sending,
                            decoration: InputDecoration(
                              labelText: l10n.chatInputLabel,
                              hintText: l10n.chatInputHint,
                              filled: true,
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: const Key('chat_send_button'),
                          onPressed: _sending ? _cancelRequest : _sendMessage,
                          icon: Icon(_sending ? Icons.stop : Icons.send),
                          tooltip:
                              _sending ? l10n.stopTooltip : l10n.sendTooltip,
                        ),
                      ],
                    ),
                  ),
                if (!_closed)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 260,
                          child: _buildModelSelector(
                            db: db,
                            currentModel: settings?.model ?? '',
                            provider: provider,
                            l10n: l10n,
                          ),
                        ),
                        _modeChip(TutorMode.learn, l10n),
                        _modeChip(TutorMode.review, l10n),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          key: const Key('summary_button'),
                          onPressed: _sending ? null : _requestSummary,
                          child: Text(l10n.summaryButton),
                        ),
                        TextButton(
                          key: const Key('exit_button'),
                          onPressed: _sending ? null : _exitSession,
                          child: Text(l10n.exitButton),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMessageActions(
    ChatMessage message,
    int? lastUserId,
    AppLocalizations l10n,
  ) {
    final actions = <Widget>[
      IconButton(
        tooltip: l10n.copyTooltip,
        icon: const Icon(Icons.copy),
        onPressed: () => _copyMessage(message, l10n),
      ),
    ];

    if (message.role == 'user' &&
        lastUserId != null &&
        message.id == lastUserId) {
      actions.add(
        IconButton(
          tooltip: l10n.editTooltip,
          icon: const Icon(Icons.edit),
          onPressed: _sending ? null : () => _editMessage(message, l10n),
        ),
      );
    } else if (_isRefreshableMessage(message)) {
      actions.add(
        IconButton(
          tooltip: l10n.refreshTooltip,
          icon: const Icon(Icons.refresh),
          onPressed: _sending ? null : () => _refreshAnswer(message, l10n),
        ),
      );
    }

    return actions;
  }

  Widget _modeChip(TutorMode mode, AppLocalizations l10n) {
    return ChoiceChip(
      label: Text(mode.label(l10n)),
      selected: _mode == mode,
      onSelected: _sending
          ? null
          : (selected) {
              if (selected) {
                setState(() => _mode = mode);
              }
            },
    );
  }

  Future<void> _sendMessage() async {
    final l10n = AppLocalizations.of(context)!;
    if (_inputController.text.trim().isEmpty) {
      await _showErrorDialog(
        title: l10n.messageRequiredTitle,
        message: l10n.messageRequiredBody,
      );
      return;
    }
    setState(() => _sending = true);
    final sessionService = context.read<AppServices>().sessionService;
    final modelOverride = _resolveModelOverride();
    try {
      final llmHandle = await sessionService.startTutorAction(
        sessionId: widget.sessionId,
        mode: _mode.promptName,
        studentInput: _inputController.text,
        courseVersion: widget.courseVersion,
        node: widget.node,
        modelOverride: modelOverride,
      );
      _pending = llmHandle;
      await llmHandle.future;
      _inputController.clear();
      _inputFocus.requestFocus();
    } catch (e) {
      await _showErrorDialog(
        title: l10n.requestFailedTitle,
        message: e.toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
      _pending = null;
    }
  }

  Future<void> _requestSummary() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _sending = true);
    final sessionService = context.read<AppServices>().sessionService;
    final modelOverride = _resolveModelOverride();
    try {
      final summarizeHandle = await sessionService.startSummarize(
        sessionId: widget.sessionId,
        courseVersion: widget.courseVersion,
        node: widget.node,
        modelOverride: modelOverride,
      );
      _pending = summarizeHandle;
      final result = await summarizeHandle.future;
      _summaryFailed = !result.success;
      if (result.success) {
        if (result.lit != null && result.masterLevel != null) {
          _showMessage(
            l10n.summaryUpdatedStatus('${result.lit}', result.masterLevel!),
          );
        } else if (result.lit != null) {
          _showMessage(l10n.summaryUpdatedLit('${result.lit}'));
        } else {
          _showMessage(l10n.summarySavedUnparsed);
        }
      } else {
        await _showSummaryErrorDialog(
          messageOverride: result.message,
        );
      }
    } catch (e) {
      await _showSummaryErrorDialog(
        messageOverride: e.toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
      _pending = null;
    }
  }

  Future<void> _exitSession() async {
    final sessionService = context.read<AppServices>().sessionService;
    await sessionService.closeSession(widget.sessionId);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _cancelRequest() {
    _pending?.cancel();
    setState(() => _sending = false);
  }

  Future<void> _copyMessage(
    ChatMessage message,
    AppLocalizations l10n,
  ) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    _showMessage(l10n.copySuccess);
  }

  bool _isRefreshableMessage(ChatMessage message) {
    if (message.role != 'assistant') {
      return false;
    }
    final action = message.action;
    if (action == null) {
      return false;
    }
    return action == 'learn' ||
        action == 'review' ||
        action == 'summary';
  }

  Future<void> _refreshAnswer(
    ChatMessage message,
    AppLocalizations l10n,
  ) async {
    final action = message.action;
    if (action == null) {
      return;
    }
    if (action == 'summary') {
      await _requestSummary();
      return;
    }
    setState(() => _sending = true);
    final sessionService = context.read<AppServices>().sessionService;
    final modelOverride = _resolveModelOverride();
    try {
      final llmHandle = await sessionService.startTutorAction(
        sessionId: widget.sessionId,
        mode: action,
        studentInput: '',
        courseVersion: widget.courseVersion,
        node: widget.node,
        modelOverride: modelOverride,
      );
      _pending = llmHandle;
      await llmHandle.future;
    } catch (e) {
      await _showErrorDialog(
        title: l10n.refreshFailedTitle,
        message: e.toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
      _pending = null;
    }
  }

  Future<void> _editMessage(
    ChatMessage message,
    AppLocalizations l10n,
  ) async {
    final controller = TextEditingController(text: message.content);
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.editTooltip),
        content: TextField(
          controller: controller,
          maxLines: 6,
          minLines: 1,
          decoration: InputDecoration(labelText: l10n.chatInputLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.sendTooltip),
          ),
        ],
      ),
    );
    if (updated == null || updated.trim().isEmpty) {
      return;
    }
    setState(() => _sending = true);
    final db = context.read<AppDatabase>();
    final sessionService = context.read<AppServices>().sessionService;
    final modelOverride = _resolveModelOverride();
    try {
      await db.deleteMessagesFrom(
        sessionId: widget.sessionId,
        fromMessageId: message.id,
      );
      final mode = message.action ?? _mode.promptName;
      final llmHandle = await sessionService.startTutorAction(
        sessionId: widget.sessionId,
        mode: mode,
        studentInput: updated.trim(),
        courseVersion: widget.courseVersion,
        node: widget.node,
        modelOverride: modelOverride,
      );
      _pending = llmHandle;
      await llmHandle.future;
    } catch (e) {
      await _showErrorDialog(
        title: l10n.editFailedTitle,
        message: e.toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
      _pending = null;
    }
  }

  Future<void> _renameSession() async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final session = await db.getSession(widget.sessionId);
    if (session == null) {
      return;
    }
    final controller = TextEditingController(text: session.title ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameSessionTitle),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: l10n.sessionNameLabel),
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
    if (updated == null) {
      return;
    }
    await db.renameSession(sessionId: session.id, title: updated);
    if (!mounted) {
      return;
    }
    setState(() {
      final cleaned = updated.trim();
      _sessionTitle = cleaned.isEmpty ? null : cleaned;
    });
  }

  Future<void> _showSummaryErrorDialog({String? messageOverride}) async {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final session = await db.getSession(widget.sessionId);
    final raw = session?.summaryRawResponse ?? '';
    final progress = session == null
        ? null
        : await db.getProgress(
            studentId: session.studentId,
            courseVersionId: widget.courseVersion.id,
            kpKey: widget.node.kpKey,
          );
    final progressRaw = progress?.summaryRawResponse ?? '';
    final llmCall = await db.getLatestLlmCallForSession(
      sessionId: widget.sessionId,
      promptName: 'summarize',
    );
    final parseError = llmCall?.parseError;
    final responseText = llmCall?.responseText;
    final details = responseText?.isNotEmpty == true
        ? responseText
        : (raw.isNotEmpty
            ? raw
            : (progressRaw.isNotEmpty ? progressRaw : null));
    final message = messageOverride ?? parseError ?? l10n.summaryFailedMessage;
    await _showErrorDialog(
      title: l10n.summaryFailedTitle,
      message: message,
      details: details,
    );
  }

  Future<void> _showErrorDialog({
    required String title,
    required String message,
    String? details,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.messageLabel),
                SelectableText(message),
                if ((details ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(l10n.detailsLabel),
                  SelectableText(details!),
                ],
              ],
            ),
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

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _resolveModelOverride() {
    final settings = context.read<SettingsController>().settings;
    final selected = _sessionModel?.trim();
    if (selected != null && selected.isNotEmpty) {
      return selected;
    }
    final fallback = settings?.model.trim();
    if (fallback == null || fallback.isEmpty) {
      return null;
    }
    return fallback;
  }

  Widget _buildModelSelector({
    required AppDatabase db,
    required String currentModel,
    required LlmProvider provider,
    required AppLocalizations l10n,
  }) {
    return StreamBuilder<List<ApiConfig>>(
      stream: db.watchApiConfigs(),
      builder: (context, snapshot) {
        final configs = snapshot.data ?? [];
        final models = <String>{
          ...provider.models.map((model) => model.trim()).where(
                (model) => model.isNotEmpty,
              ),
          if (currentModel.trim().isNotEmpty) currentModel.trim(),
          ...configs
              .where(
                (config) =>
                    _normalizeBaseUrl(config.baseUrl) ==
                    _normalizeBaseUrl(provider.baseUrl),
              )
              .map((config) => config.model.trim())
              .where((m) => m.isNotEmpty),
        }.toList()
          ..sort();
        final selected = (_sessionModel?.trim().isNotEmpty == true)
            ? _sessionModel!.trim()
            : currentModel.trim();
        final value = models.contains(selected)
            ? selected
            : (models.isNotEmpty ? models.first : selected);
        if ((_sessionModel == null ||
                !_sessionModel!.trim().isNotEmpty ||
                !models.contains(_sessionModel!.trim())) &&
            value.isNotEmpty) {
          _sessionModel = value;
        }
        return DropdownButtonFormField<String>(
          key: ValueKey(value),
          initialValue: value.isNotEmpty ? value : null,
          decoration: InputDecoration(
            labelText: l10n.modelLabel,
            border: const OutlineInputBorder(),
          ),
          items: models
              .map(
                (model) => DropdownMenuItem(
                  value: model,
                  child: Text(model),
                ),
              )
              .toList(),
          onChanged: _sending
              ? null
              : (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _sessionModel = value);
                },
        );
      },
    );
  }

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  String _messageLabel(ChatMessage message, AppLocalizations l10n) {
    if (message.role == 'user') {
      return l10n.chatLabelStudent;
    }
    if (message.action == 'summary') {
      return l10n.chatLabelSummary;
    }
    final actionLabel = _actionLabel(message.action, l10n);
    return l10n.chatLabelTutor(actionLabel);
  }

  String _actionLabel(String? action, AppLocalizations l10n) {
    switch (action) {
      case 'learn':
        return l10n.promptLearn;
      case 'review':
        return l10n.promptReview;
      case 'summary':
        return l10n.promptSummarize;
      default:
        return l10n.tutorReplyLabel;
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}
