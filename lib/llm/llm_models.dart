class LlmCallResult {
  LlmCallResult({
    required this.responseText,
    required this.latencyMs,
    required this.fromReplay,
    this.responseJson,
    this.reasoningText,
    this.parseValid,
    this.parseError,
    this.callHash,
    this.model,
    this.baseUrl,
  });

  final String responseText;
  final int latencyMs;
  final bool fromReplay;
  final String? responseJson;
  final String? reasoningText;
  final bool? parseValid;
  final String? parseError;
  final String? callHash;
  final String? model;
  final String? baseUrl;
}

class ReasoningEffort {
  static const String none = 'none';
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';

  static const List<String> values = <String>[
    none,
    low,
    medium,
    high,
  ];

  static String normalize(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return medium;
    }
    if (values.contains(normalized)) {
      return normalized;
    }
    return medium;
  }
}

class LlmCallContext {
  const LlmCallContext({
    this.teacherId,
    this.studentId,
    this.courseVersionId,
    this.sessionId,
    this.kpKey,
    this.action,
  });

  final int? teacherId;
  final int? studentId;
  final int? courseVersionId;
  final int? sessionId;
  final String? kpKey;
  final String? action;
}

class RequestHandle<T> {
  RequestHandle({required this.future, required this.cancel});

  final Future<T> future;
  final void Function() cancel;
}

typedef LlmRequestHandle = RequestHandle<LlmCallResult>;

enum LlmMode {
  liveRecord,
  replay,
  live,
}

extension LlmModeX on LlmMode {
  String get value {
    switch (this) {
      case LlmMode.liveRecord:
        return 'LIVE_RECORD';
      case LlmMode.replay:
        return 'REPLAY';
      case LlmMode.live:
        return 'LIVE';
    }
  }

  static LlmMode fromString(String value) {
    switch (value) {
      case 'REPLAY':
        return LlmMode.replay;
      case 'LIVE':
        return LlmMode.live;
      case 'LIVE_RECORD':
      default:
        return LlmMode.liveRecord;
    }
  }
}
