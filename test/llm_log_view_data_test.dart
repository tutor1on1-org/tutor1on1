import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/ui/pages/llm_log_view_data.dart';

void main() {
  test(
      'groups APP retry rows with surrounding model attempts for one logical call',
      () {
    final baseTime = DateTime.utc(2026, 3, 17, 0, 0, 0);
    final entries = buildLlmLogViewEntries(
      dbAttempts: [
        LlmLogDbAttemptInput(
          createdAt: baseTime.add(const Duration(seconds: 1)),
          callHash: 'same_hash',
          promptName: 'review',
          renderedPrompt: 'prompt',
          model: 'gpt-test',
          baseUrl: 'https://example.com/v1',
          responseText: '{"text":"first"}',
          responseJson: '{"text":"first"}',
          parseValid: false,
          parseError: 'bad schema',
          latencyMs: 1200,
          teacherId: 1,
          studentId: 2,
          courseVersionId: 3,
          sessionId: 4,
          kpKey: '1.2.3',
          action: 'review',
          mode: 'LIVE_RECORD',
          teacherName: 'teacher_a',
          studentName: 'student_a',
        ),
        LlmLogDbAttemptInput(
          createdAt: baseTime.add(const Duration(seconds: 3)),
          callHash: 'same_hash',
          promptName: 'review',
          renderedPrompt: 'prompt',
          model: 'gpt-test',
          baseUrl: 'https://example.com/v1',
          responseText: '{"text":"second"}',
          responseJson: '{"text":"second"}',
          parseValid: true,
          parseError: null,
          latencyMs: 900,
          teacherId: 1,
          studentId: 2,
          courseVersionId: 3,
          sessionId: 4,
          kpKey: '1.2.3',
          action: 'review',
          mode: 'LIVE_RECORD',
          teacherName: 'teacher_a',
          studentName: 'student_a',
        ),
      ],
      fileEvents: [
        LlmLogFileEventInput(
          createdAt: baseTime.add(const Duration(seconds: 1)),
          promptName: 'review',
          model: 'gpt-test',
          baseUrl: 'https://example.com/v1',
          mode: 'LIVE_RECORD',
          status: 'ok',
          callHash: 'same_hash',
          metadata: <String, dynamic>{
            'source': 'llm_jsonl',
            'latency_ms': 1200,
            'reasoning_text':
                '{"provider_id":"openai","reasoning_text":"first think"}',
          },
        ),
        LlmLogFileEventInput(
          createdAt: baseTime.add(const Duration(seconds: 2)),
          promptName: 'review',
          model: 'gpt-test',
          baseUrl: 'https://example.com/v1',
          mode: 'APP',
          status: 'retry',
          callHash: 'same_hash',
          metadata: const <String, dynamic>{
            'source': 'llm_jsonl',
            'retry_reason': 'structured_parse_retry',
          },
        ),
        LlmLogFileEventInput(
          createdAt: baseTime.add(const Duration(seconds: 3)),
          promptName: 'review',
          model: 'gpt-test',
          baseUrl: 'https://example.com/v1',
          mode: 'LIVE_RECORD',
          status: 'ok',
          callHash: 'same_hash',
          metadata: const <String, dynamic>{
            'source': 'llm_jsonl',
            'latency_ms': 900,
          },
        ),
      ],
    );

    expect(entries, hasLength(1));
    expect(entries.single.events, hasLength(3));
    expect(
      entries.single.events.map((event) => event.mode).toList(),
      equals(['LIVE_RECORD', 'APP', 'LIVE_RECORD']),
    );
    expect(entries.single.teacherName, equals('teacher_a'));
    final detail = entries.single.toJsonRecord();
    final events = detail['events'] as List<dynamic>;
    final firstEvent = events.first as Map<String, dynamic>;
    expect(firstEvent['response_text'], isA<Map<String, dynamic>>());
    expect(
      (firstEvent['metadata'] as Map<String, dynamic>)['reasoning_text'],
      isA<Map<String, dynamic>>(),
    );
    final exchange = entries.single.toExchangeRecord();
    final attempts = exchange['attempts'] as List<dynamic>;
    expect(attempts, hasLength(2));
    final firstAttempt = attempts.first as Map<String, dynamic>;
    expect(firstAttempt['request'], equals('prompt'));
    expect(firstAttempt['response'], isA<Map<String, dynamic>>());
    expect(firstAttempt['reasoning'], equals('first think'));
    expect(firstAttempt.containsKey('response_json'), isFalse);
    expect(firstAttempt.containsKey('metadata'), isFalse);
  });

  test(
      'keeps repeated same-hash model executions as separate viewer entries without APP bridge',
      () {
    final baseTime = DateTime.utc(2026, 3, 17, 0, 0, 0);
    final entries = buildLlmLogViewEntries(
      dbAttempts: [
        LlmLogDbAttemptInput(
          createdAt: baseTime.add(const Duration(seconds: 1)),
          callHash: 'same_hash',
          promptName: 'review',
          renderedPrompt: 'prompt',
          model: 'gpt-test',
          baseUrl: 'https://example.com/v1',
          responseText: '{"text":"first"}',
          responseJson: '{"text":"first"}',
          parseValid: true,
          parseError: null,
          latencyMs: 700,
          teacherId: 1,
          studentId: 2,
          courseVersionId: 3,
          sessionId: 4,
          kpKey: '1.2.3',
          action: 'review',
          mode: 'LIVE_RECORD',
          teacherName: 'teacher_a',
          studentName: 'student_a',
        ),
        LlmLogDbAttemptInput(
          createdAt: baseTime.add(const Duration(seconds: 5)),
          callHash: 'same_hash',
          promptName: 'review',
          renderedPrompt: 'prompt',
          model: 'gpt-test',
          baseUrl: 'https://example.com/v1',
          responseText: '{"text":"second"}',
          responseJson: '{"text":"second"}',
          parseValid: true,
          parseError: null,
          latencyMs: 650,
          teacherId: 1,
          studentId: 2,
          courseVersionId: 3,
          sessionId: 4,
          kpKey: '1.2.3',
          action: 'review',
          mode: 'LIVE_RECORD',
          teacherName: 'teacher_a',
          studentName: 'student_a',
        ),
      ],
      fileEvents: [
        LlmLogFileEventInput(
          createdAt: baseTime.add(const Duration(seconds: 1)),
          promptName: 'review',
          model: 'gpt-test',
          baseUrl: 'https://example.com/v1',
          mode: 'LIVE_RECORD',
          status: 'ok',
          callHash: 'same_hash',
          metadata: const <String, dynamic>{
            'source': 'llm_jsonl',
            'latency_ms': 700,
          },
        ),
        LlmLogFileEventInput(
          createdAt: baseTime.add(const Duration(seconds: 5)),
          promptName: 'review',
          model: 'gpt-test',
          baseUrl: 'https://example.com/v1',
          mode: 'LIVE_RECORD',
          status: 'ok',
          callHash: 'same_hash',
          metadata: const <String, dynamic>{
            'source': 'llm_jsonl',
            'latency_ms': 650,
          },
        ),
      ],
    );

    expect(entries, hasLength(2));
    expect(entries[0].events, hasLength(1));
    expect(entries[1].events, hasLength(1));
    expect(entries[0].createdAt, baseTime.add(const Duration(seconds: 5)));
    expect(entries[1].createdAt, baseTime.add(const Duration(seconds: 1)));
  });
}
