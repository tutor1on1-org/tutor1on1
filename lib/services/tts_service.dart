import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'secure_storage_service.dart';
import 'settings_repository.dart';
import 'tts_log_repository.dart';

class TtsService {
  TtsService(
    this._secureStorage,
    this._settingsRepository,
    this._logRepository,
  ) {
    _attachPlayerListeners(_player, tag: 'primary');
    _attachReplayListeners();
  }

  static const _ttsBaseUrl = 'https://api.openai.com/v1';
  static const _ttsModel = 'gpt-4o-mini-tts';
  static const _ttsVoice = 'alloy';
  static const _ttsFormat = 'mp3';
  static const _siliconVoice = 'FunAudioLLM/CosyVoice2-0.5B:alex';

  final SecureStorageService _secureStorage;
  final SettingsRepository _settingsRepository;
  final TtsLogRepository _logRepository;
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _replayPlayer = AudioPlayer();
  final StreamController<TtsPlaybackState> _playbackController =
      StreamController<TtsPlaybackState>.broadcast();
  Future<void> _queue = Future.value();
  int _queueToken = 0;
  int _stopToken = 0;
  bool _playerListenersAttached = false;
  int? _replayMessageId;
  Duration _replayPosition = Duration.zero;
  Duration? _replayDuration;
  bool _replayIsPlaying = false;
  bool _replayIsPaused = false;
  String _lastBaseUrl = _ttsBaseUrl;
  String _lastModel = _ttsModel;
  String _lastVoice = _ttsVoice;

  Stream<TtsPlaybackState> get playbackStream => _playbackController.stream;

  Future<TtsTestResult> playLastAudio({int? sessionId}) async {
    await stop(sessionId: sessionId);
    try {
      final stopToken = _stopToken;
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}${Platform.pathSeparator}tts_last.mp3';
      final file = File(path);
      if (!await file.exists()) {
        await _logEvent(
          event: 'test_missing',
          message: 'Last TTS audio file not found.',
          sessionId: sessionId,
        );
        return const TtsTestResult(status: TtsTestStatus.missing);
      }
      await _logEvent(
        event: 'test_play',
        message: 'Testing playback of last audio file.',
        sessionId: sessionId,
      );
      final played = await _playFile(
        file,
        sessionId: sessionId,
        sourceTag: 'test',
        stopToken: stopToken,
      );
      if (!played) {
        await _logEvent(
          event: 'test_failed',
          message: 'Test playback did not complete.',
          sessionId: sessionId,
        );
        return const TtsTestResult(status: TtsTestStatus.failed);
      }
      await _logEvent(
        event: 'test_done',
        message: 'Test playback completed.',
        sessionId: sessionId,
      );
      return TtsTestResult(status: TtsTestStatus.played, path: file.path);
    } catch (error) {
      await _logError(
        message: 'Test playback failed: $error',
        sessionId: sessionId,
      );
      return const TtsTestResult(status: TtsTestStatus.failed);
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _replayPlayer.dispose();
    await _playbackController.close();
  }

  Future<void> stop({int? sessionId}) async {
    _queueToken++;
    _stopToken++;
    _queue = Future.value();
    await _player.stop();
    await _logEvent(
      event: 'stop',
      message: 'Playback stopped.',
      sessionId: sessionId,
    );
  }

  Future<void> stopReplay({int? sessionId}) async {
    await _replayPlayer.stop();
    _replayMessageId = null;
    _replayPosition = Duration.zero;
    _replayDuration = null;
    _replayIsPlaying = false;
    _replayIsPaused = false;
    _emitReplayState();
    await _logEvent(
      event: 'replay_stop',
      message: 'Replay stopped.',
      sessionId: sessionId,
    );
  }

  Future<void> playSavedAudio({
    required int messageId,
    required String path,
    int? sessionId,
  }) async {
    try {
      await stopReplay(sessionId: sessionId);
      _replayMessageId = messageId;
      _replayPosition = Duration.zero;
      _replayDuration = null;
      _replayIsPlaying = false;
      _replayIsPaused = false;
      _emitReplayState();
      await _logEvent(
        event: 'replay_set',
        message: 'Setting replay file: $path',
        sessionId: sessionId,
      );
      await _replayPlayer.setVolume(1.0);
      await _replayPlayer.setFilePath(path).timeout(const Duration(seconds: 8));
      await _logEvent(
        event: 'replay_start',
        message: 'Starting replay.',
        sessionId: sessionId,
      );
      await _replayPlayer.play().timeout(const Duration(seconds: 20));
    } catch (error) {
      _replayMessageId = null;
      _replayPosition = Duration.zero;
      _replayDuration = null;
      _replayIsPlaying = false;
      _emitReplayState();
      await _logError(
        message: 'Replay failed: $error',
        sessionId: sessionId,
      );
    }
  }

  Future<void> pause({int? sessionId}) async {
    await _player.pause();
  }

  Future<void> resume({int? sessionId}) async {
    await _player.play();
  }

  Future<void> pauseReplay({int? sessionId}) async {
    await _replayPlayer.pause();
    _replayIsPaused = true;
    _replayIsPlaying = false;
    _emitReplayState();
  }

  Future<void> resumeReplay({int? sessionId}) async {
    await _replayPlayer.play();
    _replayIsPaused = false;
    _emitReplayState();
  }

  Future<TtsPrefetchedAudio?> prefetchAudio(
    String text, {
    int? sessionId,
    int? messageId,
    String? audioDirectory,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final token = _queueToken;
    await _logEvent(
      event: 'prefetch',
      message: 'Prefetching TTS audio.',
      textSnippet: trimmed,
      textLength: trimmed.length,
      sessionId: sessionId,
    );
    final audioBytes = await _requestAudio(trimmed, sessionId: sessionId);
    if (audioBytes == null) {
      await _logEvent(
        event: 'prefetch_skip',
        message: 'Prefetch returned no audio bytes.',
        textSnippet: trimmed,
        textLength: trimmed.length,
        sessionId: sessionId,
      );
      return null;
    }
    if (token != _queueToken) {
      await _logEvent(
        event: 'prefetch_skip',
        message: 'Prefetch ignored due to stop token.',
        textSnippet: trimmed,
        textLength: trimmed.length,
        sessionId: sessionId,
      );
      return null;
    }
    if (audioDirectory != null &&
        audioDirectory.trim().isNotEmpty &&
        messageId != null) {
      await _appendMessageAudio(
        baseDir: audioDirectory.trim(),
        messageId: messageId,
        bytes: audioBytes,
        sessionId: sessionId,
      );
    }
    final file = await _writeTempAudio(audioBytes);
    return TtsPrefetchedAudio(
      file: file,
      textSnippet: trimmed,
      textLength: trimmed.length,
      sessionId: sessionId,
    );
  }

  Future<bool> playPrefetched(
    TtsPrefetchedAudio audio, {
    void Function(Duration? duration)? onPlaybackStart,
    void Function(bool success)? onPlaybackComplete,
  }) async {
    final completer = Completer<bool>();
    final token = _queueToken;
    _queue = _queue.then((_) async {
      if (token != _queueToken) {
        onPlaybackComplete?.call(false);
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        return;
      }
      try {
        final stopToken = _stopToken;
        if (!await audio.file.exists()) {
          await _logError(
            message: 'Prefetched audio file missing.',
            textSnippet: audio.textSnippet,
            textLength: audio.textLength,
            sessionId: audio.sessionId,
          );
          onPlaybackComplete?.call(false);
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          return;
        }
        final played = await _playFile(
          audio.file,
          sessionId: audio.sessionId,
          textSnippet: audio.textSnippet,
          textLength: audio.textLength,
          sourceTag: 'prefetch',
          stopToken: stopToken,
          onPlaybackStart: onPlaybackStart,
        );
        onPlaybackComplete?.call(played);
        if (!completer.isCompleted) {
          completer.complete(played);
        }
      } catch (error) {
        await _logError(
          message: 'Prefetch playback failed: $error',
          textSnippet: audio.textSnippet,
          textLength: audio.textLength,
          sessionId: audio.sessionId,
        );
        onPlaybackComplete?.call(false);
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      } finally {
        if (await audio.file.exists()) {
          await audio.file.delete();
        }
      }
    });
    return completer.future;
  }

  void enqueue(
    String text, {
    int? sessionId,
    int? messageId,
    String? audioDirectory,
    void Function(Duration? duration)? onPlaybackStart,
    void Function(bool success)? onPlaybackComplete,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    var playbackStarted = false;
    void notifyPlaybackStart(Duration? duration) {
      if (playbackStarted) {
        return;
      }
      playbackStarted = true;
      onPlaybackStart?.call(duration);
    }

    _logEvent(
      event: 'enqueue',
      message: 'Enqueued text for TTS.',
      textSnippet: trimmed,
      textLength: trimmed.length,
      sessionId: sessionId,
    );
    final token = _queueToken;
    _queue = _queue.catchError((error) async {
      await _logError(
        message: 'Queue error (previous): $error',
        textSnippet: trimmed,
        textLength: trimmed.length,
        sessionId: sessionId,
      );
    }).then((_) async {
      if (token != _queueToken) {
        await _logEvent(
          event: 'skip',
          message: 'Queue token mismatch (stopped).',
          textSnippet: trimmed,
          textLength: trimmed.length,
          sessionId: sessionId,
        );
        return;
      }
      await _logEvent(
        event: 'start',
        message: 'Queue processing started.',
        textSnippet: trimmed,
        textLength: trimmed.length,
        sessionId: sessionId,
      );
      try {
        final audioBytes = await _requestAudio(trimmed, sessionId: sessionId);
        if (audioBytes == null) {
          await _logEvent(
            event: 'skip',
            message: 'No audio bytes returned.',
            textSnippet: trimmed,
            textLength: trimmed.length,
            sessionId: sessionId,
          );
          onPlaybackComplete?.call(false);
          return;
        }
        if (audioDirectory != null &&
            audioDirectory.trim().isNotEmpty &&
            messageId != null) {
          await _appendMessageAudio(
            baseDir: audioDirectory.trim(),
            messageId: messageId,
            bytes: audioBytes,
            sessionId: sessionId,
          );
        }
        if (token != _queueToken) {
          await _logEvent(
            event: 'skip',
            message: 'Queue token mismatch after request.',
            textSnippet: trimmed,
            textLength: trimmed.length,
            sessionId: sessionId,
          );
          return;
        }
        final file = await _writeTempAudio(audioBytes);
        final stopToken = _stopToken;
        try {
          if (token != _queueToken) {
            await _logEvent(
              event: 'skip',
              message: 'Queue token mismatch before playback.',
              textSnippet: trimmed,
              textLength: trimmed.length,
              sessionId: sessionId,
            );
            return;
          }
          await _saveLastAudio(
            audioBytes,
            textSnippet: trimmed,
            textLength: trimmed.length,
            sessionId: sessionId,
          );
          final played = await _playFile(
            file,
            sessionId: sessionId,
            textSnippet: trimmed,
            textLength: trimmed.length,
            sourceTag: 'queue',
            stopToken: stopToken,
            onPlaybackStart: notifyPlaybackStart,
          );
          if (!played) {
            await _logEvent(
              event: 'skip',
              message: 'Playback did not complete.',
              textSnippet: trimmed,
              textLength: trimmed.length,
              sessionId: sessionId,
            );
            onPlaybackComplete?.call(false);
          } else {
            onPlaybackComplete?.call(true);
          }
        } catch (error) {
          await _logError(
            message: 'Playback failed: $error',
            textSnippet: trimmed,
            textLength: trimmed.length,
            sessionId: sessionId,
          );
          onPlaybackComplete?.call(false);
        } finally {
          if (await file.exists()) {
            await file.delete();
          }
        }
      } catch (error) {
        await _logError(
          message: 'Queue execution failed: $error',
          textSnippet: trimmed,
          textLength: trimmed.length,
          sessionId: sessionId,
        );
      }
    });
  }

  Future<List<int>?> _requestAudio(
    String text, {
    int? sessionId,
  }) async {
    final config = await _resolveTtsConfig();
    if (config == null) {
      return null;
    }
    final apiKey = await _secureStorage.readApiKeyForBaseUrl(config.baseUrl);
    if ((apiKey ?? '').trim().isEmpty) {
      return null;
    }
    _lastBaseUrl = config.baseUrl;
    _lastModel = config.model;
    _lastVoice = config.voice;
    try {
      final url = Uri.parse('${config.baseUrl}/audio/speech');
      final payload = <String, dynamic>{
        'model': config.model,
        'input': text,
        'response_format': _ttsFormat,
      };
      if (config.voice.trim().isNotEmpty) {
        payload['voice'] = config.voice;
      }
      if (config.stream != null) {
        payload['stream'] = config.stream;
      }
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiKey!.trim()}',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
      final traceId = response.headers['x-siliconcloud-trace-id'];
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _logError(
          message: _formatErrorMessage(
            response.statusCode,
            response.body,
            traceId,
          ),
          statusCode: response.statusCode,
          textSnippet: text,
          textLength: text.length,
          sessionId: sessionId,
          isRequestError: true,
        );
        return null;
      }
      await _logEvent(
        event: 'response',
        message: _formatResponseMessage(
          response.bodyBytes.length,
          traceId,
        ),
        statusCode: response.statusCode,
        textSnippet: text,
        textLength: text.length,
        sessionId: sessionId,
        isRequestEvent: true,
      );
      return response.bodyBytes;
    } catch (error) {
      await _logError(
        message: 'TTS request failed: $error',
        textSnippet: text,
        textLength: text.length,
        sessionId: sessionId,
        isRequestError: true,
      );
      return null;
    }
  }

  Future<File> _writeTempAudio(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final file = File('${dir.path}${Platform.pathSeparator}tts_$timestamp.mp3');
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<bool> _playFile(
    File file, {
    int? sessionId,
    String? textSnippet,
    int? textLength,
    required String sourceTag,
    required int stopToken,
    void Function(Duration? duration)? onPlaybackStart,
  }) async {
    final played = await _playWithPlayer(
      _player,
      file,
      sessionId: sessionId,
      textSnippet: textSnippet,
      textLength: textLength,
      tag: sourceTag,
      onPlaybackStart: onPlaybackStart,
    );
    if (played) {
      return true;
    }
    if (stopToken != _stopToken) {
      await _logEvent(
        event: 'fallback_skip',
        message: 'Playback stopped; skip fallback.',
        textSnippet: textSnippet,
        textLength: textLength,
        sessionId: sessionId,
      );
      return false;
    }
    await _logEvent(
      event: 'fallback',
      message: 'Primary player failed, trying fallback.',
      textSnippet: textSnippet,
      textLength: textLength,
      sessionId: sessionId,
    );
    final fallback = AudioPlayer();
    _attachPlayerListeners(fallback, tag: 'fallback');
    try {
      return await _playWithPlayer(
        fallback,
        file,
        sessionId: sessionId,
        textSnippet: textSnippet,
        textLength: textLength,
        tag: 'fallback',
        onPlaybackStart: onPlaybackStart,
      );
    } finally {
      await fallback.dispose();
    }
  }

  Future<bool> _playWithPlayer(
    AudioPlayer player,
    File file, {
    int? sessionId,
    String? textSnippet,
    int? textLength,
    required String tag,
    void Function(Duration? duration)? onPlaybackStart,
  }) async {
    StreamSubscription<Duration>? startSub;
    StreamSubscription<ProcessingState>? stateSub;
    Timer? startTimer;
    bool hasStarted = false;
    void stopStartSub() {
      startSub?.cancel();
      startSub = null;
    }

    void stopStateSub() {
      stateSub?.cancel();
      stateSub = null;
    }

    void stopStartTimer() {
      startTimer?.cancel();
      startTimer = null;
    }

    try {
      await player.setVolume(1.0);
      await _logEvent(
        event: 'set_file',
        message: 'Setting audio file ($tag): ${file.path}',
        textSnippet: textSnippet,
        textLength: textLength,
        sessionId: sessionId,
      );
      await player.setFilePath(file.path).timeout(const Duration(seconds: 8));
      await _logEvent(
        event: 'set_file_done',
        message: 'Audio file ready ($tag).',
        textSnippet: textSnippet,
        textLength: textLength,
        sessionId: sessionId,
      );
      final completer = Completer<bool>();
      final duration = player.duration;
      startSub = player.positionStream.listen((position) {
        if (position > const Duration(milliseconds: 20)) {
          hasStarted = true;
          stopStartTimer();
          onPlaybackStart?.call(duration);
          stopStartSub();
        }
      });
      stateSub = player.processingStateStream.listen((state) {
        if (completer.isCompleted) {
          return;
        }
        if (state == ProcessingState.completed) {
          stopStartTimer();
          stopStartSub();
          completer.complete(true);
          stopStateSub();
          return;
        }
        if (state == ProcessingState.idle && !player.playing) {
          stopStartTimer();
          stopStartSub();
          completer.complete(false);
          stopStateSub();
        }
      });
      player.play();
      startTimer = Timer(const Duration(seconds: 3), () async {
        if (completer.isCompleted || hasStarted) {
          return;
        }
        await _logEvent(
          event: 'start_timeout',
          message: 'Playback did not start (no position updates).',
          textSnippet: textSnippet,
          textLength: textLength,
          sessionId: sessionId,
        );
        stopStartSub();
        stopStateSub();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        player.stop();
      });
      return await completer.future;
    } catch (error) {
      stopStartSub();
      stopStateSub();
      stopStartTimer();
      await _logError(
        message: 'Playback failed ($tag): $error',
        textSnippet: textSnippet,
        textLength: textLength,
        sessionId: sessionId,
      );
      return false;
    } finally {
      stopStartTimer();
    }
  }

  Future<void> _saveLastAudio(
    List<int> bytes, {
    String? textSnippet,
    int? textLength,
    int? sessionId,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}tts_last.mp3');
      await file.writeAsBytes(bytes, flush: true);
      await _logEvent(
        event: 'saved',
        message: 'Saved last TTS audio to ${file.path}',
        textSnippet: textSnippet,
        textLength: textLength,
        sessionId: sessionId,
      );
    } catch (error) {
      await _logError(
        message: 'Failed to save last audio: $error',
        textSnippet: textSnippet,
        textLength: textLength,
        sessionId: sessionId,
      );
    }
  }

  Future<void> _appendMessageAudio({
    required String baseDir,
    required int messageId,
    required List<int> bytes,
    int? sessionId,
  }) async {
    try {
      final dir = Directory(baseDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final path = p.join(dir.path, 'tts_message_$messageId.mp3');
      final file = File(path);
      await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
      await _logEvent(
        event: 'saved_message_audio',
        message: 'Appended TTS audio to $path',
        sessionId: sessionId,
      );
    } catch (error) {
      await _logError(
        message: 'Failed to append message audio: $error',
        sessionId: sessionId,
      );
    }
  }

  Future<_TtsConfig?> _resolveTtsConfig() async {
    final settings = await _settingsRepository.load();
    final baseUrl = _normalizeBaseUrl(settings.baseUrl);
    final providerId = (settings.providerId ?? '').trim().toLowerCase();
    final isSiliconflow =
        providerId == 'siliconflow' || baseUrl.contains('siliconflow');
    final isOpenAi = providerId == 'openai' || baseUrl.contains('openai.com');
    final model = (settings.ttsModel ?? '').trim();
    if (model.isEmpty) {
      return null;
    }
    if (!isSiliconflow && !isOpenAi) {
      return null;
    }
    return _TtsConfig(
      baseUrl: baseUrl,
      model: model,
      voice: isSiliconflow ? _siliconVoice : _ttsVoice,
      stream: isSiliconflow ? false : null,
    );
  }

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  String _formatResponseMessage(int length, String? traceId) {
    final base = 'Received TTS audio bytes ($length).';
    if (traceId == null || traceId.trim().isEmpty) {
      return base;
    }
    return '$base trace_id=${traceId.trim()}';
  }

  String _formatErrorMessage(int status, String body, String? traceId) {
    final base = 'HTTP $status: $body';
    if (traceId == null || traceId.trim().isEmpty) {
      return base;
    }
    return '$base trace_id=${traceId.trim()}';
  }

  Future<void> _logError({
    required String message,
    String? textSnippet,
    int? textLength,
    int? statusCode,
    int? sessionId,
    bool isRequestError = false,
  }) {
    if (!isRequestError) {
      return Future.value();
    }
    return _logRepository.appendError(
      message: message,
      baseUrl: _lastBaseUrl,
      model: _lastModel,
      voice: _lastVoice,
      textSnippet: textSnippet,
      textLength: textLength,
      statusCode: statusCode,
      sessionId: sessionId,
    );
  }

  Future<void> _logEvent({
    required String event,
    required String message,
    String? textSnippet,
    int? textLength,
    int? statusCode,
    int? sessionId,
    bool isRequestEvent = false,
  }) {
    if (!isRequestEvent) {
      return Future.value();
    }
    return _logRepository.appendEvent(
      event: event,
      message: message,
      baseUrl: _lastBaseUrl,
      model: _lastModel,
      voice: _lastVoice,
      textSnippet: textSnippet,
      textLength: textLength,
      statusCode: statusCode,
      sessionId: sessionId,
    );
  }

  void _attachPlayerListeners(AudioPlayer player, {required String tag}) {
    if (player == _player && _playerListenersAttached) {
      return;
    }
    if (player == _player) {
      _playerListenersAttached = true;
    }
    player.playerStateStream.listen(
      (state) {
        _logEvent(
          event: 'player_state',
          message:
              'State ($tag): ${state.processingState}, playing=${state.playing}',
        );
      },
      onError: (error) {
        _logError(message: 'Player state error: $error');
      },
    );
    player.playbackEventStream.listen(
      (event) {
        final duration = event.duration?.inMilliseconds;
        final position = event.updatePosition.inMilliseconds;
        final buffered = event.bufferedPosition.inMilliseconds;
        _logEvent(
          event: 'playback_event',
          message:
              'Playback ($tag): state=${event.processingState}, pos=${position}ms, buf=${buffered}ms, dur=${duration ?? -1}ms',
        );
      },
      onError: (error) {
        _logError(message: 'Playback event error: $error');
      },
    );
  }

  void _attachReplayListeners() {
    _replayPlayer.positionStream.listen((position) {
      _replayPosition = position;
      _emitReplayState();
    }, onError: (error) {
      _logError(message: 'Replay position error: $error');
    });
    _replayPlayer.durationStream.listen((duration) {
      _replayDuration = duration;
      _emitReplayState();
    }, onError: (error) {
      _logError(message: 'Replay duration error: $error');
    });
    _replayPlayer.playerStateStream.listen((state) {
      _replayIsPlaying = state.playing;
      if (state.playing) {
        _replayIsPaused = false;
      }
      if (state.processingState == ProcessingState.completed ||
          state.processingState == ProcessingState.idle) {
        _replayIsPlaying = false;
        if (state.processingState == ProcessingState.completed ||
            state.processingState == ProcessingState.idle) {
          _replayIsPaused = false;
        }
      }
      _emitReplayState();
      if (state.processingState == ProcessingState.completed) {
        _replayMessageId = null;
        _emitReplayState();
      }
    }, onError: (error) {
      _logError(message: 'Replay state error: $error');
    });
  }

  void _emitReplayState() {
    _playbackController.add(
      TtsPlaybackState(
        messageId: _replayMessageId,
        position: _replayPosition,
        duration: _replayDuration,
        isPlaying: _replayIsPlaying,
        isPaused: _replayIsPaused,
      ),
    );
  }

  static String buildMessageAudioPath({
    required String baseDir,
    required int messageId,
  }) {
    return p.join(baseDir, 'tts_message_$messageId.mp3');
  }
}

class _TtsConfig {
  const _TtsConfig({
    required this.baseUrl,
    required this.model,
    required this.voice,
    required this.stream,
  });

  final String baseUrl;
  final String model;
  final String voice;
  final bool? stream;
}

enum TtsTestStatus { played, missing, failed }

class TtsTestResult {
  const TtsTestResult({required this.status, this.path});

  final TtsTestStatus status;
  final String? path;
}

class TtsPrefetchedAudio {
  const TtsPrefetchedAudio({
    required this.file,
    required this.textSnippet,
    required this.textLength,
    required this.sessionId,
  });

  final File file;
  final String? textSnippet;
  final int? textLength;
  final int? sessionId;
}

class TtsPlaybackState {
  const TtsPlaybackState({
    required this.messageId,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isPaused,
  });

  final int? messageId;
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
  final bool isPaused;
}
