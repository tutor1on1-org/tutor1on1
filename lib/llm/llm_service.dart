import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/llm_call_repository.dart';
import '../services/llm_log_repository.dart';
import '../services/secure_storage_service.dart';
import '../services/settings_repository.dart';
import 'llm_hash.dart';
import 'llm_models.dart';
import 'llm_providers.dart';
import 'schema_validator.dart';

class LlmService {
  LlmService(
    this._settingsRepository,
    this._secureStorage,
    this._callRepository,
    this._logRepository,
    this._validator,
  );

  final SettingsRepository _settingsRepository;
  final SecureStorageService _secureStorage;
  final LlmCallRepository _callRepository;
  final LlmLogRepository _logRepository;
  final SchemaValidator _validator;

  LlmRequestHandle startCall({
    required String promptName,
    required String renderedPrompt,
    Map<String, dynamic>? schemaMap,
    String? conversationDigest,
    String? modelOverride,
    LlmCallContext? context,
  }) {
    final client = http.Client();
    var cancelled = false;
    final future = _execute(
      client: client,
      promptName: promptName,
      renderedPrompt: renderedPrompt,
      schemaMap: schemaMap,
      conversationDigest: conversationDigest,
      modelOverride: modelOverride,
      context: context,
      isCancelled: () => cancelled,
    ).whenComplete(() {
      client.close();
    });
    return LlmRequestHandle(
      future: future,
      cancel: () {
        cancelled = true;
        client.close();
      },
    );
  }

  LlmRequestHandle startStreamingCall({
    required String promptName,
    required String renderedPrompt,
    required void Function(String chunk) onChunk,
    Map<String, dynamic>? schemaMap,
    String? conversationDigest,
    String? modelOverride,
    LlmCallContext? context,
  }) {
    final client = http.Client();
    var cancelled = false;
    final future = _executeStreaming(
      client: client,
      promptName: promptName,
      renderedPrompt: renderedPrompt,
      onChunk: onChunk,
      schemaMap: schemaMap,
      conversationDigest: conversationDigest,
      modelOverride: modelOverride,
      context: context,
      isCancelled: () => cancelled,
    ).whenComplete(() {
      client.close();
    });
    return LlmRequestHandle(
      future: future,
      cancel: () {
        cancelled = true;
        client.close();
      },
    );
  }

  Future<LlmCallResult> _execute({
    required http.Client client,
    required String promptName,
    required String renderedPrompt,
    Map<String, dynamic>? schemaMap,
    String? conversationDigest,
    String? modelOverride,
    LlmCallContext? context,
    required bool Function() isCancelled,
  }) async {
    final settings = await _settingsRepository.load();
    final modelToUse = (modelOverride ?? '').trim().isNotEmpty
        ? modelOverride!.trim()
        : settings.model;
    final mode = LlmModeX.fromString(settings.llmMode);
    final providers = LlmProviders.defaultProviders(
      envBaseUrl: Platform.environment['OPENAI_BASE_URL'],
      envModel: Platform.environment['OPENAI_MODEL'],
    );
    final provider = LlmProviders.findById(providers, settings.providerId) ??
        LlmProviders.findByBaseUrl(providers, settings.baseUrl) ??
        LlmProvider(
          id: 'custom',
          label: 'Custom',
          baseUrl: settings.baseUrl,
          models: const [],
          maxTokensParam: MaxTokensParam.maxTokens,
        );
    final callHash = LlmHash.compute(
      baseUrl: settings.baseUrl,
      model: modelToUse,
      promptName: promptName,
      renderedPrompt: renderedPrompt,
      conversationDigest: conversationDigest,
    );

    if (mode == LlmMode.replay) {
      final record = await _callRepository.findByHash(callHash);
      if (record == null) {
        throw StateError('Replay miss for call hash: $callHash');
      }
      _logResponse(
        promptName: promptName,
        responseText: record.responseText ?? '',
        fromReplay: true,
        callHash: callHash,
      );
      return LlmCallResult(
        responseText: record.responseText ?? '',
        latencyMs: record.latencyMs ?? 0,
        fromReplay: true,
        responseJson: record.responseJson,
        parseValid: record.parseValid,
        parseError: record.parseError,
      );
    }

    final apiKey =
        await _secureStorage.readApiKeyForBaseUrl(settings.baseUrl);
    if ((apiKey ?? '').isEmpty) {
      throw StateError('Missing API key. Set it in Settings.');
    }

    final stopwatch = Stopwatch()..start();
    try {
      final responseText = await _postChatCompletion(
        client: client,
        baseUrl: settings.baseUrl,
        provider: provider,
        model: modelToUse,
        apiKey: apiKey!,
        renderedPrompt: renderedPrompt,
        timeoutSeconds: settings.timeoutSeconds,
        maxTokens: settings.maxTokens,
        isCancelled: isCancelled,
      );
      stopwatch.stop();

      String? responseJson;
      bool? parseValid;
      String? parseError;

      if (schemaMap != null) {
        final validation = await _validator.validateJson(
          schemaMap: schemaMap,
          responseText: responseText,
        );
        parseValid = validation.isValid;
        parseError = validation.error;
        if (validation.data != null) {
          responseJson = jsonEncode(validation.data);
        }
      }

      if (mode == LlmMode.liveRecord) {
        await _callRepository.insert(
          callHash: callHash,
          promptName: promptName,
          renderedPrompt: renderedPrompt,
          model: modelToUse,
          baseUrl: settings.baseUrl,
          responseText: responseText,
          responseJson: responseJson,
          parseValid: parseValid,
          parseError: parseError,
          latencyMs: stopwatch.elapsedMilliseconds,
          mode: mode.value,
          teacherId: context?.teacherId,
          studentId: context?.studentId,
          courseVersionId: context?.courseVersionId,
          sessionId: context?.sessionId,
          kpKey: context?.kpKey,
          action: context?.action,
        );
      }

      await _logRepository.appendEntry(
        promptName: promptName,
        model: modelToUse,
        baseUrl: settings.baseUrl,
        mode: mode.value,
        status: 'ok',
        callHash: callHash,
        latencyMs: stopwatch.elapsedMilliseconds,
        parseValid: parseValid,
        parseError: parseError,
        teacherId: context?.teacherId,
        studentId: context?.studentId,
        courseVersionId: context?.courseVersionId,
        sessionId: context?.sessionId,
        kpKey: context?.kpKey,
        action: context?.action,
      );

      _logResponse(
        promptName: promptName,
        responseText: responseText,
        fromReplay: false,
        callHash: callHash,
      );
      return LlmCallResult(
        responseText: responseText,
        latencyMs: stopwatch.elapsedMilliseconds,
        fromReplay: false,
        responseJson: responseJson,
        parseValid: parseValid,
        parseError: parseError,
      );
    } catch (error) {
      stopwatch.stop();
      await _logRepository.appendEntry(
        promptName: promptName,
        model: modelToUse,
        baseUrl: settings.baseUrl,
        mode: mode.value,
        status: 'error',
        callHash: callHash,
        latencyMs: stopwatch.elapsedMilliseconds,
        parseError: error.toString(),
        teacherId: context?.teacherId,
        studentId: context?.studentId,
        courseVersionId: context?.courseVersionId,
        sessionId: context?.sessionId,
        kpKey: context?.kpKey,
        action: context?.action,
      );
      rethrow;
    }
  }

  Future<LlmCallResult> _executeStreaming({
    required http.Client client,
    required String promptName,
    required String renderedPrompt,
    required void Function(String chunk) onChunk,
    Map<String, dynamic>? schemaMap,
    String? conversationDigest,
    String? modelOverride,
    LlmCallContext? context,
    required bool Function() isCancelled,
  }) async {
    final settings = await _settingsRepository.load();
    final modelToUse = (modelOverride ?? '').trim().isNotEmpty
        ? modelOverride!.trim()
        : settings.model;
    final mode = LlmModeX.fromString(settings.llmMode);
    final providers = LlmProviders.defaultProviders(
      envBaseUrl: Platform.environment['OPENAI_BASE_URL'],
      envModel: Platform.environment['OPENAI_MODEL'],
    );
    final provider = LlmProviders.findById(providers, settings.providerId) ??
        LlmProviders.findByBaseUrl(providers, settings.baseUrl) ??
        LlmProvider(
          id: 'custom',
          label: 'Custom',
          baseUrl: settings.baseUrl,
          models: const [],
          maxTokensParam: MaxTokensParam.maxTokens,
        );
    final callHash = LlmHash.compute(
      baseUrl: settings.baseUrl,
      model: modelToUse,
      promptName: promptName,
      renderedPrompt: renderedPrompt,
      conversationDigest: conversationDigest,
    );

    if (mode == LlmMode.replay) {
      final record = await _callRepository.findByHash(callHash);
      if (record == null) {
        throw StateError('Replay miss for call hash: $callHash');
      }
      if ((record.responseText ?? '').isNotEmpty) {
        onChunk(record.responseText ?? '');
      }
      _logResponse(
        promptName: promptName,
        responseText: record.responseText ?? '',
        fromReplay: true,
        callHash: callHash,
      );
      return LlmCallResult(
        responseText: record.responseText ?? '',
        latencyMs: record.latencyMs ?? 0,
        fromReplay: true,
        responseJson: record.responseJson,
        parseValid: record.parseValid,
        parseError: record.parseError,
      );
    }

    final apiKey =
        await _secureStorage.readApiKeyForBaseUrl(settings.baseUrl);
    if ((apiKey ?? '').isEmpty) {
      throw StateError('Missing API key. Set it in Settings.');
    }

    final stopwatch = Stopwatch()..start();
    try {
      final responseText = await _postChatCompletionStream(
        client: client,
        baseUrl: settings.baseUrl,
        provider: provider,
        model: modelToUse,
        apiKey: apiKey!,
        renderedPrompt: renderedPrompt,
        timeoutSeconds: settings.timeoutSeconds,
        maxTokens: settings.maxTokens,
        isCancelled: isCancelled,
        onChunk: onChunk,
      );
      stopwatch.stop();

      String? responseJson;
      bool? parseValid;
      String? parseError;

      if (schemaMap != null) {
        final validation = await _validator.validateJson(
          schemaMap: schemaMap,
          responseText: responseText,
        );
        parseValid = validation.isValid;
        parseError = validation.error;
        if (validation.data != null) {
          responseJson = jsonEncode(validation.data);
        }
      }

      if (mode == LlmMode.liveRecord) {
        await _callRepository.insert(
          callHash: callHash,
          promptName: promptName,
          renderedPrompt: renderedPrompt,
          model: modelToUse,
          baseUrl: settings.baseUrl,
          responseText: responseText,
          responseJson: responseJson,
          parseValid: parseValid,
          parseError: parseError,
          latencyMs: stopwatch.elapsedMilliseconds,
          mode: mode.value,
          teacherId: context?.teacherId,
          studentId: context?.studentId,
          courseVersionId: context?.courseVersionId,
          sessionId: context?.sessionId,
          kpKey: context?.kpKey,
          action: context?.action,
        );
      }

      await _logRepository.appendEntry(
        promptName: promptName,
        model: modelToUse,
        baseUrl: settings.baseUrl,
        mode: mode.value,
        status: 'ok',
        callHash: callHash,
        latencyMs: stopwatch.elapsedMilliseconds,
        parseValid: parseValid,
        parseError: parseError,
        teacherId: context?.teacherId,
        studentId: context?.studentId,
        courseVersionId: context?.courseVersionId,
        sessionId: context?.sessionId,
        kpKey: context?.kpKey,
        action: context?.action,
      );

      _logResponse(
        promptName: promptName,
        responseText: responseText,
        fromReplay: false,
        callHash: callHash,
      );
      return LlmCallResult(
        responseText: responseText,
        latencyMs: stopwatch.elapsedMilliseconds,
        fromReplay: false,
        responseJson: responseJson,
        parseValid: parseValid,
        parseError: parseError,
      );
    } catch (error) {
      stopwatch.stop();
      await _logRepository.appendEntry(
        promptName: promptName,
        model: modelToUse,
        baseUrl: settings.baseUrl,
        mode: mode.value,
        status: 'error',
        callHash: callHash,
        latencyMs: stopwatch.elapsedMilliseconds,
        parseError: error.toString(),
        teacherId: context?.teacherId,
        studentId: context?.studentId,
        courseVersionId: context?.courseVersionId,
        sessionId: context?.sessionId,
        kpKey: context?.kpKey,
        action: context?.action,
      );
      rethrow;
    }
  }

  void _logResponse({
    required String promptName,
    required String responseText,
    required bool fromReplay,
    required String callHash,
  }) {
    final source = fromReplay ? 'REPLAY' : 'LIVE';
    debugPrint(
      '[LLM][$source][$promptName][$callHash] response:\n$responseText',
    );
  }

  Future<String> _postChatCompletion({
    required http.Client client,
    required String baseUrl,
    required LlmProvider provider,
    required String model,
    required String apiKey,
    required String renderedPrompt,
    required int timeoutSeconds,
    required int maxTokens,
    required bool Function() isCancelled,
  }) async {
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}${provider.chatPath}');
    final bodyMap = <String, dynamic>{
      'model': model,
      'messages': [
        {'role': 'user', 'content': renderedPrompt},
      ],
    };
    bodyMap[provider.maxTokensField(model)] = maxTokens;
    final body = jsonEncode(bodyMap);

    http.Response response;
    response = await _sendWithRetry(
      () => client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              provider.authHeader: '${provider.authPrefix}$apiKey',
            },
            body: body,
          )
          .timeout(Duration(seconds: timeoutSeconds)),
      isCancelled: isCancelled,
    );

    if (isCancelled()) {
      throw StateError('Request cancelled.');
    }

    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode}: $responseBody',
      );
    }
    final payload = jsonDecode(responseBody);
    if (payload is! Map<String, dynamic>) {
      throw StateError('LLM response is not a JSON object.');
    }
    final content = _extractContentFromPayload(payload);
    if (content == null || content.trim().isEmpty) {
      throw StateError('LLM response missing content.');
    }
    return content;
  }

  Future<String> _postChatCompletionStream({
    required http.Client client,
    required String baseUrl,
    required LlmProvider provider,
    required String model,
    required String apiKey,
    required String renderedPrompt,
    required int timeoutSeconds,
    required int maxTokens,
    required bool Function() isCancelled,
    required void Function(String chunk) onChunk,
  }) async {
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}${provider.chatPath}');
    final bodyMap = <String, dynamic>{
      'model': model,
      'stream': true,
      'messages': [
        {'role': 'user', 'content': renderedPrompt},
      ],
    };
    bodyMap[provider.maxTokensField(model)] = maxTokens;
    final request = http.Request('POST', url);
    request.headers.addAll({
      'Content-Type': 'application/json',
      provider.authHeader: '${provider.authPrefix}$apiKey',
    });
    request.body = jsonEncode(bodyMap);
    final response = await client
        .send(request)
        .timeout(Duration(seconds: timeoutSeconds));

    if (isCancelled()) {
      throw StateError('Request cancelled.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw HttpException('HTTP ${response.statusCode}: $body');
    }

    final buffer = StringBuffer();
    var pending = '';
    final stream = response.stream.transform(utf8.decoder);
    await for (final chunk in stream) {
      if (isCancelled()) {
        throw StateError('Request cancelled.');
      }
      pending += chunk;
      while (true) {
        final lineBreak = pending.indexOf('\n');
        if (lineBreak == -1) {
          break;
        }
        var line = pending.substring(0, lineBreak);
        pending = pending.substring(lineBreak + 1);
        line = line.trim();
        if (line.isEmpty) {
          continue;
        }
        if (!line.startsWith('data:')) {
          continue;
        }
        final data = line.substring(5).trim();
        if (data == '[DONE]') {
          return buffer.toString();
        }
        try {
          final payload = jsonDecode(data);
          if (payload is Map<String, dynamic>) {
            final content = _extractContentFromPayload(payload);
            if (content != null && content.isNotEmpty) {
              buffer.write(content);
              onChunk(content);
            }
          }
        } catch (_) {
          continue;
        }
      }
    }
    return buffer.toString();
  }

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }


  String? _extractContentFromPayload(Map<String, dynamic> payload) {
    final choices = payload['choices'];
    if (choices is List && choices.isNotEmpty) {
      for (final choice in choices) {
        final content = _extractContentFromChoice(choice);
        if (content != null && content.trim().isNotEmpty) {
          return content;
        }
      }
    }
    final outputText = payload['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) {
      return outputText;
    }
    return null;
  }

  String? _extractContentFromChoice(dynamic choice) {
    if (choice is Map<String, dynamic>) {
      final message = choice['message'] ?? choice['delta'] ?? choice;
      if (message is Map<String, dynamic>) {
        final content = message['content'];
        final extracted = _extractContentValue(content);
        if (extracted != null) {
          return extracted;
        }
        final text = message['text'];
        if (text is String) {
          return text;
        }
      }
      final text = choice['text'];
      if (text is String) {
        return text;
      }
    }
    return null;
  }

  String? _extractContentValue(dynamic content) {
    if (content is String) {
      return content;
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        final value = _extractContentValue(part);
        if (value != null) {
          buffer.write(value);
        }
      }
      final result = buffer.toString();
      return result.isNotEmpty ? result : null;
    }
    if (content is Map<String, dynamic>) {
      final text = content['text'];
      if (text is String) {
        return text;
      }
      final inner = content['content'];
      if (inner != null) {
        return _extractContentValue(inner);
      }
    }
    return null;
  }

  Future<http.Response> _sendWithRetry(
    Future<http.Response> Function() request, {
    required bool Function() isCancelled,
  }) async {
    http.Response response;
    try {
      response = await request();
    } on Exception catch (e) {
      if (isCancelled()) {
        rethrow;
      }
      if (e is SocketException || e is HttpException || e is TimeoutException) {
        response = await request();
        return response;
      }
      rethrow;
    }

    if (isCancelled()) {
      return response;
    }

    if (response.statusCode == 429 ||
        (response.statusCode >= 500 && response.statusCode < 600)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      response = await request();
    }
    return response;
  }
}
