import 'dart:convert';

class LlmLogDbAttemptInput {
  LlmLogDbAttemptInput({
    required this.createdAt,
    required this.callHash,
    required this.promptName,
    required this.renderedPrompt,
    required this.model,
    required this.baseUrl,
    required this.responseText,
    required this.responseJson,
    required this.parseValid,
    required this.parseError,
    required this.latencyMs,
    required this.teacherId,
    required this.studentId,
    required this.courseVersionId,
    required this.sessionId,
    required this.kpKey,
    required this.action,
    required this.mode,
    required this.teacherName,
    required this.studentName,
  });

  final DateTime createdAt;
  final String callHash;
  final String promptName;
  final String renderedPrompt;
  final String model;
  final String baseUrl;
  final String? responseText;
  final String? responseJson;
  final bool? parseValid;
  final String? parseError;
  final int? latencyMs;
  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? sessionId;
  final String? kpKey;
  final String? action;
  final String mode;
  final String? teacherName;
  final String? studentName;
}

class LlmLogFileEventInput {
  LlmLogFileEventInput({
    required this.createdAt,
    required this.promptName,
    required this.model,
    required this.baseUrl,
    required this.mode,
    required this.status,
    required this.metadata,
    this.callHash,
    this.parseValid,
    this.parseError,
    this.teacherId,
    this.studentId,
    this.teacherName,
    this.studentName,
    this.courseVersionId,
    this.sessionId,
    this.kpKey,
    this.action,
  });

  final DateTime createdAt;
  final String promptName;
  final String model;
  final String baseUrl;
  final String mode;
  final String status;
  final String? callHash;
  final bool? parseValid;
  final String? parseError;
  final int? teacherId;
  final int? studentId;
  final String? teacherName;
  final String? studentName;
  final int? courseVersionId;
  final int? sessionId;
  final String? kpKey;
  final String? action;
  final Map<String, dynamic> metadata;
}

class LlmLogViewEvent {
  LlmLogViewEvent({
    required this.createdAt,
    required this.promptName,
    required this.model,
    required this.baseUrl,
    required this.mode,
    required this.status,
    required this.callHash,
    required this.metadata,
    this.teacherId,
    this.studentId,
    this.courseVersionId,
    this.sessionId,
    this.kpKey,
    this.action,
    this.teacherName,
    this.studentName,
    this.renderedPrompt,
    this.responseText,
    this.responseJson,
    this.parseValid,
    this.parseError,
  });

  final DateTime createdAt;
  final String promptName;
  final String model;
  final String baseUrl;
  final String mode;
  final String status;
  final String callHash;
  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? sessionId;
  final String? kpKey;
  final String? action;
  final String? teacherName;
  final String? studentName;
  final String? renderedPrompt;
  final String? responseText;
  final String? responseJson;
  final bool? parseValid;
  final String? parseError;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJsonRecord() {
    final record = <String, dynamic>{};
    _put(record, 'created_at', createdAt.toIso8601String());
    _put(record, 'prompt_name', promptName);
    _put(record, 'model', model);
    _put(record, 'base_url', baseUrl);
    _put(record, 'mode', mode);
    _put(record, 'status', status);
    _put(record, 'call_hash', callHash);
    _put(record, 'teacher_id', teacherId);
    _put(record, 'teacher_name', teacherName);
    _put(record, 'student_id', studentId);
    _put(record, 'student_name', studentName);
    _put(record, 'course_version_id', courseVersionId);
    _put(record, 'session_id', sessionId);
    _put(record, 'kp_key', kpKey);
    _put(record, 'action', action);
    _put(record, 'parse_valid', parseValid);
    _put(record, 'parse_error', parseError);
    _put(record, 'rendered_prompt', renderedPrompt);
    _put(record, 'response_text', _normalizeJsonValue(responseText));
    _put(record, 'response_json', _normalizeJsonValue(responseJson));
    _put(record, 'metadata', _normalizeJsonValue(metadata));
    return record;
  }

  Map<String, dynamic> toExchangeRecord() {
    final record = <String, dynamic>{};
    _put(record, 'request', renderedPrompt);
    _put(record, 'response', _normalizeJsonValue(responseText));
    _put(record, 'reasoning',
        _extractReasoningContent(metadata['reasoning_text']));
    return record;
  }
}

class LlmLogViewEntry {
  LlmLogViewEntry({
    required this.events,
  });

  final List<LlmLogViewEvent> events;

  DateTime get createdAt => events.last.createdAt;

  String get promptName =>
      _latestNonEmptyString((event) => event.promptName) ?? '';

  String get model => _latestNonEmptyString((event) => event.model) ?? '';

  String get baseUrl => _latestNonEmptyString((event) => event.baseUrl) ?? '';

  String get modeSummary => _joinUnique(
        events.map((event) => event.mode),
      );

  String get callHash => _latestNonEmptyString((event) => event.callHash) ?? '';

  int? get teacherId => _latestValue((event) => event.teacherId);

  int? get studentId => _latestValue((event) => event.studentId);

  int? get courseVersionId => _latestValue((event) => event.courseVersionId);

  int? get sessionId => _latestValue((event) => event.sessionId);

  String? get kpKey => _latestNonEmptyString((event) => event.kpKey);

  String? get action => _latestNonEmptyString((event) => event.action);

  String? get teacherName =>
      _latestNonEmptyString((event) => event.teacherName);

  String? get studentName =>
      _latestNonEmptyString((event) => event.studentName);

  String? get status =>
      _latestNonEmptyString((event) => event.status) ??
      (_latestValue((event) => event.parseValid) == true ? 'ok' : null);

  bool? get parseValid => _latestValue((event) => event.parseValid);

  Map<String, dynamic> toJsonRecord() {
    final record = <String, dynamic>{};
    _put(record, 'created_at', createdAt.toIso8601String());
    _put(record, 'prompt_name', promptName);
    _put(record, 'model', model);
    _put(record, 'base_url', baseUrl);
    _put(record, 'mode', modeSummary);
    _put(record, 'status', status);
    _put(record, 'call_hash', callHash);
    _put(record, 'teacher_id', teacherId);
    _put(record, 'teacher_name', teacherName);
    _put(record, 'student_id', studentId);
    _put(record, 'student_name', studentName);
    _put(record, 'course_version_id', courseVersionId);
    _put(record, 'session_id', sessionId);
    _put(record, 'kp_key', kpKey);
    _put(record, 'action', action);
    record['events'] =
        events.map((event) => event.toJsonRecord()).toList(growable: false);
    return record;
  }

  Map<String, dynamic> toExchangeRecord() {
    final attempts = events
        .map((event) => event.toExchangeRecord())
        .where((event) => event.isNotEmpty)
        .toList(growable: false);
    return <String, dynamic>{
      'attempts': attempts,
    };
  }

  T? _latestValue<T>(T? Function(LlmLogViewEvent event) read) {
    for (final event in events.reversed) {
      final value = read(event);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  String? _latestNonEmptyString(
    String? Function(LlmLogViewEvent event) read,
  ) {
    for (final event in events.reversed) {
      final value = read(event)?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}

List<LlmLogViewEntry> buildLlmLogViewEntries({
  required List<LlmLogDbAttemptInput> dbAttempts,
  required List<LlmLogFileEventInput> fileEvents,
}) {
  final dbAttemptsByHash = <String, List<LlmLogDbAttemptInput>>{};
  final dbIdentityByHash = <String, LlmLogDbAttemptInput>{};
  final unmatchedDbWithoutHash = <LlmLogDbAttemptInput>[];
  for (final entry in dbAttempts) {
    final hash = entry.callHash.trim();
    if (hash.isEmpty) {
      unmatchedDbWithoutHash.add(entry);
      continue;
    }
    dbAttemptsByHash
        .putIfAbsent(hash, () => <LlmLogDbAttemptInput>[])
        .add(entry);
    dbIdentityByHash.putIfAbsent(hash, () => entry);
  }
  for (final attempts in dbAttemptsByHash.values) {
    attempts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  final sortedFileEvents = [...fileEvents]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final groups = <_LlmLogGroup>[];
  final activeGroupByHash = <String, _LlmLogGroup>{};

  for (final entry in sortedFileEvents) {
    final matchedDb = _isModelAttempt(entry)
        ? _takeNextDbAttempt(dbAttemptsByHash, entry.callHash)
        : null;
    final identityDb = _lookupDbIdentity(dbIdentityByHash, entry.callHash);
    final event = LlmLogViewEvent(
      createdAt: entry.createdAt,
      promptName: matchedDb?.promptName ?? entry.promptName,
      model: matchedDb?.model ?? entry.model,
      baseUrl: matchedDb?.baseUrl ?? entry.baseUrl,
      mode: entry.mode.trim().isNotEmpty ? entry.mode : (matchedDb?.mode ?? ''),
      status: entry.status,
      callHash: entry.callHash?.trim() ?? matchedDb?.callHash ?? '',
      teacherId:
          matchedDb?.teacherId ?? identityDb?.teacherId ?? entry.teacherId,
      studentId:
          matchedDb?.studentId ?? identityDb?.studentId ?? entry.studentId,
      courseVersionId: matchedDb?.courseVersionId ?? entry.courseVersionId,
      sessionId: matchedDb?.sessionId ?? entry.sessionId,
      kpKey: matchedDb?.kpKey ?? entry.kpKey,
      action: matchedDb?.action ?? entry.action,
      teacherName: matchedDb?.teacherName ??
          identityDb?.teacherName ??
          entry.teacherName,
      studentName: matchedDb?.studentName ??
          identityDb?.studentName ??
          entry.studentName,
      renderedPrompt: matchedDb?.renderedPrompt,
      responseText: matchedDb?.responseText,
      responseJson: matchedDb?.responseJson,
      parseValid: matchedDb?.parseValid ?? entry.parseValid,
      parseError: matchedDb?.parseError ?? entry.parseError,
      metadata: entry.metadata,
    );
    final group = _selectGroupForFileEvent(
      groups: groups,
      activeGroupByHash: activeGroupByHash,
      callHash: event.callHash,
      isModelAttempt: _isModelAttempt(entry),
    );
    group.addEvent(
      event,
      isModelAttempt: _isModelAttempt(entry),
    );
  }

  final remainingDb = <LlmLogDbAttemptInput>[
    ...unmatchedDbWithoutHash,
    for (final attempts in dbAttemptsByHash.values) ...attempts,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  for (final entry in remainingDb) {
    final group = _LlmLogGroup();
    group.addEvent(
      LlmLogViewEvent(
        createdAt: entry.createdAt,
        promptName: entry.promptName,
        model: entry.model,
        baseUrl: entry.baseUrl,
        mode: entry.mode,
        status: '',
        callHash: entry.callHash,
        teacherId: entry.teacherId,
        studentId: entry.studentId,
        courseVersionId: entry.courseVersionId,
        sessionId: entry.sessionId,
        kpKey: entry.kpKey,
        action: entry.action,
        teacherName: entry.teacherName,
        studentName: entry.studentName,
        renderedPrompt: entry.renderedPrompt,
        responseText: entry.responseText,
        responseJson: entry.responseJson,
        parseValid: entry.parseValid,
        parseError: entry.parseError,
        metadata: <String, dynamic>{
          'source': 'llm_calls_only',
          'latency_ms': entry.latencyMs,
        },
      ),
      isModelAttempt: true,
    );
    groups.add(group);
  }

  final entries = groups.where((group) => group.events.isNotEmpty).map((group) {
    group.events.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return LlmLogViewEntry(
        events: List<LlmLogViewEvent>.unmodifiable(group.events));
  }).toList(growable: false);
  entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return entries;
}

class _LlmLogGroup {
  final List<LlmLogViewEvent> events = <LlmLogViewEvent>[];
  bool hasModelAttempt = false;
  bool bridgeToNextModel = false;

  void addEvent(
    LlmLogViewEvent event, {
    required bool isModelAttempt,
  }) {
    events.add(event);
    if (isModelAttempt) {
      hasModelAttempt = true;
      bridgeToNextModel = false;
      return;
    }
    bridgeToNextModel = true;
  }
}

_LlmLogGroup _selectGroupForFileEvent({
  required List<_LlmLogGroup> groups,
  required Map<String, _LlmLogGroup> activeGroupByHash,
  required String callHash,
  required bool isModelAttempt,
}) {
  final hash = callHash.trim();
  if (hash.isEmpty) {
    final group = _LlmLogGroup();
    groups.add(group);
    return group;
  }
  final active = activeGroupByHash[hash];
  if (active == null) {
    final group = _LlmLogGroup();
    groups.add(group);
    activeGroupByHash[hash] = group;
    return group;
  }
  if (!isModelAttempt || !active.hasModelAttempt || active.bridgeToNextModel) {
    return active;
  }
  final group = _LlmLogGroup();
  groups.add(group);
  activeGroupByHash[hash] = group;
  return group;
}

bool _isModelAttempt(LlmLogFileEventInput entry) {
  final reasoningText = entry.metadata['reasoning_text'] as String?;
  return entry.metadata['latency_ms'] != null ||
      entry.parseValid != null ||
      (reasoningText?.trim().isNotEmpty ?? false) ||
      entry.status.trim().toLowerCase() == 'ok';
}

LlmLogDbAttemptInput? _takeNextDbAttempt(
  Map<String, List<LlmLogDbAttemptInput>> attemptsByHash,
  String? callHash,
) {
  final hash = (callHash ?? '').trim();
  if (hash.isEmpty) {
    return null;
  }
  final queue = attemptsByHash[hash];
  if (queue == null || queue.isEmpty) {
    return null;
  }
  return queue.removeAt(0);
}

LlmLogDbAttemptInput? _lookupDbIdentity(
  Map<String, LlmLogDbAttemptInput> attemptsByHash,
  String? callHash,
) {
  final hash = (callHash ?? '').trim();
  if (hash.isEmpty) {
    return null;
  }
  return attemptsByHash[hash];
}

void _put(Map<String, dynamic> target, String key, dynamic value) {
  if (value == null) {
    return;
  }
  if (value is String && value.trim().isEmpty) {
    return;
  }
  target[key] = value;
}

dynamic _normalizeJsonValue(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return _normalizeJsonValue(jsonDecode(trimmed));
      } catch (_) {
        return value;
      }
    }
    return value;
  }
  if (value is Map) {
    final normalized = <String, dynamic>{};
    value.forEach((key, fieldValue) {
      final nextValue = _normalizeJsonValue(fieldValue);
      if (nextValue == null) {
        return;
      }
      normalized['$key'] = nextValue;
    });
    return normalized;
  }
  if (value is List) {
    return value
        .map(_normalizeJsonValue)
        .where((entry) => entry != null)
        .toList(growable: false);
  }
  return value;
}

dynamic _extractReasoningContent(dynamic value) {
  final normalized = _normalizeJsonValue(value);
  if (normalized is Map<String, dynamic>) {
    final reasoning = normalized['reasoning_text'];
    if (reasoning is String && reasoning.trim().isNotEmpty) {
      return reasoning;
    }
    if (reasoning != null) {
      return reasoning;
    }
  }
  if (normalized is String && normalized.trim().isNotEmpty) {
    return normalized;
  }
  return null;
}

String _joinUnique(Iterable<String> values) {
  final unique = <String>[];
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isEmpty || unique.contains(normalized)) {
      continue;
    }
    unique.add(normalized);
  }
  return unique.join(' + ');
}
