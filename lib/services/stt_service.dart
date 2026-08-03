import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:record/record.dart';

import 'browser_audio_store.dart';
import 'secure_storage_service.dart';
import 'settings_repository.dart';
import 'tts_log_repository.dart';

class SttService {
  SttService(
    this._secureStorage,
    this._settingsRepository,
    this._logRepository,
  );

  static const _openAiBaseUrl = 'https://api.openai.com/v1';
  static const _openAiModel = 'gpt-4o-mini-transcribe';
  static const _siliconBaseUrl = 'https://api.siliconflow.cn/v1';
  static const _isBrowser = bool.fromEnvironment('dart.library.js_interop');

  final SecureStorageService _secureStorage;
  final SettingsRepository _settingsRepository;
  final TtsLogRepository _logRepository;
  final AudioRecorder _recorder = AudioRecorder();
  final Map<String, _CapturedAudio> _capturedAudio = <String, _CapturedAudio>{};
  String _lastBaseUrl = _openAiBaseUrl;
  String _lastModel = _openAiModel;
  bool _recording = false;
  DateTime? _recordStartedAt;
  double? _recordPeakDb;
  bool _recordAmplitudeHasData = false;
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  bool get isRecording => _recording;

  static const int _minKeepDurationMs = 400;
  static const int _veryShortDurationMs = 1200;
  static const int _shortDurationMs = 3000;
  static const int _minDataBytes = 4096;
  static const double _silentDbThreshold = -55.0;
  static const double _veryShortDbThreshold = -45.0;

  @visibleForTesting
  static AudioEncoder selectRecordingEncoder({bool? isWindows}) {
    return AudioEncoder.opus;
  }

  Future<SttStartResult> startRecording({int? sessionId}) async {
    if (_recording) {
      return const SttStartResult(started: true);
    }
    _capturedAudio.clear();
    if (!_isBrowser) {
      return const SttStartResult(
        started: false,
        error: 'Microphone recording requires Chrome.',
      );
    }
    bool hasPermission;
    try {
      hasPermission = await _recorder.hasPermission();
    } catch (error) {
      await _logError(
        message: 'Permission check failed: $error',
        sessionId: sessionId,
      );
      return const SttStartResult(
        started: false,
        error: 'Microphone permission check failed.',
      );
    }
    if (!hasPermission) {
      await _logError(
        message: 'Microphone permission denied.',
        sessionId: sessionId,
      );
      return const SttStartResult(
        started: false,
        permissionDenied: true,
      );
    }
    final encoder = await _selectSupportedEncoder();
    if (encoder == null) {
      await _logError(
        message: 'No supported browser microphone encoder.',
        sessionId: sessionId,
      );
      return const SttStartResult(
        started: false,
        error: 'Microphone encoder not supported.',
      );
    }
    try {
      await _recorder.start(
        RecordConfig(
          encoder: encoder,
          bitRate: 96000,
          sampleRate: 48000,
          numChannels: 1,
        ),
        path: 'tutor1on1-recording${_extensionForEncoder(encoder)}',
      );
      _recording = true;
      _recordStartedAt = DateTime.now();
      _recordPeakDb = null;
      _recordAmplitudeHasData = false;
      _amplitudeSubscription ??= _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((amplitude) {
        if (!_recording) {
          return;
        }
        final current = amplitude.current;
        final maxValue = amplitude.max;
        if (current == 0 && maxValue == 0) {
          return;
        }
        _recordAmplitudeHasData = true;
        final localMax = math.max(current, maxValue);
        final peak = _recordPeakDb;
        if (peak == null || localMax > peak) {
          _recordPeakDb = localMax;
        }
      });
      await _logEvent(
        event: 'stt_record_start',
        message: 'Browser recording started with $encoder.',
        sessionId: sessionId,
      );
      return const SttStartResult(started: true);
    } catch (error) {
      _resetRecordingState();
      await _logError(
        message: 'Recording start failed: $error',
        sessionId: sessionId,
      );
      return const SttStartResult(
        started: false,
        error: 'Recording start failed.',
      );
    }
  }

  Future<SttTranscriptionResult> stopAndTranscribe({int? sessionId}) async {
    if (!_recording) {
      return const SttTranscriptionResult(error: 'Not recording.');
    }
    _recording = false;
    final startedAt = _recordStartedAt;
    final peakDb = _recordAmplitudeHasData ? _recordPeakDb : null;
    _recordStartedAt = null;
    _recordPeakDb = null;
    _recordAmplitudeHasData = false;
    String? blobUrl;
    try {
      blobUrl = await _recorder.stop();
    } catch (error) {
      await _logError(
        message: 'Recording stop failed: $error',
        sessionId: sessionId,
      );
    }
    await _logEvent(
      event: 'stt_record_stop',
      message: 'Browser recording stopped.',
      sessionId: sessionId,
    );
    if (blobUrl == null || blobUrl.trim().isEmpty) {
      return const SttTranscriptionResult(error: 'No recording captured.');
    }

    try {
      final response = await http
          .get(Uri.parse(blobUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return SttTranscriptionResult(
          error: 'Could not read the browser recording.',
          statusCode: response.statusCode,
        );
      }
      final bytes = response.bodyBytes;
      final durationMs = startedAt == null
          ? null
          : DateTime.now().difference(startedAt).inMilliseconds;
      if (_shouldDiscardRecording(
        byteLength: bytes.length,
        durationMs: durationMs,
        peakDb: peakDb,
      )) {
        await _logEvent(
          event: 'stt_discard_short_silent',
          message:
              'Discarded short/silent browser audio (${durationMs ?? 0}ms, peakDb ${(peakDb ?? 0).toStringAsFixed(1)}, bytes ${bytes.length}).',
          sessionId: sessionId,
        );
        return const SttTranscriptionResult(
          error: 'Recording too short or silent.',
        );
      }
      final mimeType = _normalizeMimeType(
        response.headers['content-type'],
      );
      final capturePath =
          'browser-recording://${DateTime.now().microsecondsSinceEpoch}';
      final captured = _CapturedAudio(
        bytes: Uint8List.fromList(bytes),
        mimeType: mimeType,
        fileName: _fileNameForMimeType(mimeType),
      );
      _capturedAudio[capturePath] = captured;
      await _logEvent(
        event: 'stt_saved',
        message: 'Captured browser recording (${bytes.length} bytes).',
        sessionId: sessionId,
      );
      final result = await _transcribeAudio(
        captured,
        audioPath: capturePath,
        sessionId: sessionId,
      );
      if (!result.isSuccess) {
        _capturedAudio.remove(capturePath);
      }
      return result;
    } catch (error) {
      await _logError(
        message: 'Could not read browser recording: $error',
        sessionId: sessionId,
      );
      return const SttTranscriptionResult(
        error: 'Could not read the browser recording.',
      );
    } finally {
      BrowserAudioStore.revokeObjectUrl(blobUrl);
    }
  }

  Future<void> cancelRecording({int? sessionId}) async {
    if (!_recording) {
      _capturedAudio.clear();
      return;
    }
    _resetRecordingState();
    _capturedAudio.clear();
    try {
      await _recorder.cancel();
    } catch (error) {
      await _logError(
        message: 'Recording cancel failed: $error',
        sessionId: sessionId,
      );
    }
    await _logEvent(
      event: 'stt_record_cancel',
      message: 'Browser recording cancelled.',
      sessionId: sessionId,
    );
  }

  Future<SttSaveResult> saveMessageAudio({
    required int messageId,
    required String sourcePath,
    int? sessionId,
  }) async {
    try {
      final resolved = sourcePath.trim();
      if (resolved.isEmpty) {
        return const SttSaveResult(
          success: false,
          error: 'Empty source path.',
        );
      }
      var captured = _capturedAudio[resolved];
      if (captured == null && resolved.startsWith('browser-audio://')) {
        final stored = await BrowserAudioStore.read(resolved);
        if (stored != null) {
          captured = _CapturedAudio(
            bytes: stored.bytes,
            mimeType: stored.mimeType,
            fileName: _fileNameForMimeType(stored.mimeType),
          );
        }
      }
      if (captured == null || captured.bytes.isEmpty) {
        await _logError(
          message: 'STT browser audio missing: $resolved',
          sessionId: sessionId,
        );
        return const SttSaveResult(
          success: false,
          error: 'Source audio missing.',
        );
      }
      final outputPath = buildMessageAudioPath(
        baseDir: '',
        messageId: messageId,
      );
      await BrowserAudioStore.write(
        path: outputPath,
        bytes: captured.bytes,
        mimeType: captured.mimeType,
      );
      _capturedAudio.remove(resolved);
      await _logEvent(
        event: 'stt_saved_message_audio',
        message: 'Saved STT audio in browser storage: $outputPath',
        sessionId: sessionId,
      );
      return SttSaveResult(success: true, outputPath: outputPath);
    } catch (error) {
      await _logError(
        message: 'Failed to save STT audio: $error',
        sessionId: sessionId,
      );
      return const SttSaveResult(
        success: false,
        error: 'Save failed.',
      );
    }
  }

  Future<SttTranscriptionResult> _transcribeAudio(
    _CapturedAudio audio, {
    required String audioPath,
    int? sessionId,
  }) async {
    final config = await _resolveSttConfig();
    if (config == null) {
      await _logError(
        message: 'STT requires OpenAI or SiliconFlow.',
        sessionId: sessionId,
      );
      return const SttTranscriptionResult(
        error: 'STT requires OpenAI or SiliconFlow.',
      );
    }
    final apiKey = await _secureStorage.readApiKeyForBaseUrl(config.baseUrl);
    if ((apiKey ?? '').trim().isEmpty) {
      await _logError(message: 'Missing API key.', sessionId: sessionId);
      return const SttTranscriptionResult(error: 'Missing API key.');
    }
    _lastBaseUrl = config.baseUrl;
    _lastModel = config.model;
    await _logEvent(
      event: 'stt_request',
      message: 'Uploading browser audio for transcription.',
      sessionId: sessionId,
    );
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${config.baseUrl}/audio/transcriptions'),
      );
      request.headers['Authorization'] = 'Bearer ${apiKey!.trim()}';
      request.fields['model'] = config.model;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          audio.bytes,
          filename: audio.fileName,
        ),
      );
      final streamed =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      final traceId = response.headers['x-siliconcloud-trace-id'] ??
          response.headers['x-request-id'];
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _logError(
          message: _formatErrorMessage(
            response.statusCode,
            response.body,
            traceId,
          ),
          statusCode: response.statusCode,
          sessionId: sessionId,
        );
        return SttTranscriptionResult(
          error: 'Transcription failed (${response.statusCode}).',
          statusCode: response.statusCode,
          audioPath: audioPath,
        );
      }
      final decoded = jsonDecode(response.body);
      final text =
          decoded is Map<String, dynamic> ? decoded['text'] as String? : null;
      if (text == null || text.trim().isEmpty) {
        await _logError(
          message: 'Transcription missing text.',
          statusCode: response.statusCode,
          sessionId: sessionId,
        );
        return SttTranscriptionResult(
          error: 'Transcription missing text.',
          statusCode: response.statusCode,
          audioPath: audioPath,
        );
      }
      await _logEvent(
        event: 'stt_response',
        message: _formatResponseMessage(response.bodyBytes.length, traceId),
        statusCode: response.statusCode,
        textSnippet: text.trim(),
        textLength: text.trim().length,
        sessionId: sessionId,
      );
      return SttTranscriptionResult(
        text: text.trim(),
        statusCode: response.statusCode,
        audioPath: audioPath,
      );
    } catch (error) {
      await _logError(
        message: 'STT request failed: $error',
        sessionId: sessionId,
      );
      return SttTranscriptionResult(
        error: 'STT request failed.',
        audioPath: audioPath,
      );
    }
  }

  Future<AudioEncoder?> _selectSupportedEncoder() async {
    for (final encoder in const <AudioEncoder>[
      AudioEncoder.opus,
      AudioEncoder.aacLc,
      AudioEncoder.wav,
    ]) {
      if (await _recorder.isEncoderSupported(encoder)) {
        return encoder;
      }
    }
    return null;
  }

  bool _shouldDiscardRecording({
    required int byteLength,
    required int? durationMs,
    required double? peakDb,
  }) {
    final duration = durationMs ?? 0;
    if ((duration > 0 && duration < _minKeepDurationMs) ||
        byteLength < _minDataBytes) {
      return true;
    }
    if (peakDb == null || duration <= 0) {
      return false;
    }
    return (duration < _veryShortDurationMs &&
            peakDb < _veryShortDbThreshold) ||
        (duration < _shortDurationMs && peakDb < _silentDbThreshold);
  }

  void _resetRecordingState() {
    _recording = false;
    _recordStartedAt = null;
    _recordPeakDb = null;
    _recordAmplitudeHasData = false;
  }

  String _extensionForEncoder(AudioEncoder encoder) {
    return switch (encoder) {
      AudioEncoder.opus => '.webm',
      AudioEncoder.aacLc || AudioEncoder.aacEld || AudioEncoder.aacHe => '.m4a',
      AudioEncoder.wav => '.wav',
      AudioEncoder.flac => '.flac',
      AudioEncoder.pcm16bits => '.pcm',
      AudioEncoder.amrNb || AudioEncoder.amrWb => '.3gp',
    };
  }

  String _normalizeMimeType(String? value) {
    final normalized = (value ?? '').split(';').first.trim().toLowerCase();
    if (normalized.startsWith('audio/')) {
      return normalized;
    }
    return 'audio/webm';
  }

  String _fileNameForMimeType(String mimeType) {
    return switch (mimeType) {
      'audio/mp4' || 'audio/aac' => 'recording.m4a',
      'audio/wav' || 'audio/vnd.wave' => 'recording.wav',
      'audio/flac' || 'audio/x-flac' => 'recording.flac',
      'audio/mpeg' => 'recording.mp3',
      _ => 'recording.webm',
    };
  }

  Future<_SttConfig?> _resolveSttConfig() async {
    final settings = await _settingsRepository.load();
    final baseUrl = _normalize(settings.baseUrl);
    final providerId = settings.providerId?.trim().toLowerCase() ?? '';
    _lastBaseUrl = baseUrl.isEmpty ? _openAiBaseUrl : baseUrl;
    final lower = baseUrl.toLowerCase();
    final model = (settings.sttModel ?? '').trim();
    if (model.isEmpty) {
      return null;
    }
    if (providerId == 'openai' || lower.contains('openai')) {
      _lastModel = model;
      return _SttConfig(
        baseUrl: baseUrl.isEmpty ? _openAiBaseUrl : baseUrl,
        model: model,
      );
    }
    if (providerId == 'siliconflow' || lower.contains('siliconflow')) {
      _lastModel = model;
      return _SttConfig(
        baseUrl: baseUrl.isEmpty ? _siliconBaseUrl : baseUrl,
        model: model,
      );
    }
    return null;
  }

  Future<void> _logEvent({
    required String event,
    required String message,
    int? statusCode,
    String? textSnippet,
    int? textLength,
    int? sessionId,
  }) async {
    await _logRepository.appendEvent(
      event: event,
      message: message,
      baseUrl: _lastBaseUrl,
      model: _lastModel,
      voice: '',
      statusCode: statusCode,
      textSnippet: textSnippet,
      textLength: textLength,
      sessionId: sessionId,
    );
  }

  Future<void> _logError({
    required String message,
    int? statusCode,
    int? sessionId,
  }) async {
    await _logRepository.appendError(
      message: message,
      baseUrl: _lastBaseUrl,
      model: _lastModel,
      voice: '',
      statusCode: statusCode,
      sessionId: sessionId,
    );
  }

  String _normalize(String value) {
    var trimmed = value.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  String _formatErrorMessage(int status, String body, String? traceId) {
    final snippet = body.length > 400 ? body.substring(0, 400) : body;
    final trace = (traceId ?? '').trim();
    return trace.isEmpty
        ? 'STT error $status: $snippet'
        : 'STT error $status (trace $trace): $snippet';
  }

  String _formatResponseMessage(int bytes, String? traceId) {
    final trace = (traceId ?? '').trim();
    return trace.isEmpty
        ? 'STT response received ($bytes bytes).'
        : 'STT response received ($bytes bytes, trace $trace).';
  }

  static String buildMessageAudioPath({
    required String baseDir,
    required int messageId,
  }) {
    return BrowserAudioStore.messagePath(kind: 'stt', messageId: messageId);
  }

  static bool hasSavedAudio(String path) {
    return BrowserAudioStore.contains(path);
  }
}

class SttTranscriptionResult {
  const SttTranscriptionResult({
    this.text,
    this.error,
    this.statusCode,
    this.audioPath,
  });

  final String? text;
  final String? error;
  final int? statusCode;
  final String? audioPath;

  bool get isSuccess => (text ?? '').trim().isNotEmpty;
}

class SttStartResult {
  const SttStartResult({
    required this.started,
    this.permissionDenied = false,
    this.error,
  });

  final bool started;
  final bool permissionDenied;
  final String? error;
}

class SttSaveResult {
  const SttSaveResult({
    required this.success,
    this.outputPath,
    this.conversionFailed = false,
    this.error,
  });

  final bool success;
  final String? outputPath;
  final bool conversionFailed;
  final String? error;
}

class _CapturedAudio {
  const _CapturedAudio({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
}

class _SttConfig {
  const _SttConfig({
    required this.baseUrl,
    required this.model,
  });

  final String baseUrl;
  final String model;
}
