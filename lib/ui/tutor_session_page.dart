import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:family_teacher/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../db/app_database.dart';
import '../llm/llm_models.dart';
import '../llm/llm_providers.dart';
import '../models/tutor_action.dart';
import '../models/tutor_contract.dart';
import '../services/app_services.dart';
import '../services/stt_service.dart';
import '../services/tts_chunker.dart';
import '../services/tts_service.dart';
import '../services/tts_text_sanitizer.dart';
import '../state/auth_controller.dart';
import '../state/settings_controller.dart';
import 'app_close_button.dart';
import 'session_progress_display.dart';
import 'tutor_turn_logic.dart';
import 'widgets/math_markdown_view.dart';

class ChatSessionPage extends StatefulWidget {
  const ChatSessionPage({
    super.key,
    required this.sessionId,
    required this.courseVersion,
    required this.node,
    this.readOnly = false,
  });

  final int sessionId;
  final CourseVersion courseVersion;
  final CourseNode node;
  final bool readOnly;

  @override
  State<ChatSessionPage> createState() => _ChatSessionPageState();
}

class _ChatSessionPageState extends State<ChatSessionPage>
    with WidgetsBindingObserver {
  late AppServices _services;
  final _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  bool _closed = false;
  bool _loadingSession = true;
  bool _autoStartAttempted = false;
  TutorMode _mode = TutorMode.learn;
  TutorTurnStep _step = TutorTurnStep.newTurn;
  TutorHelpBias _helpBias = TutorHelpBias.unchanged;
  TutorFinishedAction? _recommendedAction;
  String? _sessionModel;
  String? _sessionTitle;
  RequestHandle<dynamic>? _pending;
  bool _ttsEnabled = false;
  final TtsChunker _ttsChunker = TtsChunker();
  final TtsTextSanitizer _ttsSanitizer = TtsTextSanitizer();
  final StringBuffer _ttsPendingBuffer = StringBuffer();
  final StringBuffer _ttsDisplayBuffer = StringBuffer();
  final StringBuffer _ttsRawBuffer = StringBuffer();
  final List<_TtsQueuedChunk> _ttsChunkQueue = [];
  Timer? _ttsGateTimer;
  Timer? _ttsDisplayFlushTimer;
  Timer? _ttsWordTimer;
  bool _ttsGateOpen = false;
  bool _ttsGateStarted = false;
  int _ttsInitialDelayMs = 60000;
  int _ttsTextLeadMs = 1000;
  int? _assistantMessageId;
  int _ttsOutstandingChunks = 0;
  bool _ttsLlmCompleted = false;
  bool _ttsFlushPending = false;
  List<String> _ttsStreamTokens = const [];
  int _ttsStreamIndex = 0;
  DateTime? _ttsStreamStart;
  int _ttsStreamDurationMs = 0;
  bool _ttsStreamingActive = false;
  bool _ttsPlaybackActive = false;
  bool _ttsChunkInFlight = false;
  bool _ttsStreamPaused = false;
  DateTime? _ttsStreamPausedAt;
  bool _ttsActiveChunkDisplayed = false;
  bool _ttsPreparingFirstChunk = false;
  bool _ttsHardStopped = false;
  Timer? _ttsPrefetchTimer;
  bool _ttsPrefetchWindowReached = false;
  bool _ttsPrefetchInFlight = false;
  TtsPrefetchedAudio? _ttsPrefetchedAudio;
  _TtsQueuedChunk? _ttsPrefetchedChunk;
  String? _ttsAudioDir;
  bool _sttRecording = false;
  bool _sttTranscribing = false;
  bool _sttPressActive = false;
  bool _sttCancelHover = false;
  String? _pendingSttAudioPath;
  bool _applyingTranscription = false;
  int _inputLineCount = 1;
  final GlobalKey _sttCancelKey = GlobalKey();
  final LayerLink _sttButtonLink = LayerLink();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inputController.addListener(_handleInputChanged);
    _loadSession();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = context.read<AppServices>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ttsEnabled) {
      _services.ttsService.stop(sessionId: widget.sessionId);
    }
    _services.ttsService.stopReplay(sessionId: widget.sessionId);
    _services.sttService.cancelRecording(sessionId: widget.sessionId);
    _ttsGateTimer?.cancel();
    _ttsDisplayFlushTimer?.cancel();
    _ttsWordTimer?.cancel();
    _ttsPrefetchTimer?.cancel();
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _handleSttAppPaused();
    }
  }

  Future<void> _handleSttAppPaused() async {
    if (!_sttPressActive && !_sttRecording && !_sttTranscribing) {
      return;
    }
    _sttPressActive = false;
    _sttRecording = false;
    _sttTranscribing = false;
    _sttCancelHover = false;
    _pendingSttAudioPath = null;
    await context
        .read<AppServices>()
        .sttService
        .cancelRecording(sessionId: widget.sessionId);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadSession() async {
    final db = context.read<AppDatabase>();
    final session = await db.getSession(widget.sessionId);
    if (!mounted) {
      return;
    }
    if (session == null) {
      _closed = true;
      _sessionTitle = null;
    } else {
      _closed = false;
      _sessionTitle = session.title;
    }
    setState(() => _loadingSession = false);
    await _applyPersistedSessionControl(db);
    await _maybeAutoStart(db);
  }

  Future<void> _maybeAutoStart(AppDatabase db) async {
    if (_autoStartAttempted || _sending || _closed || widget.readOnly) {
      return;
    }
    final messages = await db.getMessagesForSession(widget.sessionId);
    if (!mounted || messages.isNotEmpty) {
      return;
    }
    _autoStartAttempted = true;
    await _sendMessage(allowEmpty: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<AppDatabase>();
    final settings = context.watch<SettingsController>().settings;
    final currentUser = context.watch<AuthController>().currentUser;
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
    final baseUrlLower = settings?.baseUrl.toLowerCase() ?? '';
    final isAudioProvider = settings != null &&
        (provider.id == 'openai' ||
            provider.id == 'siliconflow' ||
            baseUrlLower.contains('openai.com') ||
            baseUrlLower.contains('siliconflow'));
    final ttsModel = settings?.ttsModel;
    final sttModel = settings?.sttModel;
    final ttsSupported =
        isAudioProvider && ttsModel != null && ttsModel.trim().isNotEmpty;
    final sttSupported =
        isAudioProvider && sttModel != null && sttModel.trim().isNotEmpty;
    final livePlaybackActive =
        _ttsPlaybackActive || _ttsStreamPaused || _ttsChunkInFlight;
    final canInteract = !_closed && !widget.readOnly;
    final sttBusy = _sttPressActive || _sttRecording || _sttTranscribing;
    final enterToSend = !Platform.isAndroid && (settings?.enterToSend ?? true);
    final compactControls = Platform.isAndroid;
    final footerProgressBadge = currentUser?.role == 'student'
        ? _SessionFooterProgressBadge(
            db: db,
            studentId: currentUser!.id,
            courseVersionId: widget.courseVersion.id,
            kpKey: widget.node.kpKey,
          )
        : null;
    final shortcutMap = <ShortcutActivator, Intent>{
      const SingleActivator(
        LogicalKeyboardKey.enter,
        control: true,
      ): const _SendIntent(),
      const SingleActivator(
        LogicalKeyboardKey.enter,
        meta: true,
      ): const _SendIntent(),
    };
    if (enterToSend) {
      shortcutMap[const SingleActivator(LogicalKeyboardKey.enter)] =
          const _SendIntent();
    }
    if (!ttsSupported && _ttsEnabled) {
      _ttsEnabled = false;
    }

    if (_loadingSession) {
      return Scaffold(
        appBar: AppBar(
          actions: buildAppBarActionsWithClose(context),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Shortcuts(
      shortcuts: shortcutMap,
      child: Actions(
        actions: {
          _SendIntent: CallbackAction<_SendIntent>(
            onInvoke: (_) {
              if (!_sending && canInteract && !sttBusy) {
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
              actions: buildAppBarActionsWithClose(
                context,
                actions: [
                  if (!_closed && !widget.readOnly)
                    IconButton(
                      tooltip: l10n.renameSessionButton,
                      icon: const Icon(Icons.edit),
                      onPressed: _sending ? null : _renameSession,
                    ),
                ],
              ),
            ),
            body: Stack(
              children: [
                Column(
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
                            _scrollToBottom(animated: false);
                          });
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 520;
                              return ListView.builder(
                                controller: _scrollController,
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final message = messages[index];
                                  final label = _messageLabel(message, l10n);
                                  final timeLabel =
                                      _formatTime(message.createdAt);
                                  final theme = Theme.of(context);
                                  final baseTextStyle =
                                      theme.textTheme.bodyMedium ??
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
                                    fontSize:
                                        (baseTextStyle.fontSize ?? 14) + 2,
                                    height: 1.55,
                                    fontFamily: 'Microsoft YaHei UI',
                                    fontFamilyFallback: fontFallback,
                                  );
                                  final labelStyle = baseTextStyle.copyWith(
                                    fontFamily: 'Microsoft YaHei UI',
                                    fontFamilyFallback: fontFallback,
                                  );
                                  final ttsService =
                                      context.read<AppServices>().ttsService;
                                  final ttsAudioDir =
                                      settings?.ttsAudioPath?.trim() ?? '';
                                  final logDir =
                                      (settings?.logDirectory ?? '').trim();
                                  final sttAudioDir = logDir.isNotEmpty
                                      ? logDir
                                      : () {
                                          final llmLog =
                                              (settings?.llmLogPath ?? '')
                                                  .trim();
                                          if (llmLog.isNotEmpty) {
                                            return p.dirname(llmLog);
                                          }
                                          final ttsLog =
                                              (settings?.ttsLogPath ?? '')
                                                  .trim();
                                          if (ttsLog.isNotEmpty) {
                                            return p.dirname(ttsLog);
                                          }
                                          return '';
                                        }();
                                  String? audioPath;
                                  if (message.role == 'assistant' &&
                                      ttsAudioDir.isNotEmpty) {
                                    audioPath =
                                        TtsService.buildMessageAudioPath(
                                      baseDir: ttsAudioDir,
                                      messageId: message.id,
                                    );
                                  } else if (message.role == 'user' &&
                                      sttAudioDir.isNotEmpty) {
                                    audioPath =
                                        SttService.buildMessageAudioPath(
                                      baseDir: sttAudioDir,
                                      messageId: message.id,
                                    );
                                  }
                                  final hasAudio = audioPath != null &&
                                      File(audioPath).existsSync() &&
                                      File(audioPath).lengthSync() > 0;
                                  return StreamBuilder<TtsPlaybackState>(
                                    stream: ttsService.playbackStream,
                                    builder: (context, playbackSnapshot) {
                                      final playback = playbackSnapshot.data;
                                      final isPlaying =
                                          playback?.messageId == message.id &&
                                              playback?.isPlaying == true;
                                      final isPaused =
                                          playback?.messageId == message.id &&
                                              playback?.isPaused == true;
                                      final duration = playback?.duration;
                                      final position =
                                          playback?.position ?? Duration.zero;
                                      final progressValue = (duration == null ||
                                              duration.inMilliseconds <= 0)
                                          ? null
                                          : (position.inMilliseconds /
                                                  duration.inMilliseconds)
                                              .clamp(0.0, 1.0);
                                      final showProgress =
                                          playback?.messageId == message.id &&
                                              duration != null &&
                                              duration.inMilliseconds > 0;
                                      final contentWidget = message.role ==
                                              'assistant'
                                          ? MathMarkdownView(
                                              key:
                                                  ValueKey('msg_${message.id}'),
                                              content: message.content,
                                              textStyle: contentStyle,
                                            )
                                          : SelectableText(
                                              message.content,
                                              style: contentStyle,
                                            );
                                      final messageBody = showProgress
                                          ? Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                contentWidget,
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 6),
                                                  child:
                                                      LinearProgressIndicator(
                                                    value: progressValue,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : contentWidget;
                                      final actions = _buildMessageActions(
                                        message,
                                        lastUserId,
                                        l10n,
                                        hasAudio: hasAudio,
                                        audioPath: audioPath,
                                        isPlaying: isPlaying,
                                        isPaused: isPaused,
                                      );
                                      final actionStrip = Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: actions,
                                      );
                                      final messageSubtitle =
                                          isNarrow && actions.isNotEmpty
                                              ? Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    messageBody,
                                                    const SizedBox(height: 8),
                                                    Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: actionStrip,
                                                    ),
                                                  ],
                                                )
                                              : messageBody;
                                      return ListTile(
                                        title: Text(
                                          '$label - $timeLabel',
                                          style: labelStyle,
                                        ),
                                        subtitle: messageSubtitle,
                                        trailing: isNarrow || actions.isEmpty
                                            ? null
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: actions,
                                              ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    if (canInteract)
                      StreamBuilder<List<ChatMessage>>(
                        stream: db.watchMessagesForSession(widget.sessionId),
                        builder: (context, snapshot) {
                          final preview = _buildErrorBookPreview(
                            snapshot.data ?? const <ChatMessage>[],
                          );
                          if (preview.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  const Text(
                                    'Error Book Focus:',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  ...preview.map(
                                    (item) => Tooltip(
                                      message: item.lastNote,
                                      child: Chip(
                                        label: Text(
                                          '${item.mistakeTag} x${item.count}',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    if (_sending) const LinearProgressIndicator(minHeight: 2),
                    if (canInteract)
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
                                enabled: !_sending && !_sttTranscribing,
                                decoration: InputDecoration(
                                  labelText: l10n.chatInputLabel,
                                  hintText: enterToSend
                                      ? l10n.chatInputHintEnterToSend
                                      : l10n.chatInputHintCtrlEnterToSend,
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
                            Tooltip(
                              message: sttSupported
                                  ? (_sttTranscribing
                                      ? l10n.sttTranscribingLabel
                                      : (_sttRecording
                                          ? l10n.sttStopTooltip
                                          : l10n.sttRecordTooltip))
                                  : l10n.sttRequiresOpenAi,
                              child: Listener(
                                key: const Key('chat_mic_button'),
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (_sending ||
                                        _sttTranscribing ||
                                        !sttSupported)
                                    ? null
                                    : _handleSttPointerDown,
                                onPointerMove: (_sttPressActive &&
                                        !_sttTranscribing &&
                                        sttSupported)
                                    ? _handleSttPointerMove
                                    : null,
                                onPointerUp: (_sttPressActive &&
                                        !_sttTranscribing &&
                                        sttSupported)
                                    ? _handleSttPointerUp
                                    : null,
                                onPointerCancel: (_sttPressActive &&
                                        !_sttTranscribing &&
                                        sttSupported)
                                    ? _handleSttPointerCancel
                                    : null,
                                child: CompositedTransformTarget(
                                  link: _sttButtonLink,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: _sttRecording
                                          ? Theme.of(context)
                                              .colorScheme
                                              .errorContainer
                                          : Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: _sttTranscribing
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            Icons.mic,
                                            color: _sttRecording
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .onErrorContainer
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              key: const Key('chat_send_button'),
                              onPressed: _sending
                                  ? _cancelRequest
                                  : (sttBusy ? null : _sendMessage),
                              icon: Icon(_sending ? Icons.stop : Icons.send),
                              tooltip: _sending
                                  ? l10n.stopTooltip
                                  : l10n.sendTooltip,
                            ),
                          ],
                        ),
                      ),
                    if (canInteract)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: compactControls
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (footerProgressBadge != null) ...[
                                        footerProgressBadge,
                                        const SizedBox(width: 12),
                                      ],
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: [
                                              _buildCompactModelSelector(
                                                db: db,
                                                currentModel:
                                                    settings?.model ?? '',
                                                provider: provider,
                                                l10n: l10n,
                                              ),
                                              const SizedBox(width: 8),
                                              _actionButton(
                                                key: const Key('learn_button'),
                                                label: l10n.promptLearn,
                                                selected: _isModeRecommended(
                                                  TutorMode.learn,
                                                ),
                                                onPressed: _sending
                                                    ? null
                                                    : _startNewLearnTurn,
                                                compact: true,
                                              ),
                                              const SizedBox(width: 8),
                                              _actionButton(
                                                key: const Key(
                                                  'review_button',
                                                ),
                                                label: l10n.promptReview,
                                                selected: _isModeRecommended(
                                                  TutorMode.review,
                                                ),
                                                onPressed: _sending
                                                    ? null
                                                    : _startNewReviewTurn,
                                                compact: true,
                                              ),
                                              const SizedBox(width: 8),
                                              _helpBiasChip(
                                                label: 'Easier',
                                                bias: TutorHelpBias.easier,
                                                compact: true,
                                              ),
                                              const SizedBox(width: 8),
                                              _helpBiasChip(
                                                label: 'Harder',
                                                bias: TutorHelpBias.harder,
                                                compact: true,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      _buildTtsControls(
                                        l10n: l10n,
                                        ttsSupported: ttsSupported,
                                        livePlaybackActive: livePlaybackActive,
                                      ),
                                      if (_ttsEnabled &&
                                          _ttsPreparingFirstChunk)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(l10n.ttsPreparingLabel),
                                          ],
                                        ),
                                      TextButton(
                                        key: const Key('exit_button'),
                                        onPressed:
                                            _sending ? null : _exitSession,
                                        child: Text(l10n.exitButton),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (footerProgressBadge != null) ...[
                                    footerProgressBadge,
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 320,
                                            child: _buildModelSelector(
                                              db: db,
                                              currentModel:
                                                  settings?.model ?? '',
                                              provider: provider,
                                              l10n: l10n,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _actionButton(
                                            key: const Key('learn_button'),
                                            label: l10n.promptLearn,
                                            selected: _isModeRecommended(
                                              TutorMode.learn,
                                            ),
                                            onPressed: _sending
                                                ? null
                                                : _startNewLearnTurn,
                                          ),
                                          const SizedBox(width: 8),
                                          _actionButton(
                                            key: const Key('review_button'),
                                            label: l10n.promptReview,
                                            selected: _isModeRecommended(
                                              TutorMode.review,
                                            ),
                                            onPressed: _sending
                                                ? null
                                                : _startNewReviewTurn,
                                          ),
                                          const SizedBox(width: 8),
                                          _helpBiasChip(
                                            label: 'Easier',
                                            bias: TutorHelpBias.easier,
                                          ),
                                          const SizedBox(width: 8),
                                          _helpBiasChip(
                                            label: 'Harder',
                                            bias: TutorHelpBias.harder,
                                          ),
                                          const SizedBox(width: 12),
                                          _buildTtsControls(
                                            l10n: l10n,
                                            ttsSupported: ttsSupported,
                                            livePlaybackActive:
                                                livePlaybackActive,
                                          ),
                                          if (_ttsEnabled &&
                                              _ttsPreparingFirstChunk) ...[
                                            const SizedBox(width: 8),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  l10n.ttsPreparingLabel,
                                                ),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(width: 8),
                                          TextButton(
                                            key: const Key('exit_button'),
                                            onPressed:
                                                _sending ? null : _exitSession,
                                            child: Text(l10n.exitButton),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
                if (_sttPressActive || _sttRecording)
                  _buildSttCancelOverlay(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMessageActions(
      ChatMessage message, int? lastUserId, AppLocalizations l10n,
      {required bool hasAudio,
      String? audioPath,
      required bool isPlaying,
      required bool isPaused}) {
    final actions = <Widget>[];

    if (hasAudio && audioPath != null) {
      final isActive = isPlaying || isPaused;
      actions.add(
        IconButton(
          tooltip: isPlaying
              ? l10n.ttsPauseTooltip
              : (isPaused ? l10n.ttsResumeTooltip : l10n.ttsPlayTooltip),
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () => _toggleMessageAudio(
            messageId: message.id,
            audioPath: audioPath,
            isPlaying: isPlaying,
            isPaused: isPaused,
          ),
        ),
      );
      if (isActive) {
        actions.add(
          IconButton(
            tooltip: l10n.ttsStopTooltip,
            icon: const Icon(Icons.stop),
            onPressed: _stopMessageAudio,
          ),
        );
      }
    }

    actions.addAll([
      IconButton(
        tooltip: l10n.copyTooltip,
        icon: const Icon(Icons.copy),
        onPressed: () => _copyMessage(message, l10n),
      ),
    ]);

    if (!widget.readOnly) {
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
    }

    return actions;
  }

  Widget _actionButton({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final selectedStyle = ElevatedButton.styleFrom(
      backgroundColor: theme.colorScheme.tertiaryContainer,
      foregroundColor: theme.colorScheme.onTertiaryContainer,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : null,
      minimumSize: compact ? Size.zero : null,
      tapTargetSize: compact
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      visualDensity: compact ? VisualDensity.compact : null,
    );
    return ElevatedButton(
      key: key,
      style: selected
          ? selectedStyle
          : (compact
              ? ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                )
              : null),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  Widget _helpBiasChip({
    required String label,
    required TutorHelpBias bias,
    bool compact = false,
  }) {
    final selected = _helpBias == bias;
    return FilterChip(
      label: Text(label),
      selected: selected,
      materialTapTargetSize: compact
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      visualDensity: compact ? VisualDensity.compact : null,
      onSelected: _sending
          ? null
          : (next) {
              setState(() {
                _helpBias = next ? bias : TutorHelpBias.unchanged;
                _recommendedAction = null;
              });
              unawaited(_persistVisibleControl(turnFinished: false));
            },
    );
  }

  Widget _buildTtsControls({
    required AppLocalizations l10n,
    required bool ttsSupported,
    required bool livePlaybackActive,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('TTS'),
        Tooltip(
          message: ttsSupported ? '' : l10n.ttsRequiresOpenAi,
          child: Switch(
            value: _ttsEnabled,
            onChanged: (_sending || !ttsSupported)
                ? null
                : (value) {
                    setState(() => _ttsEnabled = value);
                    if (!value) {
                      _stopLiveTts();
                    }
                  },
          ),
        ),
        IconButton(
          tooltip:
              _ttsStreamPaused ? l10n.ttsResumeTooltip : l10n.ttsPauseTooltip,
          icon: Icon(_ttsStreamPaused ? Icons.play_arrow : Icons.pause),
          onPressed: (!_ttsEnabled || !(_ttsPlaybackActive || _ttsStreamPaused))
              ? null
              : (_ttsStreamPaused ? _resumeLiveTts : _pauseLiveTts),
        ),
        IconButton(
          tooltip: l10n.ttsStopTooltip,
          icon: const Icon(Icons.stop),
          onPressed:
              (!_ttsEnabled || !livePlaybackActive) ? null : _stopLiveTts,
        ),
      ],
    );
  }

  Future<void> _startNewLearnTurn() async {
    setState(() {
      _mode = TutorMode.learn;
      _step = TutorTurnStep.newTurn;
      _recommendedAction = null;
    });
    await _persistVisibleControl(turnFinished: false);
    await _sendMessage(allowEmpty: true);
  }

  Future<void> _startNewReviewTurn() async {
    setState(() {
      _mode = TutorMode.review;
      _step = TutorTurnStep.newTurn;
      _recommendedAction = null;
    });
    await _persistVisibleControl(turnFinished: false);
    await _sendMessage(allowEmpty: true);
  }

  void _handleSttPointerDown(PointerDownEvent event) {
    if (_sttPressActive || _sttTranscribing) {
      return;
    }
    setState(() {
      _sttPressActive = true;
      _sttCancelHover = false;
    });
    _startSttRecording();
  }

  void _handleSttPointerMove(PointerMoveEvent event) {
    if (!_sttPressActive) {
      return;
    }
    _updateSttCancelHover(event.position);
  }

  void _handleSttPointerUp(PointerUpEvent event) {
    if (!_sttPressActive) {
      return;
    }
    _updateSttCancelHover(event.position);
    _finishSttPress(canceled: _sttCancelHover);
  }

  void _handleSttPointerCancel(PointerCancelEvent event) {
    if (!_sttPressActive) {
      return;
    }
    _finishSttPress(canceled: true);
  }

  Future<void> _startSttRecording() async {
    final l10n = AppLocalizations.of(context)!;
    final sttService = context.read<AppServices>().sttService;
    _prepareDraftForSttRecording();
    _pendingSttAudioPath = null;
    SttStartResult startResult;
    try {
      startResult =
          await sttService.startRecording(sessionId: widget.sessionId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sttPressActive = false;
        _sttRecording = false;
        _sttCancelHover = false;
      });
      _showMessage('${l10n.sttFailedMessage} ($error)');
      return;
    }
    if (!mounted) {
      return;
    }
    if (startResult.started) {
      setState(() => _sttRecording = true);
    } else {
      setState(() {
        _sttPressActive = false;
        _sttRecording = false;
        _sttCancelHover = false;
      });
      _inputFocus.requestFocus();
      _showMessage(
        startResult.permissionDenied
            ? l10n.sttPermissionDenied
            : (startResult.error ?? l10n.sttFailedMessage),
      );
    }
  }

  Future<void> _finishSttPress({required bool canceled}) async {
    final l10n = AppLocalizations.of(context)!;
    final sttService = context.read<AppServices>().sttService;
    setState(() {
      _sttPressActive = false;
      _sttCancelHover = false;
    });
    if (canceled) {
      await sttService.cancelRecording(sessionId: widget.sessionId);
      _pendingSttAudioPath = null;
      if (mounted) {
        setState(() => _sttRecording = false);
        _inputFocus.requestFocus();
      }
      return;
    }
    if (!_sttRecording) {
      return;
    }
    setState(() {
      _sttRecording = false;
      _sttTranscribing = true;
    });
    SttTranscriptionResult result;
    try {
      result = await sttService.stopAndTranscribe(sessionId: widget.sessionId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _sttTranscribing = false);
      _inputFocus.requestFocus();
      _showMessage('${l10n.sttFailedMessage} ($error)');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _sttTranscribing = false);
    if (result.isSuccess) {
      final autoSend =
          context.read<SettingsController>().settings?.sttAutoSend ?? false;
      _pendingSttAudioPath = result.audioPath;
      _applyTranscription(result.text!);
      if (autoSend && !_sending) {
        Future.microtask(_sendMessage);
      }
    } else {
      _pendingSttAudioPath = null;
      _inputFocus.requestFocus();
      _showMessage(result.error ?? l10n.sttFailedMessage);
    }
  }

  void _prepareDraftForSttRecording() {
    final normalized = normalizeDraftForSttRecording(_inputController.value);
    if (_inputController.value != normalized) {
      _inputController.value = normalized;
    }
    _inputFocus.unfocus();
  }

  void _updateSttCancelHover(Offset globalPosition) {
    final box = _sttCancelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final hovering = rect.contains(globalPosition);
    if (hovering == _sttCancelHover) {
      return;
    }
    setState(() => _sttCancelHover = hovering);
  }

  void _applyTranscription(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _applyingTranscription = true;
    final existing = _inputController.text.trim();
    final merged = existing.isEmpty ? trimmed : '$existing $trimmed';
    _inputController.value = TextEditingValue(
      text: merged,
      selection: TextSelection.collapsed(offset: merged.length),
    );
    _inputFocus.requestFocus();
    _applyingTranscription = false;
  }

  void _handleInputChanged() {
    final nextLineCount = _estimateInputLineCount(_inputController.text);
    if (nextLineCount > _inputLineCount) {
      _scheduleScrollToBottom();
    }
    _inputLineCount = nextLineCount;
    if (_applyingTranscription) {
      return;
    }
    return;
  }

  int _estimateInputLineCount(String text) {
    if (text.isEmpty) {
      return 1;
    }
    final lines = '\n'.allMatches(text).length + 1;
    if (lines < 1) {
      return 1;
    }
    if (lines > 3) {
      return 3;
    }
    return lines;
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _scrollToBottom({bool animated = true}) {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final target = _scrollController.position.maxScrollExtent;
    if (animated) {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
        ),
      );
      return;
    }
    _scrollController.jumpTo(target);
  }

  Widget _buildSttCancelOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final background = _sttCancelHover
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surface;
    final foreground = _sttCancelHover
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: _handleSttPointerMove,
        onPointerUp: _handleSttPointerUp,
        onPointerCancel: _handleSttPointerCancel,
        child: Stack(
          children: [
            CompositedTransformFollower(
              link: _sttButtonLink,
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: const Offset(0, -8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: AnimatedContainer(
                  key: _sttCancelKey,
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: _sttCancelHover
                          ? theme.colorScheme.error
                          : theme.colorScheme.outline,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.close, color: foreground, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage({bool allowEmpty = false}) async {
    final l10n = AppLocalizations.of(context)!;
    if (widget.readOnly) {
      return;
    }
    final trimmedInput = _inputController.text.trim();
    var allowEmptyNow = allowEmpty;
    if (trimmedInput.isEmpty && !allowEmptyNow) {
      final db = context.read<AppDatabase>();
      final messages = await db.getMessagesForSession(widget.sessionId);
      if (messages.isEmpty) {
        allowEmptyNow = true;
      } else {
        await _showErrorDialog(
          title: l10n.messageRequiredTitle,
          message: l10n.messageRequiredBody,
        );
        return;
      }
    }
    if (trimmedInput.isEmpty && !allowEmptyNow) {
      await _showErrorDialog(
        title: l10n.messageRequiredTitle,
        message: l10n.messageRequiredBody,
      );
      return;
    }
    setState(() => _sending = true);
    final db = context.read<AppDatabase>();
    final sessionService = context.read<AppServices>().sessionService;
    final sttService = context.read<AppServices>().sttService;
    final resolvedPromptName = _resolvePromptNameForSend();
    final modelOverride = _resolveModelOverride();
    _prepareTts();
    final pendingAudioPath = _pendingSttAudioPath;
    final shouldSaveSttAudio = pendingAudioPath != null;
    final onStudentMessageCreated = pendingAudioPath == null
        ? null
        : (int messageId) {
            sttService
                .saveMessageAudio(
              messageId: messageId,
              sourcePath: pendingAudioPath,
              sessionId: widget.sessionId,
            )
                .then((result) {
              if (mounted) {
                if (!result.success) {
                  _showMessage(l10n.sttAudioConvertFailedMessage);
                }
                setState(() {});
              }
            });
          };
    _pendingSttAudioPath = null;
    try {
      await _persistVisibleControl(turnFinished: false);
      final llmHandle = await sessionService.startTutorAction(
        sessionId: widget.sessionId,
        mode: resolvedPromptName,
        studentInput: trimmedInput,
        helpBias: _helpBias.wireValue,
        courseVersion: widget.courseVersion,
        node: widget.node,
        modelOverride: modelOverride,
        stream: true,
        streamToDatabase: !_ttsEnabled,
        onStudentMessageCreated:
            shouldSaveSttAudio ? onStudentMessageCreated : null,
        onAssistantMessageCreated:
            _ttsEnabled ? _handleAssistantMessageCreated : null,
        onChunk: _ttsEnabled ? _handleTtsChunk : null,
        onPromptWarning: () =>
            _showPersistentMessage(l10n.maxTokensTooSmallWarning),
      );
      _pending = llmHandle;
      await llmHandle.future;
      _flushTts();
      if (_ttsEnabled) {
        await _flushDisplay();
      }
      await _applyPersistedSessionControl(db);
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

  Future<void> _exitSession() async {
    final sessionService = context.read<AppServices>().sessionService;
    await sessionService.closeSession(widget.sessionId);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _cancelRequest() {
    _pending?.cancel();
    if (_ttsEnabled) {
      _stopLiveTts();
    }
    setState(() => _sending = false);
  }

  Future<void> _pauseLiveTts() async {
    if (!_ttsPlaybackActive || _ttsStreamPaused) {
      return;
    }
    _ttsStreamPaused = true;
    _ttsStreamPausedAt = DateTime.now();
    _ttsWordTimer?.cancel();
    await context.read<AppServices>().ttsService.pause(
          sessionId: widget.sessionId,
        );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _resumeLiveTts() async {
    if (!_ttsStreamPaused) {
      return;
    }
    final pausedAt = _ttsStreamPausedAt;
    _ttsStreamPaused = false;
    _ttsStreamPausedAt = null;
    if (_ttsStreamingActive && _ttsStreamStart != null && pausedAt != null) {
      final pausedMs = DateTime.now().difference(pausedAt).inMilliseconds;
      _ttsStreamStart = _ttsStreamStart!.add(Duration(milliseconds: pausedMs));
      _startWordTimer();
    }
    await context.read<AppServices>().ttsService.resume(
          sessionId: widget.sessionId,
        );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _stopLiveTts() async {
    if (_ttsStreamingActive) {
      _finishWordStreaming();
    }
    _ttsChunkQueue.clear();
    _ttsPendingBuffer.clear();
    _ttsChunker.reset();
    _ttsOutstandingChunks = 0;
    _ttsFlushPending = false;
    _ttsStreamingActive = false;
    _ttsPlaybackActive = false;
    _ttsChunkInFlight = false;
    _ttsStreamPaused = false;
    _ttsStreamPausedAt = null;
    _ttsPreparingFirstChunk = false;
    _ttsHardStopped = true;
    _ttsPrefetchTimer?.cancel();
    _ttsPrefetchWindowReached = false;
    _ttsPrefetchInFlight = false;
    _ttsPrefetchedAudio = null;
    _ttsPrefetchedChunk = null;
    _ttsWordTimer?.cancel();
    await context.read<AppServices>().ttsService.stop(
          sessionId: widget.sessionId,
        );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleMessageAudio({
    required int messageId,
    required String audioPath,
    required bool isPlaying,
    required bool isPaused,
  }) async {
    final ttsService = context.read<AppServices>().ttsService;
    if (isPlaying) {
      await ttsService.pauseReplay(sessionId: widget.sessionId);
      return;
    }
    if (isPaused) {
      await ttsService.resumeReplay(sessionId: widget.sessionId);
      return;
    }
    await ttsService.playSavedAudio(
      messageId: messageId,
      path: audioPath,
      sessionId: widget.sessionId,
    );
  }

  Future<void> _stopMessageAudio() async {
    await context
        .read<AppServices>()
        .ttsService
        .stopReplay(sessionId: widget.sessionId);
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
    return action == 'learn' || action == 'review';
  }

  Future<void> _refreshAnswer(
    ChatMessage message,
    AppLocalizations l10n,
  ) async {
    final action = message.action;
    if (action == null) {
      return;
    }
    setState(() => _sending = true);
    final db = context.read<AppDatabase>();
    final sessionService = context.read<AppServices>().sessionService;
    final modelOverride = _resolveModelOverride();
    _prepareTts();
    try {
      final resolvedPromptName = _resolvePromptNameForAction(
        action: action,
        preferredStep: TutorTurnStep.continueTurn,
      );
      await _persistVisibleControl(turnFinished: false);
      final llmHandle = await sessionService.startTutorAction(
        sessionId: widget.sessionId,
        mode: resolvedPromptName,
        studentInput: '',
        helpBias: _helpBias.wireValue,
        courseVersion: widget.courseVersion,
        node: widget.node,
        modelOverride: modelOverride,
        stream: true,
        streamToDatabase: !_ttsEnabled,
        onAssistantMessageCreated:
            _ttsEnabled ? _handleAssistantMessageCreated : null,
        onChunk: _ttsEnabled ? _handleTtsChunk : null,
        onPromptWarning: () =>
            _showPersistentMessage(l10n.maxTokensTooSmallWarning),
      );
      _pending = llmHandle;
      await llmHandle.future;
      _flushTts();
      if (_ttsEnabled) {
        await _flushDisplay();
      }
      await _applyPersistedSessionControl(db);
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
    _prepareTts();
    try {
      await db.deleteMessagesFrom(
        sessionId: widget.sessionId,
        fromMessageId: message.id,
      );
      final mode = _resolvePromptNameForAction(
        action: message.action ?? _mode.promptName,
        preferredStep: TutorTurnStep.continueTurn,
      );
      await _persistVisibleControl(turnFinished: false);
      final llmHandle = await sessionService.startTutorAction(
        sessionId: widget.sessionId,
        mode: mode,
        studentInput: updated.trim(),
        helpBias: _helpBias.wireValue,
        courseVersion: widget.courseVersion,
        node: widget.node,
        modelOverride: modelOverride,
        stream: true,
        streamToDatabase: !_ttsEnabled,
        onAssistantMessageCreated:
            _ttsEnabled ? _handleAssistantMessageCreated : null,
        onChunk: _ttsEnabled ? _handleTtsChunk : null,
        onPromptWarning: () =>
            _showPersistentMessage(l10n.maxTokensTooSmallWarning),
      );
      _pending = llmHandle;
      await llmHandle.future;
      _flushTts();
      if (_ttsEnabled) {
        await _flushDisplay();
      }
      await _applyPersistedSessionControl(db);
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

  void _showPersistentMessage(String message) {
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: l10n.closeButton,
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ),
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
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.modelLabel,
            border: const OutlineInputBorder(),
          ),
          selectedItemBuilder: (context) => models
              .map(
                (model) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    model,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          items: models
              .map(
                (model) => DropdownMenuItem(
                  value: model,
                  child: Text(
                    model,
                    overflow: TextOverflow.ellipsis,
                  ),
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

  Widget _buildCompactModelSelector({
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
        return PopupMenuButton<String>(
          key: ValueKey('compact_model_$value'),
          enabled: !_sending && models.isNotEmpty,
          tooltip: l10n.modelLabel,
          onSelected: (model) {
            setState(() => _sessionModel = model);
          },
          itemBuilder: (context) => models
              .map(
                (model) => PopupMenuItem<String>(
                  value: model,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(model, overflow: TextOverflow.ellipsis),
                  ),
                ),
              )
              .toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
              ),
              borderRadius: BorderRadius.circular(20),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune, size: 18),
                const SizedBox(width: 6),
                Text(_compactModelLabel(value, l10n.modelLabel)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        );
      },
    );
  }

  String _compactModelLabel(String model, String fallback) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      return fallback;
    }
    final slashIndex = trimmed.lastIndexOf('/');
    final base = slashIndex >= 0 ? trimmed.substring(slashIndex + 1) : trimmed;
    if (base.length <= 22) {
      return base;
    }
    return '${base.substring(0, 22)}...';
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
    final actionLabel = _actionLabel(message.action, l10n);
    return l10n.chatLabelTutor(actionLabel);
  }

  String _actionLabel(String? action, AppLocalizations l10n) {
    switch (action) {
      case 'learn':
        return l10n.promptLearn;
      case 'review':
        return l10n.promptReview;
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

  Future<void> _applyPersistedSessionControl(AppDatabase db) async {
    final session = await db.getSession(widget.sessionId);
    if (!mounted) {
      return;
    }
    await _resolveSessionEvidence(db, session);
    final control = _loadControlStateFromSession(session);
    if (control.mode != _mode ||
        control.step != _step ||
        control.helpBias != _helpBias ||
        control.recommendedAction != _recommendedAction) {
      setState(() {
        _mode = control.mode;
        _step = control.step;
        _helpBias = control.helpBias;
        _recommendedAction = control.recommendedAction;
      });
    }
    final justPassedKpEvent = control.justPassedKpEvent;
    if (justPassedKpEvent != null) {
      await _showPassedDialog(
        easyCount: justPassedKpEvent.easyPassedCount,
        mediumCount: justPassedKpEvent.mediumPassedCount,
        hardCount: justPassedKpEvent.hardPassedCount,
      );
      if (!mounted) {
        return;
      }
      await _persistControlState(
        control.copyWith(justPassedKpEvent: null),
      );
    }
  }

  Future<TutorEvidenceState> _resolveSessionEvidence(
    AppDatabase db,
    ChatSession? session,
  ) async {
    final stored =
        TutorEvidenceState.fromJsonText(session?.evidenceStateJson) ??
            TutorEvidenceState.initial();
    if (session == null) {
      return stored;
    }
    final messages = await db.getMessagesForSession(session.id);
    final rebuilt = TutorEvidenceState.rebuildFromAssistantTurns(
      seed: stored,
      turns: messages.where((message) => message.role == 'assistant').map(
            (message) => TutorEvidenceAssistantTurn(
              actionMode: message.action ?? '',
              parsed: _extractMessageJson(message),
            ),
          ),
    );
    if (rebuilt.toJsonText() != stored.toJsonText()) {
      await db.updateSessionContracts(
        sessionId: session.id,
        controlStateJson: session.controlStateJson,
        controlStateUpdatedAt: session.controlStateUpdatedAt,
        evidenceStateJson: rebuilt.toJsonText(),
        evidenceStateUpdatedAt: DateTime.now(),
      );
    }
    return rebuilt;
  }

  Future<void> _showPassedDialog({
    required int easyCount,
    required int mediumCount,
    required int hardCount,
  }) async {
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.kpPassedDialogTitle),
        content: SelectableText(
          l10n.kpPassedDialogMessage(
            '$easyCount',
            '$mediumCount',
            '$hardCount',
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _extractMessageJson(ChatMessage message) {
    final stored = message.parsedJson;
    if (stored != null && stored.trim().isNotEmpty) {
      final decoded = _tryDecodeJsonObject(stored);
      if (decoded != null) {
        return decoded;
      }
    }
    final raw = message.rawContent;
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = _tryDecodeJsonObject(raw);
      if (decoded != null) {
        return decoded;
      }
    }
    return _tryDecodeJsonObject(message.content);
  }

  Map<String, dynamic>? _tryDecodeJsonObject(String input) {
    final start = input.indexOf('{');
    final end = input.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      return null;
    }
    try {
      final decoded = jsonDecode(input.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  TutorControlState _loadControlStateFromSession(ChatSession? session) {
    return TutorControlState.fromJsonText(session?.controlStateJson) ??
        TutorControlState.defaultForMode(_mode);
  }

  Future<void> _persistVisibleControl({
    required bool turnFinished,
    TutorFinishedAction? recommendedAction,
  }) async {
    final db = context.read<AppDatabase>();
    final session = await db.getSession(widget.sessionId);
    final existing = _loadControlStateFromSession(session);
    final preserveActiveQuestion =
        _mode == TutorMode.review && _step == TutorTurnStep.continueTurn;
    return _persistControlState(
      TutorControlState(
        version: TutorControlState.currentVersion,
        mode: _mode,
        step: _step,
        turnFinished: turnFinished,
        helpBias: _helpBias,
        allowedActions: const <TutorFinishedAction>[],
        recommendedAction: turnFinished ? recommendedAction : null,
        activeReviewQuestion:
            preserveActiveQuestion ? existing.activeReviewQuestion : null,
        justPassedKpEvent: existing.justPassedKpEvent,
      ),
    );
  }

  Future<void> _persistControlState(TutorControlState control) async {
    final db = context.read<AppDatabase>();
    final services = context.read<AppServices>();
    try {
      await db.updateSessionContracts(
        sessionId: widget.sessionId,
        controlStateJson: control.toJsonText(),
        controlStateUpdatedAt: DateTime.now(),
      );
      await services.sessionUploadCacheService.captureSession(widget.sessionId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog(
        title: 'Failed to save tutor state',
        message: error.toString(),
      );
    }
  }

  String _resolvePromptNameForSend() {
    return _resolvePromptNameForAction(
      action: _mode.promptName,
      preferredStep: _step,
    );
  }

  String _resolvePromptNameForAction({
    required String action,
    required TutorTurnStep preferredStep,
  }) {
    return action.trim().toLowerCase();
  }

  bool _isModeRecommended(TutorMode mode) {
    final recommended = _recommendedAction;
    if (recommended == TutorFinishedAction.learn) {
      return mode == TutorMode.learn;
    }
    if (recommended == TutorFinishedAction.review) {
      return mode == TutorMode.review;
    }
    return _mode == mode && _step == TutorTurnStep.newTurn;
  }

  List<_ErrorBookPreviewItem> _buildErrorBookPreview(
    List<ChatMessage> messages,
  ) {
    final aggregates = <String, _ErrorBookPreviewItem>{};
    for (final message in messages) {
      if (message.role != 'assistant' || message.action != 'review') {
        continue;
      }
      final parsed = _extractMessageJson(message);
      final update = parsed?['error_book_update'];
      if (update is! Map<String, dynamic>) {
        continue;
      }
      final mistakeTag = (update['mistake_tag'] as String?)?.trim() ?? '';
      if (mistakeTag.isEmpty) {
        continue;
      }
      final note = (update['mistake_note'] as String?)?.trim() ?? '';
      final existing = aggregates[mistakeTag];
      if (existing == null) {
        aggregates[mistakeTag] = _ErrorBookPreviewItem(
          mistakeTag: mistakeTag,
          count: 1,
          lastNote: note.isEmpty ? 'No note.' : note,
        );
      } else {
        existing.count += 1;
        if (note.isNotEmpty) {
          existing.lastNote = note;
        }
      }
    }
    if (aggregates.isEmpty) {
      return const <_ErrorBookPreviewItem>[];
    }
    final sorted = aggregates.values.toList()
      ..sort((left, right) => right.count.compareTo(left.count));
    return sorted.take(3).toList(growable: false);
  }

  void _handleAssistantMessageCreated(int messageId) {
    _assistantMessageId = messageId;
    if (_ttsDisplayBuffer.isNotEmpty) {
      _scheduleDisplayFlush();
    }
  }

  void _prepareTts() {
    _ttsChunker.reset();
    _ttsPendingBuffer.clear();
    _ttsDisplayBuffer.clear();
    _ttsRawBuffer.clear();
    _ttsChunkQueue.clear();
    _assistantMessageId = null;
    _ttsGateOpen = false;
    _ttsGateStarted = false;
    _ttsGateTimer?.cancel();
    _ttsDisplayFlushTimer?.cancel();
    _ttsWordTimer?.cancel();
    final settings = context.read<SettingsController>().settings;
    _ttsInitialDelayMs = settings?.ttsInitialDelayMs ?? 60000;
    _ttsTextLeadMs = settings?.ttsTextLeadMs ?? 1000;
    _ttsOutstandingChunks = 0;
    _ttsLlmCompleted = false;
    _ttsFlushPending = false;
    _ttsStreamTokens = const [];
    _ttsStreamIndex = 0;
    _ttsStreamStart = null;
    _ttsStreamDurationMs = 0;
    _ttsStreamingActive = false;
    _ttsPlaybackActive = false;
    _ttsChunkInFlight = false;
    _ttsStreamPaused = false;
    _ttsStreamPausedAt = null;
    _ttsActiveChunkDisplayed = false;
    _ttsPreparingFirstChunk = false;
    _ttsHardStopped = false;
    _ttsPrefetchTimer?.cancel();
    _ttsPrefetchWindowReached = false;
    _ttsPrefetchInFlight = false;
    _ttsPrefetchedAudio = null;
    _ttsPrefetchedChunk = null;
    _ttsAudioDir = settings?.ttsAudioPath?.trim();
    if (_ttsEnabled) {
      context.read<AppServices>().ttsService.stop(sessionId: widget.sessionId);
    }
  }

  void _handleTtsChunk(String chunk) {
    if (!_ttsEnabled) {
      return;
    }
    if (chunk.isEmpty) {
      return;
    }
    if (_ttsHardStopped) {
      _ttsRawBuffer.write(chunk);
      _appendDisplayChunk(chunk);
      return;
    }
    if (!_ttsPreparingFirstChunk && !_ttsPlaybackActive && !_ttsChunkInFlight) {
      _ttsPreparingFirstChunk = true;
      if (mounted) {
        setState(() {});
      }
    }
    _ttsRawBuffer.write(chunk);
    _ttsPendingBuffer.write(chunk);
    _startTtsGateIfNeeded();
    if (_ttsGateOpen && !_ttsChunkInFlight && !_ttsStreamPaused) {
      _processPendingBuffer();
    }
  }

  void _flushTts() {
    if (!_ttsEnabled) {
      return;
    }
    if (_ttsHardStopped) {
      _ttsLlmCompleted = true;
      _scheduleDisplayFlush();
      _maybeFinalizeDisplay();
      return;
    }
    _ttsLlmCompleted = true;
    _openTtsGate();
    if (_ttsChunkInFlight || _ttsStreamPaused) {
      _ttsFlushPending = true;
      if (_ttsPrefetchWindowReached) {
        _attemptPrefetch(forceComplete: true);
      }
      return;
    }
    _processPendingBuffer();
    final chunks = _ttsChunker.flushComplete();
    _emitTtsChunks(chunks);
    _scheduleDisplayFlush();
    _maybeFinalizeDisplay();
  }

  void _startTtsGateIfNeeded() {
    if (_ttsGateStarted) {
      return;
    }
    _ttsGateStarted = true;
    if (_ttsInitialDelayMs <= 0) {
      _openTtsGate();
      return;
    }
    _ttsGateTimer = Timer(
      Duration(milliseconds: _ttsInitialDelayMs),
      _openTtsGate,
    );
  }

  void _openTtsGate() {
    if (_ttsGateOpen) {
      return;
    }
    _ttsGateOpen = true;
    _processPendingBuffer();
  }

  void _processPendingBuffer() {
    if (!_ttsGateOpen) {
      return;
    }
    if (_ttsChunkInFlight || _ttsStreamPaused) {
      return;
    }
    final pending = _ttsPendingBuffer.toString();
    if (pending.isEmpty) {
      return;
    }
    _ttsPendingBuffer.clear();
    final chunks = _ttsChunker.addText(pending);
    _emitTtsChunks(chunks);
  }

  void _feedPendingToChunker() {
    final pending = _ttsPendingBuffer.toString();
    if (pending.isEmpty) {
      return;
    }
    _ttsPendingBuffer.clear();
    _ttsChunker.addText(pending, allowCut: false);
  }

  void _emitTtsChunks(List<String> chunks) {
    if (chunks.isEmpty) {
      return;
    }
    for (final raw in chunks) {
      final spoken = _ttsSanitizer.sanitizeForTts(raw);
      if (spoken.trim().isEmpty) {
        _appendDisplayChunk(raw);
        continue;
      }
      _ttsOutstandingChunks += 1;
      _ttsChunkQueue.add(_TtsQueuedChunk(raw: raw, spoken: spoken));
    }
    _drainTtsQueue();
  }

  void _drainTtsQueue() {
    if (!_ttsEnabled ||
        _ttsChunkInFlight ||
        _ttsStreamPaused ||
        _ttsHardStopped) {
      return;
    }
    if (_ttsChunkQueue.isEmpty) {
      _maybeFinalizeDisplay();
      return;
    }
    final tts = context.read<AppServices>().ttsService;
    final next = _ttsChunkQueue.removeAt(0);
    _ttsChunkInFlight = true;
    _ttsActiveChunkDisplayed = false;
    tts.enqueue(
      next.spoken,
      sessionId: widget.sessionId,
      messageId: _assistantMessageId,
      audioDirectory: _ttsAudioDir,
      onPlaybackStart: (duration) {
        if (!mounted) {
          return;
        }
        _schedulePrefetchWindow(duration);
        _ttsPlaybackActive = true;
        _ttsStreamPaused = false;
        _ttsStreamPausedAt = null;
        _ttsPreparingFirstChunk = false;
        _startWordStreaming(
          rawText: next.raw,
          spokenText: next.spoken,
          duration: duration,
        );
        setState(() {});
      },
      onPlaybackComplete: (success) {
        if (!mounted) {
          return;
        }
        _handlePlaybackComplete(next);
      },
    );
  }

  void _schedulePrefetchWindow(Duration? duration) {
    _ttsPrefetchTimer?.cancel();
    _ttsPrefetchWindowReached = false;
    if (duration == null) {
      return;
    }
    final halfMs = (duration.inMilliseconds / 2).floor();
    if (halfMs <= 0) {
      return;
    }
    _ttsPrefetchTimer = Timer(Duration(milliseconds: halfMs), () {
      _ttsPrefetchWindowReached = true;
      if (_ttsChunkInFlight) {
        _attemptPrefetch(forceComplete: _ttsLlmCompleted);
      }
    });
  }

  Future<void> _attemptPrefetch({required bool forceComplete}) async {
    if (_ttsHardStopped ||
        _ttsPrefetchInFlight ||
        _ttsPrefetchedAudio != null) {
      return;
    }
    _feedPendingToChunker();
    String? rawChunk;
    if (forceComplete) {
      final chunks = _ttsChunker.flushComplete();
      if (chunks.isNotEmpty) {
        rawChunk = chunks.first;
        _ttsFlushPending = false;
      }
    } else {
      rawChunk = _ttsChunker.prefetchChunk();
    }
    if (rawChunk == null || rawChunk.trim().isEmpty) {
      return;
    }
    final spoken = _ttsSanitizer.sanitizeForTts(rawChunk);
    if (spoken.trim().isEmpty) {
      _appendDisplayChunk(rawChunk);
      return;
    }
    _ttsPrefetchInFlight = true;
    final tts = context.read<AppServices>().ttsService;
    final audio = await tts.prefetchAudio(
      spoken,
      sessionId: widget.sessionId,
      messageId: _assistantMessageId,
      audioDirectory: _ttsAudioDir,
    );
    _ttsPrefetchInFlight = false;
    if (!mounted) {
      return;
    }
    if (_ttsHardStopped) {
      if (audio != null && await audio.file.exists()) {
        await audio.file.delete();
      }
      return;
    }
    if (audio == null) {
      _ttsChunkQueue.add(_TtsQueuedChunk(raw: rawChunk, spoken: spoken));
      return;
    }
    _ttsOutstandingChunks += 1;
    _ttsPrefetchedAudio = audio;
    _ttsPrefetchedChunk = _TtsQueuedChunk(raw: rawChunk, spoken: spoken);
  }

  void _handlePlaybackComplete(_TtsQueuedChunk chunk) {
    if (_ttsHardStopped) {
      if (_ttsStreamingActive) {
        _finishWordStreaming();
      } else if (!_ttsActiveChunkDisplayed) {
        _appendDisplayChunk(chunk.raw);
        _ttsActiveChunkDisplayed = true;
      }
      _ttsPlaybackActive = false;
      _ttsChunkInFlight = false;
      _ttsStreamPaused = false;
      _ttsStreamPausedAt = null;
      _ttsPrefetchTimer?.cancel();
      _ttsPrefetchWindowReached = false;
      _ttsPrefetchInFlight = false;
      _ttsPrefetchedAudio = null;
      _ttsPrefetchedChunk = null;
      _maybeFinalizeDisplay();
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (_ttsStreamingActive) {
      _finishWordStreaming();
    } else if (!_ttsActiveChunkDisplayed) {
      _appendDisplayChunk(chunk.raw);
      _ttsActiveChunkDisplayed = true;
    }
    _ttsPlaybackActive = false;
    _ttsChunkInFlight = false;
    _ttsStreamPaused = false;
    _ttsStreamPausedAt = null;
    _ttsPrefetchTimer?.cancel();
    _ttsPrefetchWindowReached = false;
    final remaining = _ttsOutstandingChunks - 1;
    _ttsOutstandingChunks = remaining < 0 ? 0 : remaining;
    _processPendingBuffer();
    if (_ttsFlushPending && _ttsPrefetchedAudio == null) {
      _ttsFlushPending = false;
      _feedPendingToChunker();
      final chunks = _ttsChunker.flushComplete();
      _emitTtsChunks(chunks);
      _scheduleDisplayFlush();
    }
    _maybeFinalizeDisplay();
    if (_playPrefetchedIfReady()) {
      setState(() {});
      return;
    }
    _drainTtsQueue();
    setState(() {});
  }

  bool _playPrefetchedIfReady() {
    final audio = _ttsPrefetchedAudio;
    final chunk = _ttsPrefetchedChunk;
    if (audio == null || chunk == null) {
      return false;
    }
    _ttsPrefetchedAudio = null;
    _ttsPrefetchedChunk = null;
    _ttsChunkInFlight = true;
    _ttsActiveChunkDisplayed = false;
    final tts = context.read<AppServices>().ttsService;
    tts.playPrefetched(
      audio,
      onPlaybackStart: (duration) {
        if (!mounted) {
          return;
        }
        _schedulePrefetchWindow(duration);
        _ttsPlaybackActive = true;
        _ttsStreamPaused = false;
        _ttsStreamPausedAt = null;
        _ttsPreparingFirstChunk = false;
        _startWordStreaming(
          rawText: chunk.raw,
          spokenText: chunk.spoken,
          duration: duration,
        );
        setState(() {});
      },
      onPlaybackComplete: (success) {
        if (!mounted) {
          return;
        }
        _handlePlaybackComplete(chunk);
      },
    );
    return true;
  }

  void _startWordStreaming({
    required String rawText,
    required String spokenText,
    required Duration? duration,
  }) {
    _ttsWordTimer?.cancel();
    _ttsStreamTokens = _tokenizeForStreaming(rawText);
    final spokenTokens = _tokenizeForStreaming(spokenText);
    _ttsStreamIndex = 0;
    _ttsStreamDurationMs = _resolveDurationMs(
      duration: duration,
      spokenTokenCount: spokenTokens.length,
    );
    if (_ttsStreamTokens.isEmpty) {
      _ttsStreamingActive = false;
      _appendDisplayChunk(rawText);
      _ttsActiveChunkDisplayed = true;
      return;
    }
    _ttsStreamingActive = true;
    _ttsStreamPaused = false;
    _ttsStreamPausedAt = null;
    final leadMs = _ttsTextLeadMs <= 0
        ? 0
        : (_ttsTextLeadMs > _ttsStreamDurationMs
            ? _ttsStreamDurationMs
            : _ttsTextLeadMs);
    if (_ttsStreamDurationMs > 0 && leadMs > 0) {
      final leadCount =
          ((leadMs / _ttsStreamDurationMs) * _ttsStreamTokens.length).floor();
      if (leadCount > 0) {
        _appendStreamingTokens(leadCount);
      }
    }
    _ttsStreamStart = DateTime.now().subtract(Duration(milliseconds: leadMs));
    _startWordTimer();
  }

  void _startWordTimer() {
    _ttsWordTimer?.cancel();
    _ttsWordTimer = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => _tickWordStreaming(),
    );
  }

  void _tickWordStreaming() {
    if (!_ttsStreamingActive ||
        _ttsStreamTokens.isEmpty ||
        _ttsStreamStart == null) {
      _ttsWordTimer?.cancel();
      return;
    }
    if (_ttsStreamPaused) {
      _ttsWordTimer?.cancel();
      return;
    }
    final elapsedMs =
        DateTime.now().difference(_ttsStreamStart!).inMilliseconds;
    final durationMs = _ttsStreamDurationMs <= 0 ? 1 : _ttsStreamDurationMs;
    final ratio = elapsedMs / durationMs;
    final calculated = (ratio * _ttsStreamTokens.length).floor();
    final target = calculated < 0
        ? 0
        : (calculated > _ttsStreamTokens.length
            ? _ttsStreamTokens.length
            : calculated);
    if (target > _ttsStreamIndex) {
      _appendStreamingTokens(target - _ttsStreamIndex);
    }
    if (elapsedMs >= durationMs || _ttsStreamIndex >= _ttsStreamTokens.length) {
      _finishWordStreaming();
    }
  }

  void _finishWordStreaming() {
    if (_ttsStreamTokens.isEmpty) {
      _ttsWordTimer?.cancel();
      _ttsStreamingActive = false;
      return;
    }
    final remaining = _ttsStreamTokens.length - _ttsStreamIndex;
    if (remaining > 0) {
      _appendStreamingTokens(remaining);
    }
    _ttsWordTimer?.cancel();
    _ttsStreamingActive = false;
    _ttsStreamPaused = false;
    _ttsStreamPausedAt = null;
    _ttsActiveChunkDisplayed = true;
  }

  void _appendStreamingTokens(int count) {
    if (count <= 0 || _ttsStreamTokens.isEmpty) {
      return;
    }
    var end = _ttsStreamIndex + count;
    if (end < 0) {
      end = 0;
    } else if (end > _ttsStreamTokens.length) {
      end = _ttsStreamTokens.length;
    }
    if (end <= _ttsStreamIndex) {
      return;
    }
    final chunk = _ttsStreamTokens.sublist(_ttsStreamIndex, end).join();
    _ttsStreamIndex = end;
    if (chunk.isNotEmpty) {
      _appendDisplayChunk(chunk);
    }
  }

  List<String> _tokenizeForStreaming(String text) {
    if (text.isEmpty) {
      return const [];
    }
    final tokens = <String>[];
    final buffer = StringBuffer();
    bool isCjk(int codeUnit) {
      return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
          (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
          (codeUnit >= 0xF900 && codeUnit <= 0xFAFF);
    }

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final code = rune;
      if (char.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        tokens.add(char);
        continue;
      }
      if (isCjk(code)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        tokens.add(char);
        continue;
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    return tokens;
  }

  int _resolveDurationMs({
    required Duration? duration,
    required int spokenTokenCount,
  }) {
    if (duration != null && duration.inMilliseconds > 0) {
      return duration.inMilliseconds;
    }
    if (spokenTokenCount <= 0) {
      return 0;
    }
    const msPerToken = 220;
    final estimate = spokenTokenCount * msPerToken;
    return estimate < 400 ? 400 : estimate;
  }

  void _appendDisplayChunk(String chunk) {
    _ttsDisplayBuffer.write(chunk);
    _scheduleDisplayFlush();
  }

  void _scheduleDisplayFlush() {
    if (_assistantMessageId == null) {
      return;
    }
    if (_ttsDisplayFlushTimer?.isActive == true) {
      return;
    }
    _ttsDisplayFlushTimer = Timer(const Duration(milliseconds: 80), () async {
      await _flushDisplay();
    });
  }

  Future<void> _flushDisplay() async {
    if (_assistantMessageId == null) {
      return;
    }
    final content = _ttsDisplayBuffer.toString();
    if (content.isEmpty) {
      return;
    }
    final db = context.read<AppDatabase>();
    await db.updateChatMessageContent(
      messageId: _assistantMessageId!,
      content: content,
    );
  }

  Future<void> _maybeFinalizeDisplay() async {
    if (!_ttsLlmCompleted || _ttsOutstandingChunks > 0) {
      return;
    }
    if (_assistantMessageId == null) {
      return;
    }
    final services = context.read<AppServices>();
    final db = services.db;
    await db.updateChatMessageContent(
      messageId: _assistantMessageId!,
      content: _ttsRawBuffer.toString(),
    );
    final settings = await services.settingsRepository.load();
    await services.llmLogRepository.appendEntry(
      promptName: 'stream_display',
      model: settings.model,
      baseUrl: settings.baseUrl,
      mode: 'APP',
      status: 'ui_commit',
      uiCommitOk: true,
      responseChars: _ttsRawBuffer.length,
      teacherId: widget.courseVersion.teacherId,
      courseVersionId: widget.courseVersion.id,
      sessionId: widget.sessionId,
      kpKey: widget.node.kpKey,
      action: _mode.promptName,
    );
  }
}

class _SessionFooterProgressBadge extends StatelessWidget {
  const _SessionFooterProgressBadge({
    required this.db,
    required this.studentId,
    required this.courseVersionId,
    required this.kpKey,
  });

  final AppDatabase db;
  final int studentId;
  final int courseVersionId;
  final String kpKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<ResolvedStudentPassRule>(
      stream: db.watchResolvedStudentPassRule(
        courseVersionId: courseVersionId,
        studentId: studentId,
      ),
      initialData: const ResolvedStudentPassRule(
        easyWeight: ResolvedStudentPassRule.defaultEasyWeight,
        mediumWeight: ResolvedStudentPassRule.defaultMediumWeight,
        hardWeight: ResolvedStudentPassRule.defaultHardWeight,
        passThreshold: ResolvedStudentPassRule.defaultPassThreshold,
      ),
      builder: (context, passRuleSnapshot) {
        if (passRuleSnapshot.hasError) {
          Error.throwWithStackTrace(
            passRuleSnapshot.error!,
            passRuleSnapshot.stackTrace ?? StackTrace.current,
          );
        }
        final passRule = passRuleSnapshot.data!;
        return StreamBuilder<ProgressEntry?>(
          stream: db.watchProgress(
            studentId: studentId,
            courseVersionId: courseVersionId,
            kpKey: kpKey,
          ),
          builder: (context, progressSnapshot) {
            if (progressSnapshot.hasError) {
              Error.throwWithStackTrace(
                progressSnapshot.error!,
                progressSnapshot.stackTrace ?? StackTrace.current,
              );
            }
            final display = SessionProgressDisplayValue.fromProgress(
              passRule: passRule,
              progress: progressSnapshot.data,
            );
            return Container(
              key: const Key('student_session_progress_badge'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                display.compactLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _TtsQueuedChunk {
  const _TtsQueuedChunk({
    required this.raw,
    required this.spoken,
  });

  final String raw;
  final String spoken;
}

class _ErrorBookPreviewItem {
  _ErrorBookPreviewItem({
    required this.mistakeTag,
    required this.count,
    required this.lastNote,
  });

  final String mistakeTag;
  int count;
  String lastNote;
}
