import 'dart:convert';

import 'package:crypto/crypto.dart';

String hashSessionSemanticContent({
  required String kpKey,
  required String sessionTitle,
  required String summaryText,
  required String controlStateJson,
  required String evidenceStateJson,
  required List<SessionSemanticMessageInput> messages,
}) {
  return _hashNormalized(
    <String, Object?>{
      'kp_key': _normalizeRequiredString(kpKey),
      'session_title': _normalizeOptionalString(sessionTitle),
      'summary_text': _normalizeOptionalString(summaryText),
      'control_state': _normalizeJsonText(controlStateJson),
      'evidence_state': _normalizeJsonText(evidenceStateJson),
      'messages': messages
          .map(
            (message) => _normalizeObject(
              <String, Object?>{
                'role': _normalizeRequiredString(message.role),
                'content': _normalizeRequiredString(message.content),
                'raw_content': _normalizeOptionalString(message.rawContent),
                'parsed_json': _normalizeJsonText(message.parsedJson),
                'action': _normalizeOptionalString(message.action),
              },
            ),
          )
          .toList(growable: false),
    },
  );
}

String hashSessionChapterSemanticContent(
  List<SessionChapterSemanticMemberInput> members,
) {
  final normalized = members
      .map(
        (member) => _normalizeObject(
          <String, Object?>{
            'sync_id': _normalizeRequiredString(member.syncId),
            'content_hash': _normalizeRequiredString(member.contentHash),
          },
        ),
      )
      .toList(growable: false)
    ..sort(_compareNormalizedJson);
  return _hashNormalized(normalized);
}

String hashProgressSemanticContent({
  required bool lit,
  required int litPercent,
  required String questionLevel,
  required int easyPassedCount,
  required int mediumPassedCount,
  required int hardPassedCount,
  required String summaryText,
  required String summaryRawResponse,
  required bool? summaryValid,
}) {
  final normalizedPassedCounts = _normalizeProgressPassedCounts(
    lit: lit,
    litPercent: litPercent,
    questionLevel: questionLevel,
    easyPassedCount: easyPassedCount,
    mediumPassedCount: mediumPassedCount,
    hardPassedCount: hardPassedCount,
  );
  return _hashNormalized(
    <String, Object?>{
      'lit': lit,
      'easy_passed_count': normalizedPassedCounts.easyPassedCount,
      'medium_passed_count': normalizedPassedCounts.mediumPassedCount,
      'hard_passed_count': normalizedPassedCounts.hardPassedCount,
      'summary_text': _normalizeOptionalString(summaryText),
      'summary_raw_response': _normalizeOptionalString(summaryRawResponse),
      'summary_valid': summaryValid,
    },
  );
}

String hashProgressChunkSemanticContent(
  List<ProgressChunkSemanticMemberInput> members,
) {
  final normalized = members
      .map(
        (member) => _normalizeObject(
          <String, Object?>{
            'kp_key': _normalizeRequiredString(member.kpKey),
            'content_hash': _normalizeRequiredString(member.contentHash),
          },
        ),
      )
      .toList(growable: false)
    ..sort(_compareNormalizedJson);
  return _hashNormalized(normalized);
}

class SessionSemanticMessageInput {
  const SessionSemanticMessageInput({
    required this.role,
    required this.content,
    this.rawContent,
    this.parsedJson,
    this.action,
  });

  final String role;
  final String content;
  final String? rawContent;
  final String? parsedJson;
  final String? action;
}

class SessionChapterSemanticMemberInput {
  const SessionChapterSemanticMemberInput({
    required this.syncId,
    required this.contentHash,
  });

  final String syncId;
  final String contentHash;
}

class ProgressChunkSemanticMemberInput {
  const ProgressChunkSemanticMemberInput({
    required this.kpKey,
    required this.contentHash,
  });

  final String kpKey;
  final String contentHash;
}

class _NormalizedProgressPassedCounts {
  const _NormalizedProgressPassedCounts({
    required this.easyPassedCount,
    required this.mediumPassedCount,
    required this.hardPassedCount,
  });

  final int easyPassedCount;
  final int mediumPassedCount;
  final int hardPassedCount;
}

String _hashNormalized(Object? value) {
  final normalized = _normalizeObject(value);
  return sha256.convert(utf8.encode(jsonEncode(normalized))).toString();
}

Object? _normalizeObject(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map) {
    final entries = value.entries
        .map(
          (entry) => MapEntry(
            entry.key.toString(),
            _normalizeObject(entry.value),
          ),
        )
        .where((entry) => entry.value != null)
        .toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return <String, Object?>{
      for (final entry in entries) entry.key: entry.value,
    };
  }
  if (value is List) {
    return value.map(_normalizeObject).where((item) => item != null).toList();
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return value;
}

String? _normalizeOptionalString(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

String _normalizeRequiredString(String value) {
  final trimmed = value.trim();
  return trimmed;
}

Object? _normalizeJsonText(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(trimmed);
    final normalized = _normalizeObject(decoded);
    if (normalized is Map && normalized.isEmpty) {
      return null;
    }
    if (normalized is List && normalized.isEmpty) {
      return null;
    }
    return normalized;
  } catch (_) {
    return trimmed;
  }
}

int _compareNormalizedJson(Object? left, Object? right) {
  return jsonEncode(left).compareTo(jsonEncode(right));
}

_NormalizedProgressPassedCounts _normalizeProgressPassedCounts({
  required bool lit,
  required int litPercent,
  required String questionLevel,
  required int easyPassedCount,
  required int mediumPassedCount,
  required int hardPassedCount,
}) {
  final easy = easyPassedCount < 0 ? 0 : easyPassedCount;
  final medium = mediumPassedCount < 0 ? 0 : mediumPassedCount;
  final hard = hardPassedCount < 0 ? 0 : hardPassedCount;
  if (easy > 0 || medium > 0 || hard > 0) {
    return _NormalizedProgressPassedCounts(
      easyPassedCount: easy,
      mediumPassedCount: medium,
      hardPassedCount: hard,
    );
  }
  switch (_resolveLegacyProgressLevel(
    lit: lit,
    litPercent: litPercent,
    questionLevel: questionLevel,
  )) {
    case 'hard':
      return const _NormalizedProgressPassedCounts(
        easyPassedCount: 0,
        mediumPassedCount: 0,
        hardPassedCount: 1,
      );
    case 'medium':
      return const _NormalizedProgressPassedCounts(
        easyPassedCount: 0,
        mediumPassedCount: 1,
        hardPassedCount: 0,
      );
    case 'easy':
      return const _NormalizedProgressPassedCounts(
        easyPassedCount: 1,
        mediumPassedCount: 0,
        hardPassedCount: 0,
      );
  }
  return const _NormalizedProgressPassedCounts(
    easyPassedCount: 0,
    mediumPassedCount: 0,
    hardPassedCount: 0,
  );
}

String? _resolveLegacyProgressLevel({
  required bool lit,
  required int litPercent,
  required String questionLevel,
}) {
  final normalizedLevel = _normalizeOptionalString(questionLevel);
  if (litPercent >= 100 || normalizedLevel == 'hard') {
    return 'hard';
  }
  if (litPercent >= 66 || normalizedLevel == 'medium') {
    return 'medium';
  }
  if (litPercent >= 33 || normalizedLevel == 'easy') {
    return 'easy';
  }
  if (lit) {
    return 'hard';
  }
  return null;
}
