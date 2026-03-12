import 'dart:convert';
import 'dart:io';

import 'package:family_teacher/services/log_crypto_service.dart';

Future<void> main() async {
  final path = Platform.environment['LLM_LOG_PATH']?.trim().isNotEmpty == true
      ? Platform.environment['LLM_LOG_PATH']!.trim()
      : r'C:\family_teacher\logs\llm_logs.jsonl';
  final userId = int.parse(
    Platform.environment['LOG_USER_ID'] ?? '6',
  );
  final role = Platform.environment['LOG_ROLE'] ?? 'student';
  final password = Platform.environment['LOG_PASSWORD'] ?? '1234';
  final sessionId = int.parse(
    Platform.environment['LOG_SESSION_ID'] ?? '71',
  );
  final kpKey = Platform.environment['LOG_KP_KEY'] ?? '4.1.2.2';

  final service = LogCryptoService.instance;
  await service.activate(userId: userId, role: role, password: password);
  final lines = File(path).readAsLinesSync();
  for (final line in lines) {
    if (line.trim().isEmpty) {
      continue;
    }
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) {
      continue;
    }
    if (decoded['owner_user_id'] != userId || decoded['owner_role'] != role) {
      continue;
    }
    if (decoded['session_id'] != sessionId || decoded['kp_key'] != kpKey) {
      continue;
    }
    Future<String?> decryptField(String key) async {
      return service.decryptForCurrentUser(decoded[key] as String?);
    }

    final row = <String, dynamic>{
      'created_at': decoded['created_at'],
      'prompt_name': await decryptField('prompt_name_enc'),
      'mode': await decryptField('mode_enc'),
      'status': await decryptField('status_enc'),
      'call_hash': await decryptField('call_hash_enc'),
      'parse_valid': decoded['parse_valid'],
      'parse_error': await decryptField('parse_error_enc'),
      'action': await decryptField('action_enc'),
      'attempt': decoded['attempt'],
      'retry_reason': await decryptField('retry_reason_enc'),
      'rendered_chars': decoded['rendered_chars'],
      'response_chars': decoded['response_chars'],
      'db_write_ok': decoded['db_write_ok'],
      'ui_commit_ok': decoded['ui_commit_ok'],
    };
    stdout.writeln(jsonEncode(row));
  }
}
