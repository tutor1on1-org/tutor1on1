import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/llm_call_repository.dart';
import '../services/llm_log_repository.dart';
import '../services/openai_codex_oauth_service.dart';
import '../services/secure_storage_service.dart';
import '../services/settings_repository.dart';
import '../services/transport_retry_policy.dart';
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
    this._validator, {
    http.Client Function()? clientFactory,
    OpenAiCodexOAuthService? codexOAuthService,
  })  : _clientFactory = clientFactory ?? (() => http.Client()),
        _codexOAuthService =
            codexOAuthService ?? OpenAiCodexOAuthService(_secureStorage);

  final SettingsRepository _settingsRepository;
  final SecureStorageService _secureStorage;
  final LlmCallRepository _callRepository;
  final LlmLogRepository _logRepository;
  final SchemaValidator _validator;
  final http.Client Function() _clientFactory;
  final OpenAiCodexOAuthService _codexOAuthService;

  LlmRequestHandle startCall({
    required String promptName,
    required String renderedPrompt,
    Map<String, dynamic>? schemaMap,
    String? conversationDigest,
    String? modelOverride,
    LlmCallContext? context,
  }) {
    final client = _clientFactory();
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
    final client = _clientFactory();
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

    final credential = await _resolveCredential(
      provider: provider,
      baseUrl: settings.baseUrl,
    );

    final stopwatch = Stopwatch()..start();
    try {
      final responseText = await _postChatCompletion(
        reasoningEffort: reasoningEffort,
        client: client,
        baseUrl: settings.baseUrl,
        provider: provider,
        promptName: promptName,
        model: modelToUse,
        credential: credential,
        renderedPrompt: renderedPrompt,
        schemaMap: schemaMap,
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

    final credential = await _resolveCredential(
      provider: provider,
      baseUrl: settings.baseUrl,
    );

    final stopwatch = Stopwatch()..start();
    try {
      final responseText = await _postChatCompletionStream(
        reasoningEffort: reasoningEffort,
        client: client,
        baseUrl: settings.baseUrl,
        provider: provider,
        promptName: promptName,
        model: modelToUse,
        credential: credential,
        renderedPrompt: renderedPrompt,
        schemaMap: schemaMap,
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

  Future<_LlmCredential> _resolveCredential({
    required LlmProvider provider,
    required String baseUrl,
  }) async {
    if (provider.usesOpenAiCodexOAuth) {
      final credentials = await _codexOAuthService.resolveValidCredentials();
      return _LlmCredential(
        accessToken: credentials.accessToken,
        codexAccountId: credentials.accountId,
      );
    }
    final apiKey = await _secureStorage.readApiKeyForBaseUrl(baseUrl);
    if ((apiKey ?? '').trim().isEmpty) {
      throw StateError('Missing API key. Set it in Settings.');
    }
    return _LlmCredential(accessToken: apiKey!.trim());
  }

  Future<LlmPreparedResponse> _postChatCompletion({
    required http.Client client,
    required String baseUrl,
    required LlmProvider provider,
    required String promptName,
    required String model,
    required String reasoningEffort,
    required _LlmCredential credential,
    required String renderedPrompt,
    required Map<String, dynamic>? schemaMap,
    required int timeoutSeconds,
    required int maxTokens,
    required bool Function() isCancelled,
  }) async {
    if (provider.apiFormat == LlmApiFormat.openAiCodexResponses) {
      return _postOpenAiCodexResponsesStream(
        reasoningEffort: reasoningEffort,
        client: client,
        baseUrl: baseUrl,
        provider: provider,
        promptName: promptName,
        model: model,
        credential: credential,
        renderedPrompt: renderedPrompt,
        schemaMap: schemaMap,
        timeoutSeconds: timeoutSeconds,
        maxTokens: maxTokens,
        isCancelled: isCancelled,
      );
    }
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}${provider.chatPath}');
    final bodyMap = _buildRequestBody(
      provider: provider,
      baseUrl: baseUrl,
      promptName: promptName,
      model: model,
      renderedPrompt: renderedPrompt,
      schemaMap: schemaMap,
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
            headers: _buildHeaders(
              provider: provider,
              credential: credential,
            ),
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
    required String promptName,
    required String model,
    required String reasoningEffort,
    required _LlmCredential credential,
    required String renderedPrompt,
    required Map<String, dynamic>? schemaMap,
    required int timeoutSeconds,
    required int maxTokens,
    required bool Function() isCancelled,
    required void Function(String chunk) onChunk,
  }) async {
    if (provider.apiFormat == LlmApiFormat.openAiCodexResponses) {
      return _postOpenAiCodexResponsesStream(
        reasoningEffort: reasoningEffort,
        client: client,
        baseUrl: baseUrl,
        provider: provider,
        promptName: promptName,
        model: model,
        credential: credential,
        renderedPrompt: renderedPrompt,
        schemaMap: schemaMap,
        timeoutSeconds: timeoutSeconds,
        maxTokens: maxTokens,
        isCancelled: isCancelled,
        onChunk: onChunk,
      );
    }
    if (provider.apiFormat == LlmApiFormat.anthropicMessages) {
      return _postAnthropicStream(
        client: client,
        baseUrl: baseUrl,
        provider: provider,
        promptName: promptName,
        model: model,
        reasoningEffort: reasoningEffort,
        credential: credential,
        renderedPrompt: renderedPrompt,
        schemaMap: schemaMap,
        timeoutSeconds: timeoutSeconds,
        maxTokens: maxTokens,
        isCancelled: isCancelled,
        onChunk: onChunk,
      );
    }
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}${provider.chatPath}');
    final bodyMap = _buildRequestBody(
      provider: provider,
      baseUrl: baseUrl,
      promptName: promptName,
      model: model,
      renderedPrompt: renderedPrompt,
      schemaMap: schemaMap,
      maxTokens: maxTokens,
      reasoningEffort: reasoningEffort,
      stream: true,
    );
    Future<http.StreamedResponse> send() {
      return client
          .send(
            _buildJsonPostRequest(
              url: url,
              headers: _buildHeaders(
                provider: provider,
                credential: credential,
              ),
              bodyMap: bodyMap,
            ),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    }

    final response = await _sendStreamWithRetry(
      send,
      isCancelled: isCancelled,
    );

    if (isCancelled()) {
      throw StateError('Request cancelled.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw HttpException('HTTP ${response.statusCode}: $body');
    }

    final responseBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    int? reasoningTokens;
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
            reasoningTokens: reasoningTokens,
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
              final delta =
                  LlmReasoningSupport.appendJsonAwareFragmentAndReturnDelta(
                responseBuffer,
                extracted.responseText,
              );
              if (delta.isNotEmpty) {
                onChunk(delta);
              }
            }
            if ((extracted.reasoningText ?? '').isNotEmpty) {
              LlmReasoningSupport.appendReasoningFragment(
                reasoningBuffer,
                extracted.reasoningText!,
              );
            }
            if (extracted.reasoningTokens != null) {
              reasoningTokens = extracted.reasoningTokens;
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
      reasoningTokens: reasoningTokens,
    );
  }

  Future<LlmPreparedResponse> _postOpenAiCodexResponsesStream({
    required http.Client client,
    required String baseUrl,
    required LlmProvider provider,
    required String promptName,
    required String model,
    required String reasoningEffort,
    required _LlmCredential credential,
    required String renderedPrompt,
    required Map<String, dynamic>? schemaMap,
    required int timeoutSeconds,
    required int maxTokens,
    required bool Function() isCancelled,
    void Function(String chunk)? onChunk,
  }) async {
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}${provider.chatPath}');
    final bodyMap = _buildOpenAiCodexResponsesBody(
      provider: provider,
      promptName: promptName,
      model: model,
      renderedPrompt: renderedPrompt,
      schemaMap: schemaMap,
      maxTokens: maxTokens,
      reasoningEffort: reasoningEffort,
    );
    Future<http.StreamedResponse> send() {
      return client
          .send(
            _buildJsonPostRequest(
              url: url,
              headers: _buildOpenAiCodexHeaders(credential),
              bodyMap: bodyMap,
            ),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    }

    final response = await _sendStreamWithRetry(
      send,
      isCancelled: isCancelled,
    );

    if (isCancelled()) {
      throw StateError('Request cancelled.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw HttpException('HTTP ${response.statusCode}: $body');
    }

    return _readOpenAiCodexSse(
      response: response,
      provider: provider,
      isCancelled: isCancelled,
      onChunk: onChunk,
    );
  }

  Map<String, dynamic> _buildOpenAiCodexResponsesBody({
    required LlmProvider provider,
    required String promptName,
    required String model,
    required String renderedPrompt,
    required Map<String, dynamic>? schemaMap,
    required int maxTokens,
    required String reasoningEffort,
  }) {
    final bodyMap = <String, dynamic>{
      'model': model,
      'store': false,
      'stream': true,
      'text': <String, dynamic>{
        'verbosity': 'medium',
      },
      'input': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, String>>[
            <String, String>{
              'type': 'input_text',
              'text': renderedPrompt,
            },
          ],
        },
      ],
      'max_output_tokens': maxTokens,
    };
    final normalizedEffort =
        LlmReasoningSupport.normalizeEffort(reasoningEffort);
    if (normalizedEffort != ReasoningEffort.none) {
      bodyMap['reasoning'] = <String, dynamic>{
        'effort': normalizedEffort,
        'summary': 'auto',
      };
    }
    if (_shouldUseOpenAiStructuredOutputs(
      provider: provider,
      baseUrl: OpenAiCodexOAuthService.baseUrl,
      schemaMap: schemaMap,
    )) {
      final text = bodyMap['text'] as Map<String, dynamic>;
      text['format'] = <String, dynamic>{
        'type': 'json_schema',
        'name': _buildStructuredOutputName(promptName),
        'strict': true,
        'schema': _stripSchemaMeta(schemaMap!),
      };
    }
    return bodyMap;
  }

  Map<String, String> _buildOpenAiCodexHeaders(_LlmCredential credential) {
    final accountId = credential.codexAccountId?.trim() ?? '';
    if (accountId.isEmpty) {
      throw StateError('ChatGPT OAuth token is missing account id.');
    }
    return <String, String>{
      'Authorization': 'Bearer ${credential.accessToken}',
      'chatgpt-account-id': accountId,
      'originator': 'pi',
      'OpenAI-Beta': 'responses=experimental',
      'Accept': 'text/event-stream',
      'Content-Type': 'application/json',
    };
  }

  Future<LlmPreparedResponse> _readOpenAiCodexSse({
    required http.StreamedResponse response,
    required LlmProvider provider,
    required bool Function() isCancelled,
    void Function(String chunk)? onChunk,
  }) async {
    final responseBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    Map<String, dynamic>? finalPayload;
    var pending = '';
    final stream = response.stream.transform(utf8.decoder);
    await for (final chunk in stream) {
      if (isCancelled()) {
        throw StateError('Request cancelled.');
      }
      pending += chunk.replaceAll('\r\n', '\n');
      while (true) {
        final eventBreak = pending.indexOf('\n\n');
        if (eventBreak == -1) {
          break;
        }
        final event = pending.substring(0, eventBreak);
        pending = pending.substring(eventBreak + 2);
        final data = _extractSseData(event);
        if (data == null || data.isEmpty) {
          continue;
        }
        if (data == '[DONE]') {
          return _finalizeOpenAiCodexResponse(
            provider: provider,
            responseBuffer: responseBuffer,
            reasoningBuffer: reasoningBuffer,
            finalPayload: finalPayload,
          );
        }
        final decoded = jsonDecode(data);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final type = (decoded['type'] as String?)?.trim() ?? '';
        if (type == 'error') {
          throw StateError(
            'Codex error: ${decoded['message'] ?? jsonEncode(decoded)}',
          );
        }
        if (type == 'response.failed') {
          final responseObject = decoded['response'];
          final message = responseObject is Map<String, dynamic>
              ? responseObject['error']?.toString()
              : null;
          throw StateError(message ?? 'Codex response failed.');
        }
        if (type == 'response.output_text.delta') {
          final delta = (decoded['delta'] as String?) ?? '';
          if (delta.isNotEmpty) {
            final normalized =
                LlmReasoningSupport.appendJsonAwareFragmentAndReturnDelta(
              responseBuffer,
              delta,
            );
            if (normalized.isNotEmpty) {
              onChunk?.call(normalized);
            }
          }
          continue;
        }
        if (type == 'response.reasoning_summary_text.delta' ||
            type == 'response.reasoning_text.delta') {
          final delta = (decoded['delta'] as String?) ?? '';
          LlmReasoningSupport.appendReasoningFragment(reasoningBuffer, delta);
          continue;
        }
        if (type == 'response.completed' ||
            type == 'response.done' ||
            type == 'response.incomplete') {
          final responseObject = decoded['response'];
          if (responseObject is Map<String, dynamic>) {
            finalPayload = responseObject;
          }
        }
      }
    }
    return _finalizeOpenAiCodexResponse(
      provider: provider,
      responseBuffer: responseBuffer,
      reasoningBuffer: reasoningBuffer,
      finalPayload: finalPayload,
    );
  }

  String? _extractSseData(String event) {
    final lines = event.split('\n');
    final dataLines = <String>[];
    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.startsWith('data:')) {
        dataLines.add(trimmed.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) {
      return null;
    }
    return dataLines.join('\n').trim();
  }

  LlmPreparedResponse _finalizeOpenAiCodexResponse({
    required LlmProvider provider,
    required StringBuffer responseBuffer,
    required StringBuffer reasoningBuffer,
    required Map<String, dynamic>? finalPayload,
  }) {
    var responseText = responseBuffer.toString();
    var reasoningText = reasoningBuffer.toString();
    int? reasoningTokens;
    if (finalPayload != null) {
      final extracted = LlmReasoningSupport.extractResponse(
        payload: finalPayload,
        provider: provider,
      );
      if (responseText.trim().isEmpty) {
        responseText = extracted.responseText;
      }
      if (reasoningText.trim().isEmpty) {
        reasoningText = extracted.reasoningText ?? '';
      }
      reasoningTokens = extracted.reasoningTokens;
    }
    if (responseText.trim().isEmpty) {
      throw StateError('LLM response missing content.');
    }
    return LlmPreparedResponse(
      responseText: responseText,
      reasoningText: reasoningText.trim().isEmpty ? null : reasoningText,
      reasoningTokens: reasoningTokens,
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
    required String baseUrl,
    required String promptName,
    required String model,
    required String renderedPrompt,
    required Map<String, dynamic>? schemaMap,
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
    } else if (stream && provider.id == 'openai') {
      bodyMap['stream_options'] = <String, dynamic>{
        'include_usage': true,
      };
    }
    if (_shouldUseOpenAiStructuredOutputs(
      provider: provider,
      baseUrl: baseUrl,
      schemaMap: schemaMap,
    )) {
      bodyMap['response_format'] = <String, dynamic>{
        'type': 'json_schema',
        'json_schema': <String, dynamic>{
          'name': _buildStructuredOutputName(promptName),
          'strict': true,
          'schema': _stripSchemaMeta(schemaMap!),
        },
      };
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
    required _LlmCredential credential,
  }) {
    return <String, String>{
      'Content-Type': 'application/json',
      provider.authHeader: '${provider.authPrefix}${credential.accessToken}',
      ...provider.extraHeaders,
    };
  }

  http.Request _buildJsonPostRequest({
    required Uri url,
    required Map<String, String> headers,
    required Map<String, dynamic> bodyMap,
  }) {
    final request = http.Request('POST', url);
    request.headers.addAll(headers);
    request.body = jsonEncode(bodyMap);
    return request;
  }

  Future<LlmPreparedResponse> _postAnthropicStream({
    required http.Client client,
    required String baseUrl,
    required LlmProvider provider,
    required String promptName,
    required String model,
    required String reasoningEffort,
    required _LlmCredential credential,
    required String renderedPrompt,
    required Map<String, dynamic>? schemaMap,
    required int timeoutSeconds,
    required int maxTokens,
    required bool Function() isCancelled,
    required void Function(String chunk) onChunk,
  }) async {
    final url = Uri.parse('${_normalizeBaseUrl(baseUrl)}${provider.chatPath}');
    Future<http.StreamedResponse> send() {
      return client
          .send(
            _buildJsonPostRequest(
              url: url,
              headers: _buildHeaders(
                provider: provider,
                credential: credential,
              ),
              bodyMap: _buildRequestBody(
                provider: provider,
                baseUrl: baseUrl,
                promptName: promptName,
                model: model,
                renderedPrompt: renderedPrompt,
                schemaMap: schemaMap,
                maxTokens: maxTokens,
                reasoningEffort: reasoningEffort,
                stream: true,
              ),
            ),
          )
          .timeout(Duration(seconds: timeoutSeconds));
    }

    final response = await _sendStreamWithRetry(
      send,
      isCancelled: isCancelled,
    );

    if (isCancelled()) {
      throw StateError('Request cancelled.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw HttpException('HTTP ${response.statusCode}: $body');
    }

    final responseBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    int? reasoningTokens;
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
            reasoningTokens: reasoningTokens,
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
              final delta =
                  LlmReasoningSupport.appendJsonAwareFragmentAndReturnDelta(
                responseBuffer,
                extracted.responseText,
              );
              if (delta.isNotEmpty) {
                onChunk(delta);
              }
            }
            if ((extracted.reasoningText ?? '').isNotEmpty) {
              LlmReasoningSupport.appendReasoningFragment(
                reasoningBuffer,
                extracted.reasoningText!,
              );
            }
            if (extracted.reasoningTokens != null) {
              reasoningTokens = extracted.reasoningTokens;
            }
            continue;
          }
          if (eventType == 'message_stop') {
            return LlmPreparedResponse(
              responseText: responseBuffer.toString(),
              reasoningText: reasoningBuffer.toString(),
              reasoningTokens: reasoningTokens,
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
      reasoningTokens: reasoningTokens,
    );
  }

  Future<http.Response> _sendWithRetry(
    Future<http.Response> Function() request, {
    required bool Function() isCancelled,
  }) async {
    return _sendWithOneRetry(
      request,
      isCancelled: isCancelled,
      statusCodeOf: (response) => response.statusCode,
    );
  }

  Future<http.StreamedResponse> _sendStreamWithRetry(
    Future<http.StreamedResponse> Function() request, {
    required bool Function() isCancelled,
  }) async {
    return _sendWithOneRetry(
      request,
      isCancelled: isCancelled,
      statusCodeOf: (response) => response.statusCode,
      disposeBeforeRetry: (response) => response.stream.drain(),
    );
  }

  Future<T> _sendWithOneRetry<T>(
    Future<T> Function() request, {
    required bool Function() isCancelled,
    required int Function(T response) statusCodeOf,
    Future<void> Function(T response)? disposeBeforeRetry,
  }) async {
    T response;
    try {
      response = await request();
    } on Exception catch (e) {
      if (isCancelled()) {
        rethrow;
      }
      if (isRetryableTransportException(e)) {
        return request();
      }
      rethrow;
    }

    if (isCancelled()) {
      return response;
    }

    if (isRetryableHttpStatus(statusCodeOf(response))) {
      await disposeBeforeRetry?.call(response);
      if (isCancelled()) {
        return response;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      if (isCancelled()) {
        return response;
      }
      response = await request();
    }
    return response;
  }

  bool _shouldUseOpenAiStructuredOutputs({
    required LlmProvider provider,
    required String baseUrl,
    required Map<String, dynamic>? schemaMap,
  }) {
    if (schemaMap == null) {
      return false;
    }
    if (provider.apiFormat != LlmApiFormat.openAiChatCompletions &&
        provider.apiFormat != LlmApiFormat.openAiCodexResponses) {
      return false;
    }
    if (!provider.supportsStructuredOutputs) {
      return false;
    }
    return _normalizeBaseUrl(baseUrl).isNotEmpty;
  }

  String _buildStructuredOutputName(String promptName) {
    final normalized = promptName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? 'structured_output' : '${normalized}_output';
  }

  Map<String, dynamic> _stripSchemaMeta(Map<String, dynamic> schemaMap) {
    final stripped = Map<String, dynamic>.from(schemaMap);
    stripped.remove(r'$schema');
    return stripped;
  }
}

class _LlmCredential {
  const _LlmCredential({
    required this.accessToken,
    this.codexAccountId,
  });

  final String accessToken;
  final String? codexAccountId;
}
