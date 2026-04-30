import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/llm/llm_service.dart';
import 'package:tutor1on1/llm/schema_validator.dart';
import 'package:tutor1on1/services/llm_call_repository.dart';
import 'package:tutor1on1/services/llm_log_repository.dart';
import 'package:tutor1on1/services/openai_codex_oauth_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';
import 'package:tutor1on1/services/settings_repository.dart';

class _FakeSecureStorage implements SecureStorageService {
  @override
  Future<String?> readApiKeyForBaseUrl(String baseUrl) async => 'test-api-key';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCodexOAuthService extends OpenAiCodexOAuthService {
  _FakeCodexOAuthService(this.credentials) : super(_FakeSecureStorage());

  final OpenAiCodexOAuthCredentials credentials;

  @override
  Future<OpenAiCodexOAuthCredentials> resolveValidCredentials() async {
    return credentials;
  }
}

class _FakeLlmLogRepository implements LlmLogRepository {
  final List<String> statuses = <String>[];

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
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _seedSettings(
  AppDatabase db, {
  String providerId = 'openai',
  String baseUrl = 'https://api.openai.com/v1',
  String model = 'gpt-4o-mini',
}) async {
  await db.into(db.appSettings).insert(
        AppSettingsCompanion.insert(
          baseUrl: baseUrl,
          providerId: Value(providerId),
          model: model,
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

  test('streaming chat retry recovers from one handshake failure', () async {
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
          throw const HandshakeException(
            'Connection terminated during handshake',
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

  test('OpenAI Codex OAuth streams through Codex Responses endpoint', () async {
    await db.delete(db.appSettings).go();
    await _seedSettings(
      db,
      providerId: 'openai-codex',
      baseUrl: OpenAiCodexOAuthService.baseUrl,
      model: 'gpt-5.5',
    );

    final service = LlmService(
      SettingsRepository(db),
      _FakeSecureStorage(),
      LlmCallRepository(db),
      logRepository,
      SchemaValidator(),
      codexOAuthService: _FakeCodexOAuthService(
        OpenAiCodexOAuthCredentials(
          accessToken: 'oauth-access-token',
          refreshToken: 'oauth-refresh-token',
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + 3600000,
          accountId: 'acct_123',
          email: 'user@example.com',
        ),
      ),
      clientFactory: () => MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(
          request.url.toString(),
          equals('https://chatgpt.com/backend-api/codex/responses'),
        );
        final headers = <String, String>{
          for (final entry in request.headers.entries)
            entry.key.toLowerCase(): entry.value,
        };
        expect(headers['authorization'], equals('Bearer oauth-access-token'));
        expect(headers['chatgpt-account-id'], equals('acct_123'));
        expect(headers['originator'], equals('pi'));
        expect(headers['openai-beta'], equals('responses=experimental'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], equals('gpt-5.5'));
        expect(body['stream'], isTrue);
        expect(body['store'], isFalse);
        expect(body['max_output_tokens'], equals(4000));
        expect(body['instructions'], isA<String>());
        expect((body['instructions'] as String).trim(), isNotEmpty);
        expect(
          body['text'],
          containsPair('verbosity', 'medium'),
        );
        final input = body['input'] as List<dynamic>;
        final firstInput = input.single as Map<String, dynamic>;
        expect(firstInput['type'], equals('message'));
        final content = firstInput['content'] as List<dynamic>;
        expect(
          (content.single as Map<String, dynamic>)['text'],
          equals('Explain fractions.'),
        );
        return http.Response(
          'data: {"type":"response.output_text.delta","delta":"OAuth"}\r\n\r\n'
          'data: {"type":"response.output_text.delta","delta":" result"}\r\n\r\n'
          'data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"OAuth result"}]}]}}\r\n\r\n'
          'data: [DONE]\r\n\r\n',
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

    expect(chunks, equals(<String>['OAuth', ' result']));
    expect(result.responseText, equals('OAuth result'));
    expect(logRepository.statuses, equals(<String>['ok']));
  });
}
