import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'log_crypto_service.dart';

class LlmCallRepository {
  LlmCallRepository(
    this._db, {
    LogCryptoService? logCrypto,
  }) : _logCrypto = logCrypto ?? LogCryptoService.instance;

  final AppDatabase _db;
  final LogCryptoService _logCrypto;

  Future<LlmCall?> findByHash(String callHash) async {
    final record = await (_db.select(_db.llmCalls)
          ..where((tbl) => tbl.callHash.equals(callHash))
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
            (tbl) => OrderingTerm(
                  expression: tbl.id,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();
    if (record == null) {
      return null;
    }
    final renderedPrompt =
        await _logCrypto.decryptForCurrentUser(record.renderedPrompt);
    if (renderedPrompt == null) {
      return null;
    }
    final responseText =
        await _logCrypto.decryptForCurrentUser(record.responseText);
    if (record.responseText != null && responseText == null) {
      return null;
    }
    final responseJson =
        await _logCrypto.decryptForCurrentUser(record.responseJson);
    if (record.responseJson != null && responseJson == null) {
      return null;
    }
    final parseError =
        await _logCrypto.decryptForCurrentUser(record.parseError);
    if (record.parseError != null && parseError == null) {
      return null;
    }
    return record.copyWith(
      renderedPrompt: renderedPrompt,
      responseText: Value(responseText),
      responseJson: Value(responseJson),
      parseError: Value(parseError),
    );
  }

  Future<int> insert({
    required String callHash,
    required String promptName,
    required String renderedPrompt,
    required String model,
    required String baseUrl,
    required String responseText,
    String? responseJson,
    bool? parseValid,
    String? parseError,
    int? latencyMs,
    required String mode,
    int? teacherId,
    int? studentId,
    int? courseVersionId,
    int? sessionId,
    String? kpKey,
    String? action,
  }) async {
    final encryptedRenderedPrompt =
        await _logCrypto.encryptForCurrentUser(renderedPrompt);
    final encryptedResponseText =
        await _logCrypto.encryptForCurrentUser(responseText);
    final encryptedResponseJson = responseJson == null
        ? null
        : await _logCrypto.encryptForCurrentUser(responseJson);
    final encryptedParseError = parseError == null
        ? null
        : await _logCrypto.encryptForCurrentUser(parseError);
    return _db.into(_db.llmCalls).insert(
          LlmCallsCompanion.insert(
            callHash: callHash,
            promptName: promptName,
            renderedPrompt: encryptedRenderedPrompt,
            model: model,
            baseUrl: baseUrl,
            responseText: Value(encryptedResponseText),
            responseJson: Value(encryptedResponseJson),
            parseValid: Value(parseValid),
            parseError: Value(encryptedParseError),
            latencyMs: Value(latencyMs),
            mode: mode,
            teacherId: Value(teacherId),
            studentId: Value(studentId),
            courseVersionId: Value(courseVersionId),
            sessionId: Value(sessionId),
            kpKey: Value(kpKey),
            action: Value(action),
          ),
        );
  }
}
