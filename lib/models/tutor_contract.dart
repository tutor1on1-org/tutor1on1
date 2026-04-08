import 'dart:convert';

import 'tutor_action.dart';

enum TutorTurnStep {
  newTurn('NEW'),
  continueTurn('CONTINUE');

  const TutorTurnStep(this.wireValue);
  final String wireValue;

  static TutorTurnStep? fromWire(String? value) {
    final normalized = value?.trim().toUpperCase();
    if (normalized == 'NEW') {
      return TutorTurnStep.newTurn;
    }
    if (normalized == 'CONTINUE') {
      return TutorTurnStep.continueTurn;
    }
    return null;
  }
}

enum TutorHelpBias {
  easier('EASIER'),
  unchanged('UNCHANGED'),
  harder('HARDER');

  const TutorHelpBias(this.wireValue);
  final String wireValue;

  static TutorHelpBias? fromWire(String? value) {
    final normalized = value?.trim().toUpperCase();
    if (normalized == 'EASIER') {
      return TutorHelpBias.easier;
    }
    if (normalized == 'UNCHANGED') {
      return TutorHelpBias.unchanged;
    }
    if (normalized == 'HARDER') {
      return TutorHelpBias.harder;
    }
    return null;
  }
}

enum TutorFinishedAction {
  learn('LEARN'),
  review('REVIEW');

  const TutorFinishedAction(this.wireValue);
  final String wireValue;

  static TutorFinishedAction? fromWire(String? value) {
    final normalized = value?.trim().toUpperCase();
    for (final candidate in TutorFinishedAction.values) {
      if (candidate.wireValue == normalized) {
        return candidate;
      }
    }
    return null;
  }
}

class TutorControlState {
  static const Object _unset = Object();

  const TutorControlState({
    required this.version,
    required this.mode,
    required this.step,
    required this.turnFinished,
    required this.helpBias,
    required this.allowedActions,
    required this.recommendedAction,
    required this.activeReviewQuestion,
    required this.justPassedKpEvent,
  });

  static const int currentVersion = 2;

  final int version;
  final TutorMode mode;
  final TutorTurnStep step;
  final bool turnFinished;
  final TutorHelpBias helpBias;
  final List<TutorFinishedAction> allowedActions;
  final TutorFinishedAction? recommendedAction;
  final Map<String, dynamic>? activeReviewQuestion;
  final TutorJustPassedKpEvent? justPassedKpEvent;

  bool get hasActiveReviewQuestion =>
      activeReviewQuestion != null && activeReviewQuestion!.isNotEmpty;

  TutorControlState copyWith({
    TutorMode? mode,
    TutorTurnStep? step,
    bool? turnFinished,
    TutorHelpBias? helpBias,
    List<TutorFinishedAction>? allowedActions,
    TutorFinishedAction? recommendedAction,
    Object? activeReviewQuestion = _unset,
    Object? justPassedKpEvent = _unset,
  }) {
    return TutorControlState(
      version: version,
      mode: mode ?? this.mode,
      step: step ?? this.step,
      turnFinished: turnFinished ?? this.turnFinished,
      helpBias: helpBias ?? this.helpBias,
      allowedActions: allowedActions ?? this.allowedActions,
      recommendedAction: recommendedAction ?? this.recommendedAction,
      activeReviewQuestion: identical(activeReviewQuestion, _unset)
          ? this.activeReviewQuestion
          : (activeReviewQuestion as Map<String, dynamic>?),
      justPassedKpEvent: identical(justPassedKpEvent, _unset)
          ? this.justPassedKpEvent
          : (justPassedKpEvent as TutorJustPassedKpEvent?),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'mode': mode == TutorMode.learn ? 'LEARN' : 'REVIEW',
      'step': step.wireValue,
      'turn_finished': turnFinished,
      'help_bias': helpBias.wireValue,
      'allowed_actions': allowedActions.map((item) => item.wireValue).toList(),
      'recommended_action': recommendedAction?.wireValue,
      'active_review_question': activeReviewQuestion,
      'just_passed_kp_event': justPassedKpEvent?.toJson(),
    };
  }

  String toJsonText() => jsonEncode(toJson());

  static TutorControlState? fromJsonText(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static TutorControlState? fromJson(Map<String, dynamic> json) {
    final mode = _modeFromWire(json['mode'] as String?);
    final step = TutorTurnStep.fromWire(json['step'] as String?);
    final turnFinished = json['turn_finished'] == true;
    final helpBias = TutorHelpBias.fromWire(json['help_bias'] as String?);
    if (mode == null || step == null || helpBias == null) {
      return null;
    }
    final allowedRaw = json['allowed_actions'];
    if (allowedRaw != null && allowedRaw is! List) {
      return null;
    }
    final allowed = <TutorFinishedAction>[];
    if (allowedRaw is List) {
      for (final entry in allowedRaw) {
        if (entry is! String) {
          return null;
        }
        final action = TutorFinishedAction.fromWire(entry);
        if (action == null) {
          return null;
        }
        if (!allowed.contains(action)) {
          allowed.add(action);
        }
      }
    }
    final recommendedRaw = json['recommended_action'];
    if (recommendedRaw != null && recommendedRaw is! String) {
      return null;
    }
    final recommended = TutorFinishedAction.fromWire(recommendedRaw as String?);
    if (recommendedRaw is String &&
        recommendedRaw.trim().isNotEmpty &&
        recommended == null) {
      return null;
    }
    final activeReviewQuestionRaw = json['active_review_question'];
    if (activeReviewQuestionRaw != null &&
        activeReviewQuestionRaw is! Map<String, dynamic>) {
      return null;
    }
    final justPassedKpEvent = TutorJustPassedKpEvent.fromJson(
      json['just_passed_kp_event'],
    );
    if (json['just_passed_kp_event'] != null && justPassedKpEvent == null) {
      return null;
    }
    return TutorControlState(
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      mode: mode,
      step: step,
      turnFinished: turnFinished,
      helpBias: helpBias,
      allowedActions: allowed,
      recommendedAction: recommended,
      activeReviewQuestion: activeReviewQuestionRaw == null
          ? null
          : Map<String, dynamic>.from(activeReviewQuestionRaw as Map),
      justPassedKpEvent: justPassedKpEvent,
    );
  }

  static TutorControlState defaultForMode(TutorMode mode) {
    return TutorControlState(
      version: currentVersion,
      mode: mode,
      step: TutorTurnStep.newTurn,
      turnFinished: false,
      helpBias: TutorHelpBias.unchanged,
      allowedActions: const <TutorFinishedAction>[],
      recommendedAction: null,
      activeReviewQuestion: null,
      justPassedKpEvent: null,
    );
  }

  static TutorControlState? fromAssistantPayload(
    Map<String, dynamic>? parsed,
  ) {
    if (parsed == null) {
      return null;
    }
    final control = parsed['control'];
    if (control is Map<String, dynamic>) {
      final decoded = fromJson(control);
      if (decoded != null) {
        return decoded;
      }
    }
    final finished = parsed['finished'];
    if (finished is bool) {
      final difficultyLevel = _normalizeLevel(parsed['difficulty']);
      final text = (parsed['text'] as String?)?.trim();
      final mistakes = _stringListFromValue(parsed['mistakes']);
      final activeReviewQuestion = finished
          ? null
          : <String, dynamic>{
              if (text != null && text.isNotEmpty) 'text': text,
              if (difficultyLevel != null) 'difficulty': difficultyLevel,
              if (mistakes.isNotEmpty) 'mistakes': mistakes,
            };
      return TutorControlState(
        version: currentVersion,
        mode: TutorMode.review,
        step: finished ? TutorTurnStep.newTurn : TutorTurnStep.continueTurn,
        turnFinished: finished,
        helpBias: TutorHelpBias.unchanged,
        allowedActions: const <TutorFinishedAction>[],
        recommendedAction: TutorFinishedAction.fromWire(
          (parsed['next_action'] as String?)?.trim().toUpperCase(),
        ),
        activeReviewQuestion: activeReviewQuestion,
        justPassedKpEvent: null,
      );
    }
    final nextAction = TutorFinishedAction.fromWire(
      (parsed['next_action'] as String?)?.trim().toUpperCase(),
    );
    final helpBias =
        TutorHelpBias.fromWire(parsed['next_help_bias'] as String?);
    if (nextAction == null || helpBias == null) {
      return null;
    }
    return TutorControlState(
      version: currentVersion,
      mode: nextAction == TutorFinishedAction.learn
          ? TutorMode.learn
          : TutorMode.review,
      step: TutorTurnStep.newTurn,
      turnFinished: true,
      helpBias: helpBias,
      allowedActions: const <TutorFinishedAction>[],
      recommendedAction: nextAction,
      activeReviewQuestion: null,
      justPassedKpEvent: null,
    );
  }

  static TutorMode? _modeFromWire(String? value) {
    final normalized = value?.trim().toUpperCase();
    if (normalized == 'LEARN' || normalized == 'RELEARN') {
      return TutorMode.learn;
    }
    if (normalized == 'REVIEW' || normalized == 'CONTINUE_REVIEW') {
      return TutorMode.review;
    }
    return null;
  }

  static String? _normalizeLevel(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized == 'easy' ||
        normalized == 'medium' ||
        normalized == 'hard') {
      return normalized;
    }
    return null;
  }

  static List<String> _stringListFromValue(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class TutorJustPassedKpEvent {
  const TutorJustPassedKpEvent({
    required this.easyPassedCount,
    required this.mediumPassedCount,
    required this.hardPassedCount,
  });

  final int easyPassedCount;
  final int mediumPassedCount;
  final int hardPassedCount;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'easy_passed_count': easyPassedCount,
      'medium_passed_count': mediumPassedCount,
      'hard_passed_count': hardPassedCount,
    };
  }

  static TutorJustPassedKpEvent? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    return TutorJustPassedKpEvent(
      easyPassedCount: _readNonNegativeCount(value['easy_passed_count']),
      mediumPassedCount: _readNonNegativeCount(value['medium_passed_count']),
      hardPassedCount: _readNonNegativeCount(value['hard_passed_count']),
    );
  }

  static int _readNonNegativeCount(Object? value) {
    final count = (value as num?)?.toInt() ?? 0;
    return count < 0 ? 0 : count;
  }
}

class TutorEvidenceState {
  const TutorEvidenceState({
    required this.version,
    required this.policy,
    required this.gradedReviewCount,
    required this.summaryConsumedReviewCount,
    required this.reviewCorrectTotal,
    required this.reviewAttemptTotal,
    required this.easyPassedCount,
    required this.mediumPassedCount,
    required this.hardPassedCount,
    required this.easyFailedCount,
    required this.mediumFailedCount,
    required this.hardFailedCount,
    required this.lastAssessedAction,
    required this.lastEvidence,
  });

  static const int currentVersion = 1;
  static const String reviewOnlyPolicy = 'REVIEW_ONLY';

  final int version;
  final String policy;
  final int gradedReviewCount;
  final int summaryConsumedReviewCount;
  final int reviewCorrectTotal;
  final int reviewAttemptTotal;
  final int easyPassedCount;
  final int mediumPassedCount;
  final int hardPassedCount;
  final int easyFailedCount;
  final int mediumFailedCount;
  final int hardFailedCount;
  final String? lastAssessedAction;
  final Map<String, dynamic>? lastEvidence;

  bool get hasNewGradedReviewEvidence =>
      gradedReviewCount > summaryConsumedReviewCount;

  TutorEvidenceState copyWith({
    String? policy,
    int? gradedReviewCount,
    int? summaryConsumedReviewCount,
    int? reviewCorrectTotal,
    int? reviewAttemptTotal,
    int? easyPassedCount,
    int? mediumPassedCount,
    int? hardPassedCount,
    int? easyFailedCount,
    int? mediumFailedCount,
    int? hardFailedCount,
    String? lastAssessedAction,
    Map<String, dynamic>? lastEvidence,
  }) {
    return TutorEvidenceState(
      version: version,
      policy: policy ?? this.policy,
      gradedReviewCount: gradedReviewCount ?? this.gradedReviewCount,
      summaryConsumedReviewCount:
          summaryConsumedReviewCount ?? this.summaryConsumedReviewCount,
      reviewCorrectTotal: reviewCorrectTotal ?? this.reviewCorrectTotal,
      reviewAttemptTotal: reviewAttemptTotal ?? this.reviewAttemptTotal,
      easyPassedCount: easyPassedCount ?? this.easyPassedCount,
      mediumPassedCount: mediumPassedCount ?? this.mediumPassedCount,
      hardPassedCount: hardPassedCount ?? this.hardPassedCount,
      easyFailedCount: easyFailedCount ?? this.easyFailedCount,
      mediumFailedCount: mediumFailedCount ?? this.mediumFailedCount,
      hardFailedCount: hardFailedCount ?? this.hardFailedCount,
      lastAssessedAction: lastAssessedAction ?? this.lastAssessedAction,
      lastEvidence: lastEvidence ?? this.lastEvidence,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'policy': policy,
      'graded_review_count': gradedReviewCount,
      'summary_consumed_review_count': summaryConsumedReviewCount,
      'review_correct_total': reviewCorrectTotal,
      'review_attempt_total': reviewAttemptTotal,
      'easy_passed_count': easyPassedCount,
      'medium_passed_count': mediumPassedCount,
      'hard_passed_count': hardPassedCount,
      'easy_failed_count': easyFailedCount,
      'medium_failed_count': mediumFailedCount,
      'hard_failed_count': hardFailedCount,
      'last_assessed_action': lastAssessedAction,
      'last_evidence': lastEvidence,
    };
  }

  String toJsonText() => jsonEncode(toJson());

  static TutorEvidenceState initial() {
    return const TutorEvidenceState(
      version: currentVersion,
      policy: reviewOnlyPolicy,
      gradedReviewCount: 0,
      summaryConsumedReviewCount: 0,
      reviewCorrectTotal: 0,
      reviewAttemptTotal: 0,
      easyPassedCount: 0,
      mediumPassedCount: 0,
      hardPassedCount: 0,
      easyFailedCount: 0,
      mediumFailedCount: 0,
      hardFailedCount: 0,
      lastAssessedAction: null,
      lastEvidence: null,
    );
  }

  static TutorEvidenceState? fromJsonText(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static TutorEvidenceState? fromJson(Map<String, dynamic> json) {
    return TutorEvidenceState(
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      policy: (json['policy'] as String?)?.trim().isNotEmpty == true
          ? (json['policy'] as String).trim()
          : reviewOnlyPolicy,
      gradedReviewCount: (json['graded_review_count'] as num?)?.toInt() ?? 0,
      summaryConsumedReviewCount:
          (json['summary_consumed_review_count'] as num?)?.toInt() ?? 0,
      reviewCorrectTotal: (json['review_correct_total'] as num?)?.toInt() ?? 0,
      reviewAttemptTotal: (json['review_attempt_total'] as num?)?.toInt() ?? 0,
      easyPassedCount: (json['easy_passed_count'] as num?)?.toInt() ?? 0,
      mediumPassedCount: (json['medium_passed_count'] as num?)?.toInt() ?? 0,
      hardPassedCount: (json['hard_passed_count'] as num?)?.toInt() ?? 0,
      easyFailedCount: (json['easy_failed_count'] as num?)?.toInt() ?? 0,
      mediumFailedCount: (json['medium_failed_count'] as num?)?.toInt() ?? 0,
      hardFailedCount: (json['hard_failed_count'] as num?)?.toInt() ?? 0,
      lastAssessedAction: (json['last_assessed_action'] as String?)?.trim(),
      lastEvidence: json['last_evidence'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['last_evidence'] as Map)
          : null,
    );
  }

  static TutorEvidenceState updateFromAssistantPayload({
    required TutorEvidenceState current,
    required String actionMode,
    required Map<String, dynamic>? parsed,
    required bool hadActiveReviewQuestion,
    String? passedLevel,
  }) {
    final normalizedAction = actionMode.trim().toUpperCase();
    if (normalizedAction == 'REVIEW' && parsed != null) {
      final finished = parsed['finished'];
      if (finished is bool) {
        final normalizedLevel = _normalizeLevel(parsed['difficulty']) ??
            _normalizeLevel(passedLevel);
        final mistakeTags = _stringListFromValue(parsed['mistakes']);
        final shouldCountReviewAttempt = hadActiveReviewQuestion;
        return current.copyWith(
          gradedReviewCount:
              current.gradedReviewCount + (shouldCountReviewAttempt ? 1 : 0),
          reviewCorrectTotal: current.reviewCorrectTotal +
              (shouldCountReviewAttempt && finished ? 1 : 0),
          reviewAttemptTotal:
              current.reviewAttemptTotal + (shouldCountReviewAttempt ? 1 : 0),
          easyPassedCount: current.easyPassedCount +
              (shouldCountReviewAttempt && finished && normalizedLevel == 'easy'
                  ? 1
                  : 0),
          mediumPassedCount: current.mediumPassedCount +
              (shouldCountReviewAttempt &&
                      finished &&
                      normalizedLevel == 'medium'
                  ? 1
                  : 0),
          hardPassedCount: current.hardPassedCount +
              (shouldCountReviewAttempt && finished && normalizedLevel == 'hard'
                  ? 1
                  : 0),
          easyFailedCount: current.easyFailedCount +
              (shouldCountReviewAttempt &&
                      !finished &&
                      normalizedLevel == 'easy'
                  ? 1
                  : 0),
          mediumFailedCount: current.mediumFailedCount +
              (shouldCountReviewAttempt &&
                      !finished &&
                      normalizedLevel == 'medium'
                  ? 1
                  : 0),
          hardFailedCount: current.hardFailedCount +
              (shouldCountReviewAttempt &&
                      !finished &&
                      normalizedLevel == 'hard'
                  ? 1
                  : 0),
          lastAssessedAction: 'REVIEW',
          lastEvidence: <String, dynamic>{
            'difficulty': normalizedLevel,
            'finished': finished,
            'mistakes': mistakeTags,
          },
        );
      }
    }
    if (normalizedAction == 'LEARN') {
      return current.copyWith(
        lastAssessedAction: 'LEARN',
        lastEvidence: <String, dynamic>{
          'difficulty': _normalizeLevel(parsed?['difficulty']),
          'mistakes': _stringListFromValue(parsed?['mistakes']),
          'next_action': (parsed?['next_action'] as String?)?.trim(),
        },
      );
    }
    return current;
  }

  static TutorEvidenceState rebuildFromAssistantTurns({
    required TutorEvidenceState seed,
    required Iterable<TutorEvidenceAssistantTurn> turns,
  }) {
    var rebuilt = TutorEvidenceState(
      version: seed.version,
      policy: seed.policy,
      gradedReviewCount: 0,
      summaryConsumedReviewCount: 0,
      reviewCorrectTotal: 0,
      reviewAttemptTotal: 0,
      easyPassedCount: 0,
      mediumPassedCount: 0,
      hardPassedCount: 0,
      easyFailedCount: 0,
      mediumFailedCount: 0,
      hardFailedCount: 0,
      lastAssessedAction: null,
      lastEvidence: null,
    );
    var hasActiveReviewQuestion = false;
    for (final turn in turns) {
      rebuilt = TutorEvidenceState.updateFromAssistantPayload(
        current: rebuilt,
        actionMode: turn.actionMode,
        parsed: turn.parsed,
        hadActiveReviewQuestion: hasActiveReviewQuestion,
      );
      final normalizedAction = turn.actionMode.trim().toUpperCase();
      if (normalizedAction == 'REVIEW' && turn.parsed != null) {
        final finished = turn.parsed!['finished'];
        if (finished is bool) {
          hasActiveReviewQuestion = !finished;
        }
      } else if (normalizedAction != 'REVIEW') {
        hasActiveReviewQuestion = false;
      }
    }
    final cappedSummaryConsumed =
        seed.summaryConsumedReviewCount > rebuilt.gradedReviewCount
            ? rebuilt.gradedReviewCount
            : seed.summaryConsumedReviewCount;
    return rebuilt.copyWith(
      summaryConsumedReviewCount: cappedSummaryConsumed,
    );
  }

  static String? _normalizeLevel(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized == 'easy' ||
        normalized == 'medium' ||
        normalized == 'hard') {
      return normalized;
    }
    return null;
  }

  static List<String> _stringListFromValue(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class TutorEvidenceAssistantTurn {
  const TutorEvidenceAssistantTurn({
    required this.actionMode,
    required this.parsed,
  });

  final String actionMode;
  final Map<String, dynamic>? parsed;
}
