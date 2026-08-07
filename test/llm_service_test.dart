import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/llm/llm_models.dart';
import 'package:tutor1on1/llm/llm_service.dart';
import 'package:tutor1on1/llm/schema_validator.dart';
import 'package:tutor1on1/services/llm_call_repository.dart';
import 'package:tutor1on1/services/llm_log_repository.dart';
import 'package:tutor1on1/services/openai_codex_oauth_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';
import 'package:tutor1on1/services/settings_repository.dart';

class _FakeSecureStorage implements SecureStorageService {
  final Map<String, String> values = <String, String>{
    'auth:access': 'tutor-access-token',
  };

  @override
  int? get boundAuthRemoteUserId => null;

  @override
  Future<String?> readApiKeyForBaseUrl(String baseUrl) async => 'test-api-key';

  @override
  Future<String?> readAuthAccessToken() async => values['auth:access'];

  @override
  Future<String?> readAuthRefreshToken() async => values['auth:refresh'];

  @override
  Future<void> writeAuthTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    values['auth:access'] = accessToken;
    values['auth:refresh'] = refreshToken;
  }

  @override
  Future<String?> readOAuthCredentials(String providerId) async {
    return values['oauth:$providerId'];
  }

  @override
  Future<void> writeOAuthCredentials(String providerId, String value) async {
    values['oauth:$providerId'] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCodexOAuthService extends OpenAiCodexOAuthService {
  _FakeCodexOAuthService(
    SecureStorageService secureStorage,
    this.credentials,
  ) : super(secureStorage);

  final OpenAiCodexOAuthCredentials credentials;

  @override
  Future<OpenAiCodexOAuthCredentials> resolveValidCredentials() async {
    return credentials;
  }
}

class _FakeLlmLogRepository implements LlmLogRepository {
  final List<String> statuses = <String>[];
  final List<String?> parseErrors = <String?>[];

  @override
  Future<void> appendEntry({
    required String promptName,
    required String model,
    required String baseUrl,
    required String mode,
    required String status,
    String? callHash,
    int? latencyMs,
    bool? parseValid,
    String? parseError,
    int? teacherId,
    int? studentId,
    int? courseVersionId,
    int? sessionId,
    String? kpKey,
    String? action,
    int? attempt,
    String? retryReason,
    int? backoffMs,
    int? renderedChars,
    int? responseChars,
    String? reasoningText,
    bool? dbWriteOk,
    bool? uiCommitOk,
  }) async {
    statuses.add(status);
    parseErrors.add(parseError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _seedSettings(
  AppDatabase db, {
  String providerId = 'openai',
  String baseUrl = 'https://api.openai.com/v1',
  String model = 'gpt-4o-mini',
  String reasoningEffort = 'medium',
}) async {
  await db.into(db.appSettings).insert(
        AppSettingsCompanion.insert(
          baseUrl: baseUrl,
          providerId: Value(providerId),
          model: model,
          reasoningEffort: Value(reasoningEffort),
          timeoutSeconds: 30,
          maxTokens: 4000,
          ttsInitialDelayMs: const Value(1000),
          ttsTextLeadMs: const Value(1000),
          ttsAudioPath: const Value(r'C:\tutor1on1\logs'),
          sttAutoSend: const Value(false),
          enterToSend: const Value(true),
          studyModeEnabled: const Value(false),
          logDirectory: const Value(r'C:\tutor1on1\logs'),
          llmLogPath: const Value(r'C:\tutor1on1\logs\llm_logs.jsonl'),
          ttsLogPath: const Value(r'C:\tutor1on1\logs\tts_logs.jsonl'),
          llmMode: 'LIVE',
          locale: const Value('en'),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeLlmLogRepository logRepository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await _seedSettings(db);
    logRepository = _FakeLlmLogRepository();
  });

  tearDown(() async {
    await db.close();
  });

  test('streaming chat retry recovers from one browser transport failure',
      () async {
    var requestCount = 0;
    final service = LlmService(
      SettingsRepository(db),
      _FakeSecureStorage(),
      LlmCallRepository(db),
      logRepository,
      SchemaValidator(),
      clientFactory: () => MockClient((request) async {
        requestCount += 1;
        expect(request.method, equals('POST'));
        expect(request.url.toString(),
            equals('https://api.openai.com/v1/chat/completions'));
        expect(jsonDecode(request.body), containsPair('stream', true));
        if (requestCount == 1) {
          throw http.ClientException(
            'Browser transport failed',
          );
        }
        return http.Response(
          'data: {"choices":[{"delta":{"content":"Recovered"}}]}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: <String, String>{
            'content-type': 'text/event-stream',
          },
        );
      }),
    );

    final chunks = <String>[];
    final handle = service.startStreamingCall(
      promptName: 'learn',
      renderedPrompt: 'Explain fractions.',
      onChunk: chunks.add,
    );

    final result = await handle.future;

    expect(requestCount, equals(2));
    expect(chunks, equals(<String>['Recovered']));
    expect(result.responseText, equals('Recovered'));
    expect(logRepository.statuses, equals(<String>['ok']));
  });

  test('OpenAI Codex OAuth streams through authenticated Tutor relay',
      () async {
    await db.delete(db.appSettings).go();
    await _seedSettings(
      db,
      providerId: 'openai-codex',
      baseUrl: OpenAiCodexOAuthService.baseUrl,
      model: 'gpt-5.5',
    );
    final storage = _FakeSecureStorage();
    final credentials = OpenAiCodexOAuthCredentials(
      accessToken: 'openai-access-token',
      refreshToken: 'openai-refresh-token',
      expiresAtMs: 4102444800000,
      accountId: 'acct_123',
      email: 'user@example.com',
    );
    await OpenAiCodexOAuthService(storage).writeCredentials(credentials);
    final service = LlmService(
      SettingsRepository(db),
      storage,
      LlmCallRepository(db),
      logRepository,
      SchemaValidator(),
      codexOAuthService: _FakeCodexOAuthService(storage, credentials),
      clientFactory: () => MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(
          request.url.toString(),
          equals(
            'https://api.tutor1on1.org'
            '/api/llm/openai-codex/responses',
          ),
        );
        expect(
          request.headers['authorization'],
          equals('Bearer tutor-access-token'),
        );
        expect(
          request.headers['x-openai-oauth-token'],
          equals('openai-access-token'),
        );
        expect(request.headers['x-openai-account-id'], equals('acct_123'));
        expect(request.headers.values, isNot(contains('openai-refresh-token')));
        expect(request.headers, isNot(contains('chatgpt-account-id')));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], equals('gpt-5.5'));
        expect(body['stream'], isTrue);
        expect(body['store'], isFalse);
        expect(body, isNot(contains('max_output_tokens')));
        expect((body['instructions'] as String).trim(), isNotEmpty);
        expect(request.body, isNot(contains('openai-access-token')));
        expect(request.body, isNot(contains('openai-refresh-token')));
        final input = body['input'] as List<dynamic>;
        final firstInput = input.single as Map<String, dynamic>;
        final content = firstInput['content'] as List<dynamic>;
        expect(
          (content.single as Map<String, dynamic>)['text'],
          equals('Explain fractions.'),
        );
        return http.Response(
          'data: {"type":"response.output_text.delta","delta":"OAuth"}\r\n\r\n'
          'data: {"type":"response.output_text.delta","delta":" result"}\r\n\r\n'
          'data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"OAuth result"}]}]}}\r\n\r\n',
          200,
          headers: const <String, String>{
            'content-type': 'text/event-stream',
          },
        );
      }),
    );

    final chunks = <String>[];
    final handle = service.startStreamingCall(
      promptName: 'learn',
      renderedPrompt: 'Explain fractions.',
      onChunk: chunks.add,
    );

    final result = await handle.future;

    expect(chunks, equals(<String>['OAuth', ' result']));
    expect(result.responseText, equals('OAuth result'));
    expect(logRepository.statuses, equals(<String>['ok']));
    expect(
      logRepository.parseErrors.join('\n'),
      isNot(contains('openai-access-token')),
    );
  });

  test('OpenAI Codex relay refreshes expired Tutor auth once', () async {
    await db.delete(db.appSettings).go();
    await _seedSettings(
      db,
      providerId: 'openai-codex',
      baseUrl: OpenAiCodexOAuthService.baseUrl,
      model: 'gpt-5.5',
    );
    final storage = _FakeSecureStorage()
      ..values['auth:access'] = 'expired-tutor-token'
      ..values['auth:refresh'] = 'tutor-refresh-token';
    const credentials = OpenAiCodexOAuthCredentials(
      accessToken: 'openai-access-token',
      refreshToken: 'openai-refresh-token',
      expiresAtMs: 4102444800000,
      accountId: 'acct_123',
    );
    var relayCalls = 0;
    var refreshCalls = 0;
    final service = LlmService(
      SettingsRepository(db),
      storage,
      LlmCallRepository(db),
      logRepository,
      SchemaValidator(),
      codexOAuthService: _FakeCodexOAuthService(storage, credentials),
      clientFactory: () => MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          refreshCalls += 1;
          expect(
            jsonDecode(request.body),
            equals(<String, dynamic>{
              'refresh_token': 'tutor-refresh-token',
            }),
          );
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': 'fresh-tutor-token',
              'refresh_token': 'fresh-tutor-refresh-token',
            }),
            200,
          );
        }
        relayCalls += 1;
        expect(
          request.url.path,
          equals('/api/llm/openai-codex/responses'),
        );
        if (relayCalls == 1) {
          expect(
            request.headers['authorization'],
            equals('Bearer expired-tutor-token'),
          );
          return http.Response('{"error":"expired"}', 401);
        }
        expect(
          request.headers['authorization'],
          equals('Bearer fresh-tutor-token'),
        );
        return http.Response(
          'data: {"type":"response.output_text.delta","delta":"Retried"}\n\n'
          'data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"Retried"}]}]}}\n\n',
          200,
          headers: const <String, String>{
            'content-type': 'text/event-stream',
          },
        );
      }),
    );

    final result = await service
        .startStreamingCall(
          promptName: 'learn',
          renderedPrompt: 'Retry the relay.',
          onChunk: (_) {},
        )
        .future;

    expect(result.responseText, equals('Retried'));
    expect(relayCalls, equals(2));
    expect(refreshCalls, equals(1));
    expect(storage.values['auth:access'], equals('fresh-tutor-token'));
  });

  test('Agent Tutor sends model, max effort, and remote course context only',
      () async {
    await db.delete(db.appSettings).go();
    await _seedSettings(
      db,
      providerId: 'agent-tutor',
      baseUrl: 'https://api.tutor1on1.org',
      model: 'gpt-5.6-sol',
      reasoningEffort: 'max',
    );
    final service = LlmService(
      SettingsRepository(db),
      _FakeSecureStorage(),
      LlmCallRepository(db),
      logRepository,
      SchemaValidator(),
      appLabel: 'agent_tutor',
      clientFactory: () => MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(
          request.url.toString(),
          equals('https://api.tutor1on1.org/api/agent-tutor/turn'),
        );
        expect(
          request.headers['authorization'],
          equals('Bearer tutor-access-token'),
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['course_id'], equals(200));
        expect(body['bundle_version_id'], equals(501));
        expect(body['kp_key'], equals('2.1'));
        expect(body['action'], equals('review'));
        expect(body['prompt_name'], equals('review_init'));
        expect(body['model'], equals('gpt-5.6-sol'));
        expect(body['reasoning_effort'], equals('max'));
        expect(
          body['rendered_prompt'],
          contains('[[AGENT_TUTOR_SERVER_FILE:path=2.1/easy/questions.txt]]'),
        );
        expect(request.body, isNot(contains('raw private question')));
        return http.Response(
          jsonEncode(<String, dynamic>{
            'response_text': '{"teacher_message":"Server answer"}',
          }),
          200,
          headers: const <String, String>{
            'content-type': 'application/json',
          },
        );
      }),
    );

    final chunks = <String>[];
    final result = await service
        .startStreamingCall(
          promptName: 'review_init',
          renderedPrompt:
              '[[AGENT_TUTOR_SERVER_FILE:path=2.1/easy/questions.txt]]',
          schemaMap: const <String, dynamic>{'type': 'object'},
          context: const LlmCallContext(
            remoteCourseId: 200,
            remoteBundleVersionId: 501,
            kpKey: '2.1',
            action: 'review',
          ),
          onChunk: chunks.add,
        )
        .future;

    expect(result.responseText, contains('Server answer'));
    expect(chunks, equals(<String>[result.responseText]));
    expect(logRepository.statuses, equals(<String>['ok']));
  });
}
