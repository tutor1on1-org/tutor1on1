import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https/return_code.dart';
import 'package:flutter/services.dart';
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
    final encoder = AudioEncoder.aacLc;
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
    final path = await _buildRecordingPath(sessionId, encoder: encoder);
    try {
      final config = RecordConfig(
        encoder: encoder,
        bitRate: 96000,
        sampleRate: 44100,
        numChannels: 1,
      );
      await _recorder.start(config, path: path);
      _recording = true;
      _activePath = path;
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
        message: 'Recording started.',
        sessionId: sessionId,
      );
      return const SttStartResult(started: true);
    } catch (error) {
      _recording = false;
      _activePath = null;
      _recordStartedAt = null;
      _recordPeakDb = null;
      _recordAmplitudeHasData = false;
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
    final startedAt = _recordStartedAt;
    _recordStartedAt = null;
    final peakDb = _recordAmplitudeHasData ? _recordPeakDb : null;
    _recordPeakDb = null;
    _recordAmplitudeHasData = false;
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
    final durationMs = startedAt == null
        ? null
        : DateTime.now().difference(startedAt).inMilliseconds;
    var discarded = await _discardIfShortSilentRecording(
      file,
      durationMs: durationMs,
      peakDb: peakDb,
      sessionId: sessionId,
    );
    if (!discarded &&
        peakDb == null &&
        file.path.toLowerCase().endsWith('.wav')) {
      discarded = await _discardIfShortSilentWav(
        file,
        sessionId: sessionId,
      );
    }
    if (discarded) {
      return SttTranscriptionResult(
        error: 'Recording too short or silent.',
        audioPath: resolved,
      );
    }
    await _cleanupTempRecordings(
      keepPath: resolved,
      sessionId: sessionId,
    );
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
    _recordStartedAt = null;
    _recordPeakDb = null;
    _recordAmplitudeHasData = false;
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
      final inputFile = File(resolved);
      if (!await inputFile.exists()) {
        await _logError(
          message: 'STT audio file missing: $resolved',
          sessionId: sessionId,
        );
        return const SttSaveResult(
          success: false,
          error: 'Source audio missing.',
        );
      }
      final baseDir = await _resolveAudioBaseDirectory();
      final outputPath = buildMessageAudioPath(
        baseDir: baseDir,
        messageId: messageId,
      );
      final outputDir = Directory(p.dirname(outputPath));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }
      final converted = await _convertToMp3(
        inputPath: resolved,
        outputPath: outputPath,
        sessionId: sessionId,
      );
      if (!converted) {
        return const SttSaveResult(
          success: false,
          conversionFailed: true,
          error: 'Conversion failed.',
        );
      }
      try {
        await inputFile.delete();
      } catch (_) {}
      return SttSaveResult(
        success: true,
        outputPath: outputPath,
      );
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

  Future<String> _buildRecordingPath(
    int? sessionId, {
    required AudioEncoder encoder,
  }) async {
    final tmpDir = await getTemporaryDirectory();
    final dir = Directory(p.join(tmpDir.path, 'stt_tmp'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final suffix = sessionId == null ? '' : '_s$sessionId';
    final ext = _extensionForEncoder(encoder);
    return p.join(dir.path, 'stt_$timestamp$suffix$ext');
  }

  String _extensionForEncoder(AudioEncoder encoder) {
    switch (encoder) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacEld:
      case AudioEncoder.aacHe:
        return '.m4a';
      case AudioEncoder.opus:
        return '.opus';
      case AudioEncoder.flac:
        return '.flac';
      case AudioEncoder.pcm16bits:
        return '.pcm';
      case AudioEncoder.wav:
        return '.wav';
      case AudioEncoder.amrNb:
      case AudioEncoder.amrWb:
        return '.3gp';
    }
  }

  Future<String> _resolveAudioBaseDirectory() async {
    final settings = await _settingsRepository.load();
    final baseDir = (settings.logDirectory ?? '').trim();
    final parent = baseDir.isNotEmpty
        ? baseDir
        : (await getApplicationDocumentsDirectory()).path;
    return parent;
  }

  Future<bool> _convertToMp3({
    required String inputPath,
    required String outputPath,
    int? sessionId,
  }) async {
    try {
      final command = [
        '-y',
        '-i',
        '"$inputPath"',
        '-codec:a',
        'libmp3lame',
        '-b:a',
        '128k',
        '"$outputPath"',
      ].join(' ');
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        return true;
      }
      final logs = await session.getAllLogsAsString();
      await _logError(
        message: 'FFmpeg conversion failed: $logs',
        sessionId: sessionId,
      );
      return await _convertWithSystemFfmpeg(
        inputPath: inputPath,
        outputPath: outputPath,
        sessionId: sessionId,
        hint: 'ffmpeg_kit_failed',
      );
    } on MissingPluginException catch (error) {
      await _logError(
        message: 'FFmpeg plugin missing: $error',
        sessionId: sessionId,
      );
      return await _convertWithSystemFfmpeg(
        inputPath: inputPath,
        outputPath: outputPath,
        sessionId: sessionId,
        hint: 'missing_plugin',
      );
    } catch (error) {
      await _logError(
        message: 'FFmpeg conversion error: $error',
        sessionId: sessionId,
      );
      return await _convertWithSystemFfmpeg(
        inputPath: inputPath,
        outputPath: outputPath,
        sessionId: sessionId,
        hint: 'ffmpeg_kit_error',
      );
    }
  }

  Future<bool> _convertWithSystemFfmpeg({
    required String inputPath,
    required String outputPath,
    int? sessionId,
    required String hint,
  }) async {
    final candidates = <String>[];
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add(p.join(exeDir, 'ffmpeg.exe'));
      candidates.add(p.join(Directory.current.path, 'ffmpeg.exe'));
    }
    candidates.add('ffmpeg');
    final args = [
      '-y',
      '-i',
      inputPath,
      '-codec:a',
      'libmp3lame',
      '-b:a',
      '128k',
      outputPath,
    ];
    for (final bin in candidates) {
      try {
        final result = await Process.run(
          bin,
          args,
          runInShell: true,
        );
        if (result.exitCode == 0) {
          final file = File(outputPath);
          if (await file.exists() && await file.length() > 0) {
            await _logEvent(
              event: 'stt_convert_fallback',
              message: 'Converted via system ffmpeg ($bin) after $hint.',
              sessionId: sessionId,
            );
            return true;
          }
        }
        await _logError(
          message:
              'System ffmpeg failed ($bin): ${result.exitCode} ${result.stderr}',
          sessionId: sessionId,
        );
      } catch (error) {
        await _logError(
          message: 'System ffmpeg error ($bin): $error',
          sessionId: sessionId,
        );
      }
    }
    return false;
  }

  Future<bool> _discardIfShortSilentRecording(
    File file, {
    int? durationMs,
    double? peakDb,
    int? sessionId,
  }) async {
    final length = await file.length();
    final resolvedDuration = durationMs ?? 0;
    var discard = false;
    if (resolvedDuration > 0 && resolvedDuration < _minKeepDurationMs) {
      discard = true;
    }
    if (length > 0 && length < _minDataBytes) {
      discard = true;
    }
    if (!discard && peakDb != null && resolvedDuration > 0) {
      if (resolvedDuration < _veryShortDurationMs &&
          peakDb < _veryShortDbThreshold) {
        discard = true;
      } else if (resolvedDuration < _shortDurationMs &&
          peakDb < _silentDbThreshold) {
        discard = true;
      }
    }
    if (!discard) {
      return false;
    }
    await _logEvent(
      event: 'stt_discard_short_silent',
      message:
          'Discarded short/silent audio: ${file.path} (${resolvedDuration}ms, peakDb ${(peakDb ?? 0).toStringAsFixed(1)}, bytes $length)',
      sessionId: sessionId,
    );
    try {
      await file.delete();
    } catch (_) {}
    return true;
  }

  Future<bool> _discardIfShortSilentWav(
    File file, {
    int? sessionId,
  }) async {
    final info = await _readWavInfo(file);
    if (info == null) {
      return false;
    }
    if (info.dataSize <= 0) {
      return false;
    }
    final durationMs = info.durationMs;
    final stats = await _measureAmplitudeStats(file, info);
    var discard = false;
    if (durationMs < _minKeepDurationMs || info.dataSize < _minDataBytes) {
      discard = true;
    } else if (stats != null) {
      if (durationMs < _veryShortDurationMs &&
          stats.peak < 0.05 &&
          stats.rms < 0.02) {
        discard = true;
      } else if (durationMs < _shortDurationMs &&
          stats.peak < 0.02 &&
          stats.rms < 0.01) {
        discard = true;
      }
    } else if (durationMs < _veryShortDurationMs) {
      discard = true;
    }
    if (!discard) {
      return false;
    }
    await _logEvent(
      event: 'stt_discard_short_silent',
      message:
          'Discarded short/silent WAV: ${file.path} (${durationMs}ms, peak ${(stats?.peak ?? -1).toStringAsFixed(4)}, rms ${(stats?.rms ?? -1).toStringAsFixed(4)})',
      sessionId: sessionId,
    );
    try {
      await file.delete();
    } catch (_) {}
    return true;
  }

  Future<void> _cleanupTempRecordings({
    required String keepPath,
    int? sessionId,
  }) async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final dir = Directory(p.join(tmpDir.path, 'stt_tmp'));
      if (!await dir.exists()) {
        return;
      }
      await for (final entity in dir.list()) {
        if (entity is! File) {
          continue;
        }
        final lower = entity.path.toLowerCase();
        if (!lower.contains('${p.separator}stt_')) {
          continue;
        }
        final hasKnownExtension =
            lower.endsWith('.m4a') ||
            lower.endsWith('.wav') ||
            lower.endsWith('.aac') ||
            lower.endsWith('.mp4') ||
            lower.endsWith('.opus') ||
            lower.endsWith('.flac') ||
            lower.endsWith('.pcm') ||
            lower.endsWith('.3gp');
        if (!hasKnownExtension) {
          continue;
        }
        if (p.equals(entity.path, keepPath)) {
          continue;
        }
        var discarded = await _discardIfShortSilentRecording(
          entity,
          sessionId: sessionId,
        );
        if (!discarded && lower.endsWith('.wav')) {
          discarded = await _discardIfShortSilentWav(
            entity,
            sessionId: sessionId,
          );
        }
      }
    } catch (_) {}
  }

  Future<_WavInfo?> _readWavInfo(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final header = await raf.read(12);
      if (header.length < 12) {
        return null;
      }
      final riff = ascii.decode(header.sublist(0, 4));
      final wave = ascii.decode(header.sublist(8, 12));
      if (riff != 'RIFF' || wave != 'WAVE') {
        return null;
      }
      int? audioFormat;
      int? sampleRate;
      int? bitsPerSample;
      int? channels;
      int? byteRate;
      int? blockAlign;
      int? dataOffset;
      int? dataSize;
      while (true) {
        final chunkHeader = await raf.read(8);
        if (chunkHeader.length < 8) {
          break;
        }
        final id = ascii.decode(chunkHeader.sublist(0, 4));
        final size = _readLe32(chunkHeader, 4);
        final chunkStart = await raf.position();
        if (id == 'fmt ') {
          if (size < 16) {
            return null;
          }
          final fmt = await raf.read(size);
          if (fmt.length >= 16) {
            audioFormat = _readLe16(fmt, 0);
            channels = _readLe16(fmt, 2);
            sampleRate = _readLe32(fmt, 4);
            byteRate = _readLe32(fmt, 8);
            blockAlign = _readLe16(fmt, 12);
            bitsPerSample = _readLe16(fmt, 14);
          }
        } else if (id == 'data') {
          dataOffset = chunkStart;
          dataSize = size;
          break;
        }
        final next = chunkStart + size + (size.isOdd ? 1 : 0);
        await raf.setPosition(next);
      }
      if (audioFormat == null ||
          sampleRate == null ||
          bitsPerSample == null ||
          channels == null ||
          dataOffset == null ||
          dataSize == null ||
          byteRate == null ||
          blockAlign == null ||
          byteRate == 0) {
        return null;
      }
      return _WavInfo(
        audioFormat: audioFormat,
        sampleRate: sampleRate,
        bitsPerSample: bitsPerSample,
        channels: channels,
        byteRate: byteRate,
        blockAlign: blockAlign,
        dataOffset: dataOffset,
        dataSize: dataSize,
      );
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  Future<_AmplitudeStats?> _measureAmplitudeStats(
    File file,
    _WavInfo info,
  ) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      await raf.setPosition(info.dataOffset);
      var sampleBytes = math.min(info.dataSize, (info.byteRate * 0.5).floor());
      if (info.blockAlign > 0) {
        sampleBytes -= sampleBytes % info.blockAlign;
      }
      if (sampleBytes <= 0) {
        return null;
      }
      final bytes = await raf.read(sampleBytes);
      if (bytes.isEmpty) {
        return null;
      }
      final data = Uint8List.fromList(bytes);
      final view = ByteData.sublistView(data);
      var peak = 0.0;
      var sumSquares = 0.0;
      var samples = 0;
      final format = info.audioFormat;
      if (format == 1) {
        if (info.bitsPerSample == 8) {
          for (final b in data) {
            final value = (b - 128) / 128.0;
            final abs = value.abs();
            if (abs > peak) {
              peak = abs;
            }
            sumSquares += value * value;
            samples += 1;
          }
        } else if (info.bitsPerSample == 16) {
          for (var i = 0; i + 1 < data.length; i += 2) {
            final value = view.getInt16(i, Endian.little) / 32768.0;
            final abs = value.abs();
            if (abs > peak) {
              peak = abs;
            }
            sumSquares += value * value;
            samples += 1;
          }
        } else if (info.bitsPerSample == 24) {
          for (var i = 0; i + 2 < data.length; i += 3) {
            var value =
                data[i] | (data[i + 1] << 8) | (data[i + 2] << 16);
            if ((value & 0x800000) != 0) {
              value -= 0x1000000;
            }
            final normalized = value / 8388608.0;
            final abs = normalized.abs();
            if (abs > peak) {
              peak = abs;
            }
            sumSquares += normalized * normalized;
            samples += 1;
          }
        } else if (info.bitsPerSample == 32) {
          for (var i = 0; i + 3 < data.length; i += 4) {
            final value = view.getInt32(i, Endian.little) / 2147483648.0;
            final abs = value.abs();
            if (abs > peak) {
              peak = abs;
            }
            sumSquares += value * value;
            samples += 1;
          }
        } else {
          return null;
        }
      } else if (format == 3) {
        if (info.bitsPerSample == 32) {
          for (var i = 0; i + 3 < data.length; i += 4) {
            var value = view.getFloat32(i, Endian.little);
            if (value.isNaN) {
              continue;
            }
            value = value.clamp(-1.0, 1.0).toDouble();
            final abs = value.abs();
            if (abs > peak) {
              peak = abs;
            }
            sumSquares += value * value;
            samples += 1;
          }
        } else if (info.bitsPerSample == 64) {
          for (var i = 0; i + 7 < data.length; i += 8) {
            var value = view.getFloat64(i, Endian.little);
            if (value.isNaN) {
              continue;
            }
            value = value.clamp(-1.0, 1.0).toDouble();
            final abs = value.abs();
            if (abs > peak) {
              peak = abs;
            }
            sumSquares += value * value;
            samples += 1;
          }
        } else {
          return null;
        }
      } else {
        return null;
      }
      if (samples <= 0) {
        return null;
      }
      final rms = math.sqrt(sumSquares / samples);
      return _AmplitudeStats(peak: peak, rms: rms);
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  int _readLe16(List<int> bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  int _readLe32(List<int> bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
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

  static String buildMessageAudioPath({
    required String baseDir,
    required int messageId,
  }) {
    return p.join(baseDir, 'stt_audio', 'stt_message_$messageId.mp3');
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

class _WavInfo {
  const _WavInfo({
    required this.audioFormat,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.channels,
    required this.byteRate,
    required this.blockAlign,
    required this.dataOffset,
    required this.dataSize,
  });

  final int audioFormat;
  final int sampleRate;
  final int bitsPerSample;
  final int channels;
  final int byteRate;
  final int blockAlign;
  final int dataOffset;
  final int dataSize;

  int get durationMs =>
      byteRate <= 0 ? 0 : ((dataSize / byteRate) * 1000).round();
}

class _AmplitudeStats {
  const _AmplitudeStats({
    required this.peak,
    required this.rms,
  });

  final double peak;
  final double rms;
}

class _SttConfig {
  const _SttConfig({
    required this.baseUrl,
    required this.model,
  });

  final String baseUrl;
  final String model;
}
