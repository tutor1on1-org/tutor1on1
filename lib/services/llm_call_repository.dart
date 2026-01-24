import 'package:drift/drift.dart';

import '../db/app_database.dart';

class LlmCallRepository {
  LlmCallRepository(this._db);

  final AppDatabase _db;

  Future<LlmCall?> findByHash(String callHash) {
    return (_db.select(_db.llmCalls)
          ..where((tbl) => tbl.callHash.equals(callHash)))
        .getSingleOrNull();
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
  }) {
    return _db.into(_db.llmCalls).insert(
          LlmCallsCompanion.insert(
            callHash: callHash,
            promptName: promptName,
            renderedPrompt: renderedPrompt,
            model: model,
            baseUrl: baseUrl,
            responseText: Value(responseText),
            responseJson: Value(responseJson),
            parseValid: Value(parseValid),
            parseError: Value(parseError),
            latencyMs: Value(latencyMs),
            mode: mode,
            teacherId: Value(teacherId),
            studentId: Value(studentId),
            courseVersionId: Value(courseVersionId),
            sessionId: Value(sessionId),
            kpKey: Value(kpKey),
            action: Value(action),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }
}
