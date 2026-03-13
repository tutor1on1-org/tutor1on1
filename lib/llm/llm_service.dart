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
import 'llm_reasoning_support.dart';
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
    final reasoningEffort = LlmReasoningSupport.normalizeEffort(
      settings.reasoningEffort,
    );
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
      reasoningEffort: reasoningEffort,
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
        callHash: callHash,
        model: modelToUse,
        baseUrl: settings.baseUrl,
      );
    }

    final apiKey = await _secureStorage.readApiKeyForBaseUrl(settings.baseUrl);
    if ((apiKey ?? '').isEmpty) {
      throw StateError('Missing API key. Set it in Settings.');
    }

    final stopwatch = Stopwatch()..start();
    try {
      final responseText = await _postChatCompletion(
        reasoningEffort: reasoningEffort,
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

      final finalResponseText = responseText.responseText;
      String? responseJson;
      bool? parseValid;
      String? parseError;

      if (schemaMap != null) {
        final validation = await _validator.validateJson(
          schemaMap: schemaMap,
          responseText: finalResponseText,
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
          responseText: finalResponseText,
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
        reasoningText: LlmReasoningSupport.encodeReasoningLog(
          provider: provider,
          model: modelToUse,
          reasoningEffort: reasoningEffort,
          reasoningText: responseText.reasoningText,
          reasoningTokens: responseText.reasoningTokens,
        ),
        teacherId: context?.teacherId,
        studentId: context?.studentId,
        courseVersionId: context?.courseVersionId,
        sessionId: context?.sessionId,
        kpKey: context?.kpKey,
        action: context?.action,
        renderedChars: renderedPrompt.length,
        responseChars: finalResponseText.length,
      );

      _logResponse(
        promptName: promptName,
        responseText: finalResponseText,
        fromReplay: false,
        callHash: callHash,
      );
      _logReasoning(
        promptName: promptName,
        reasoningText: responseText.reasoningText,
        fromReplay: false,
        callHash: callHash,
      );
      return LlmCallResult(
        responseText: finalResponseText,
        latencyMs: stopwatch.elapsedMilliseconds,
        fromReplay: false,
        responseJson: responseJson,
        reasoningText: responseText.reasoningText,
        parseValid: parseValid,
        parseError: parseError,
        callHash: callHash,
        model: modelToUse,
        baseUrl: settings.baseUrl,
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
        reasoningText: LlmReasoningSupport.encodeReasoningLog(
          provider: provider,
          model: modelToUse,
          reasoningEffort: reasoningEffort,
        ),
        teacherId: context?.teacherId,
        studentId: context?.studentId,
        courseVersionId: context?.courseVersionId,
        sessionId: context?.sessionId,
        kpKey: context?.kpKey,
        action: context?.action,
        renderedChars: renderedPrompt.length,
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
    final reasoningEffort = LlmReasoningSupport.normalizeEffort(
      settings.reasoningEffort,
    );
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
      reasoningEffort: reasoningEffort,
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
        callHash: callHash,
        model: modelToUse,
        baseUrl: settings.baseUrl,
      );
    }

    final apiKey = await _secureStorage.readApiKeyForBaseUrl(settings.baseUrl);
    if ((apiKey ?? '').isEmpty) {
      throw StateError('Missing API key. Set it in Settings.');
    }

    final stopwatch = Stopwatch()..start();
    try {
      final responseText = await _postChatCompletionStream(
        reasoningEffort: reasoningEffort,
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

      final finalResponseText = responseText.responseText;
      String? responseJson;
      bool? parseValid;
      String? parseError;

      if (schemaMap != null) {
        final validation = await _validator.validateJson(
          schemaMap: schemaMap,
          responseText: finalResponseText,
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
          responseText: finalResponseText,
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
        reasoningText: LlmReasoningSupport.encodeReasoningLog(
          provider: provider,
          model: modelToUse,
          reasoningEffort: reasoningEffort,
          reasoningText: responseText.reasoningText,
          reasoningTokens: responseText.reasoningTokens,
        ),
        teacherId: context?.teacherId,
        studentId: context?.studentId,
        courseVersionId: context?.courseVersionId,
        sessionId: context?.sessionId,
        kpKey: context?.kpKey,
        action: context?.action,
        renderedChars: renderedPrompt.length,
        responseChars: finalResponseText.length,
      );

      _logResponse(
        promptName: promptName,
        responseText: finalResponseText,
        fromReplay: false,
        callHash: callHash,
      );
      _logReasoning(
        promptName: promptName,
        reasoningText: responseText.reasoningText,
        fromReplay: false,
        callHash: callHash,
      );
      return LlmCallResult(
        responseText: finalResponseText,
        latencyMs: stopwatch.elapsedMilliseconds,
        fromReplay: false,
        responseJson: responseJson,
        reasoningText: responseText.reasoningText,
        parseValid: parseValid,
        parseError: parseError,
        callHash: callHash,
        model: modelToUse,
        baseUrl: settings.baseUrl,
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
        reasoningText: LlmReasoningSupport.encodeReasoningLog(
          provider: provider,
          model: modelToUse,
          reasoningEffort: reasoningEffort,
        ),
        teacherId: context?.teacherId,
        studentId: context?.studentId,
        courseVersionId: context?.courseVersionId,
        sessionId: context?.sessionId,
        kpKey: context?.kpKey,
        action: context?.action,
        renderedChars: renderedPrompt.length,
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

  void _logReasoning({
    required String promptName,
    required String? reasoningText,
    required bool fromReplay,
    required String callHash,
  }) {
    final trimmed = reasoningText?.trim() ?? '';
    if (trimmed.isEmpty) {
      return;
    }
    final source = fromReplay ? 'REPLAY' : 'LIVE';
    debugPrint(
      '[LLM][$source][$promptName][$callHash] reasoning:\n$trimmed',
    );
  }

  Future<LlmPreparedResponse> _postChatCompletion({
    required http.Client client,
    required String baseUrl,
    required LlmProvider provider,
    required String model,
    required String reasoningEffort,
    required String apiKey,
    required String renderedPrompt,
    required int timeoutSeconds,
    required int maxTokens,
    required bool Function() isCancelled,
  }) async {
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}${provider.chatPath}');
    final bodyMap = _buildRequestBody(
      provider: provider,
      model: model,
      renderedPrompt: renderedPrompt,
      maxTokens: maxTokens,
      reasoningEffort: reasoningEffort,
      stream: false,
    );
    final body = jsonEncode(bodyMap);

    http.Response response;
    response = await _sendWithRetry(
      () => client
          .post(
            url,
            headers: _buildHeaders(provider: provider, apiKey: apiKey),
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
    final content = LlmReasoningSupport.extractResponse(
      payload: payload,
      provider: provider,
    );
    if (content.responseText.trim().isEmpty) {
      throw StateError('LLM response missing content.');
    }
    return content;
  }

  Future<LlmPreparedResponse> _postChatCompletionStream({
    required http.Client client,
    required String baseUrl,
    required LlmProvider provider,
    required String model,
    required String reasoningEffort,
    required String apiKey,
    required String renderedPrompt,
    required int timeoutSeconds,
    required int maxTokens,
    required bool Function() isCancelled,
    required void Function(String chunk) onChunk,
  }) async {
    if (provider.apiFormat == LlmApiFormat.anthropicMessages) {
      return _postAnthropicStream(
        client: client,
        baseUrl: baseUrl,
        provider: provider,
        model: model,
        reasoningEffort: reasoningEffort,
        apiKey: apiKey,
        renderedPrompt: renderedPrompt,
        timeoutSeconds: timeoutSeconds,
        maxTokens: maxTokens,
        isCancelled: isCancelled,
        onChunk: onChunk,
      );
    }
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}${provider.chatPath}');
    final bodyMap = _buildRequestBody(
      provider: provider,
      model: model,
      renderedPrompt: renderedPrompt,
      maxTokens: maxTokens,
      reasoningEffort: reasoningEffort,
      stream: true,
    );
    final request = http.Request('POST', url);
    request.headers.addAll(_buildHeaders(provider: provider, apiKey: apiKey));
    request.body = jsonEncode(bodyMap);
    final response =
        await client.send(request).timeout(Duration(seconds: timeoutSeconds));

    if (isCancelled()) {
      throw StateError('Request cancelled.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw HttpException('HTTP ${response.statusCode}: $body');
    }

    final responseBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
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
          return LlmPreparedResponse(
            responseText: responseBuffer.toString(),
            reasoningText: reasoningBuffer.toString(),
          );
        }
        try {
          final payload = jsonDecode(data);
          if (payload is Map<String, dynamic>) {
            final extracted = LlmReasoningSupport.extractResponse(
              payload: payload,
              provider: provider,
            );
            if (extracted.responseText.isNotEmpty) {
              responseBuffer.write(extracted.responseText);
              onChunk(extracted.responseText);
            }
            if ((extracted.reasoningText ?? '').isNotEmpty) {
              reasoningBuffer.write(extracted.reasoningText);
            }
          }
        } catch (_) {
          continue;
        }
      }
    }
    return LlmPreparedResponse(
      responseText: responseBuffer.toString(),
      reasoningText: reasoningBuffer.toString(),
    );
  }

  String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Map<String, dynamic> _buildRequestBody({
    required LlmProvider provider,
    required String model,
    required String renderedPrompt,
    required int maxTokens,
    required String reasoningEffort,
    required bool stream,
  }) {
    final bodyMap = <String, dynamic>{
      'model': model,
      'messages': [
        {'role': 'user', 'content': renderedPrompt},
      ],
      if (stream) 'stream': true,
    };
    bodyMap[provider.maxTokensField(model)] = maxTokens;
    if (provider.apiFormat == LlmApiFormat.anthropicMessages) {
      bodyMap['messages'] = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content': renderedPrompt,
        },
      ];
    }
    LlmReasoningSupport.applyRequestFields(
      bodyMap: bodyMap,
      provider: provider,
      model: model,
      reasoningEffort: reasoningEffort,
      maxTokens: maxTokens,
    );
    return bodyMap;
  }

  Map<String, String> _buildHeaders({
    required LlmProvider provider,
    required String apiKey,
  }) {
    return <String, String>{
      'Content-Type': 'application/json',
      provider.authHeader: '${provider.authPrefix}$apiKey',
      ...provider.extraHeaders,
    };
  }

  Future<LlmPreparedResponse> _postAnthropicStream({
    required http.Client client,
    required String baseUrl,
    required LlmProvider provider,
    required String model,
    required String reasoningEffort,
    required String apiKey,
    required String renderedPrompt,
    required int timeoutSeconds,
    required int maxTokens,
    required bool Function() isCancelled,
    required void Function(String chunk) onChunk,
  }) async {
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}${provider.chatPath}');
    final request = http.Request('POST', url);
    request.headers.addAll(_buildHeaders(provider: provider, apiKey: apiKey));
    request.body = jsonEncode(
      _buildRequestBody(
        provider: provider,
        model: model,
        renderedPrompt: renderedPrompt,
        maxTokens: maxTokens,
        reasoningEffort: reasoningEffort,
        stream: true,
      ),
    );
    final response =
        await client.send(request).timeout(Duration(seconds: timeoutSeconds));

    if (isCancelled()) {
      throw StateError('Request cancelled.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw HttpException('HTTP ${response.statusCode}: $body');
    }

    final responseBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    String? eventType;
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
        line = line.trimRight();
        if (line.isEmpty) {
          eventType = null;
          continue;
        }
        if (line.startsWith('event:')) {
          eventType = line.substring(6).trim();
          continue;
        }
        if (!line.startsWith('data:')) {
          continue;
        }
        final data = line.substring(5).trim();
        if (data == '[DONE]') {
          return LlmPreparedResponse(
            responseText: responseBuffer.toString(),
            reasoningText: reasoningBuffer.toString(),
          );
        }
        try {
          final payload = jsonDecode(data);
          if (payload is! Map<String, dynamic>) {
            continue;
          }
          if (eventType == 'content_block_start' ||
              eventType == 'content_block_delta') {
            final extracted =
                LlmReasoningSupport.extractAnthropicEvent(payload);
            if (extracted.responseText.isNotEmpty) {
              responseBuffer.write(extracted.responseText);
              onChunk(extracted.responseText);
            }
            if ((extracted.reasoningText ?? '').isNotEmpty) {
              reasoningBuffer.write(extracted.reasoningText);
            }
            continue;
          }
          if (eventType == 'message_stop') {
            return LlmPreparedResponse(
              responseText: responseBuffer.toString(),
              reasoningText: reasoningBuffer.toString(),
            );
          }
        } catch (_) {
          continue;
        }
      }
    }
    return LlmPreparedResponse(
      responseText: responseBuffer.toString(),
      reasoningText: reasoningBuffer.toString(),
    );
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
