import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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
  static const _siliconModel = 'FunAudioLLM/SenseVoiceSmall';

  final SecureStorageService _secureStorage;
  final SettingsRepository _settingsRepository;
  final TtsLogRepository _logRepository;
  final AudioRecorder _recorder = AudioRecorder();
  String _lastBaseUrl = _openAiBaseUrl;
  String _lastModel = _openAiModel;
  bool _recording = false;
  String? _activePath;

  bool get isRecording => _recording;

  Future<SttStartResult> startRecording({int? sessionId}) async {
    if (_recording) {
      return const SttStartResult(started: true);
    }
    bool hasPermission;
    try {
      hasPermission = await _recorder.hasPermission();
    } catch (error) {
      await _logError(
        message: 'Permission check failed: $error',
        sessionId: sessionId,
      );
      return SttStartResult(
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
    final path = await _buildRecordingPath(sessionId);
    try {
      final encoder = AudioEncoder.wav;
      final supported = await _recorder.isEncoderSupported(encoder);
      if (!supported) {
        await _logError(
          message: 'Encoder $encoder not supported.',
          sessionId: sessionId,
        );
        return SttStartResult(
          started: false,
          error: 'Microphone encoder not supported.',
        );
      }
      final config = RecordConfig(
        encoder: encoder,
        bitRate: 128000,
        sampleRate: 16000,
      );
      await _recorder.start(config, path: path);
      _recording = true;
      _activePath = path;
      await _logEvent(
        event: 'stt_record_start',
        message: 'Recording started.',
        sessionId: sessionId,
      );
      return const SttStartResult(started: true);
    } catch (error) {
      _recording = false;
      _activePath = null;
      await _logError(
        message: 'Recording start failed: $error',
        sessionId: sessionId,
      );
      return SttStartResult(
        started: false,
        error: 'Recording start failed.',
      );
    }
  }

  Future<SttTranscriptionResult> stopAndTranscribe({int? sessionId}) async {
    if (!_recording) {
      return const SttTranscriptionResult(
        error: 'Not recording.',
      );
    }
    _recording = false;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (error) {
      await _logError(
        message: 'Recording stop failed: $error',
        sessionId: sessionId,
      );
    }
    final resolved = (path ?? _activePath);
    _activePath = null;
    await _logEvent(
      event: 'stt_record_stop',
      message: 'Recording stopped.',
      sessionId: sessionId,
    );
    if (resolved == null) {
      return const SttTranscriptionResult(
        error: 'No recording captured.',
      );
    }
    final file = File(resolved);
    if (!await file.exists()) {
      await _logError(
        message: 'Recording file missing: $resolved',
        sessionId: sessionId,
      );
      return SttTranscriptionResult(
        error: 'Recording file missing.',
        audioPath: resolved,
      );
    }
    if (await file.length() == 0) {
      await _logError(
        message: 'Recording file empty: $resolved',
        sessionId: sessionId,
      );
      return SttTranscriptionResult(
        error: 'Recording file empty.',
        audioPath: resolved,
      );
    }
    await _logEvent(
      event: 'stt_saved',
      message: 'Saved recording: $resolved',
      sessionId: sessionId,
    );
    return transcribeFile(file, sessionId: sessionId);
  }

  Future<void> cancelRecording({int? sessionId}) async {
    if (!_recording) {
      return;
    }
    _recording = false;
    _activePath = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    await _logEvent(
      event: 'stt_record_cancel',
      message: 'Recording cancelled.',
      sessionId: sessionId,
    );
  }

  Future<SttTranscriptionResult> transcribeFile(
    File file, {
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
      await _logError(
        message: 'Missing API key.',
        sessionId: sessionId,
      );
      return const SttTranscriptionResult(
        error: 'Missing API key.',
      );
    }
    _lastBaseUrl = config.baseUrl;
    _lastModel = config.model;
    await _logEvent(
      event: 'stt_request',
      message: 'Uploading audio for transcription.',
      sessionId: sessionId,
    );
    try {
      final url = Uri.parse('${config.baseUrl}/audio/transcriptions');
      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Bearer ${apiKey!.trim()}';
      request.fields['model'] = config.model;
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );
      final streamed = await request.send().timeout(
            const Duration(seconds: 60),
          );
      final response = await http.Response.fromStream(streamed);
      final traceId =
          response.headers['x-siliconcloud-trace-id'] ??
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
          audioPath: file.path,
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
          audioPath: file.path,
        );
      }
      await _logEvent(
        event: 'stt_response',
        message: _formatResponseMessage(
          response.bodyBytes.length,
          traceId,
        ),
        statusCode: response.statusCode,
        textSnippet: text.trim(),
        textLength: text.trim().length,
        sessionId: sessionId,
      );
      return SttTranscriptionResult(
        text: text.trim(),
        statusCode: response.statusCode,
        audioPath: file.path,
      );
    } catch (error) {
      await _logError(
        message: 'STT request failed: $error',
        sessionId: sessionId,
      );
      return SttTranscriptionResult(
        error: 'STT request failed.',
        audioPath: file.path,
      );
    }
  }

  Future<String> _buildRecordingPath(int? sessionId) async {
    final settings = await _settingsRepository.load();
    final baseDir = (settings.logDirectory ?? '').trim();
    final parent = baseDir.isNotEmpty
        ? baseDir
        : (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(p.join(parent, 'stt_audio'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final suffix = sessionId == null ? '' : '_s$sessionId';
    return p.join(dir.path, 'stt_$timestamp$suffix.wav');
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
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  String _formatErrorMessage(
    int status,
    String body,
    String? traceId,
  ) {
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

class _SttConfig {
  const _SttConfig({
    required this.baseUrl,
    required this.model,
  });

  final String baseUrl;
  final String model;
}
