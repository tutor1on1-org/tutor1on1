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
  nextQuestion('NEXT_QUESTION'),
  learn('LEARN'),
  continueLearning('CONTINUE_LEARNING'),
  tryQuestion('TRY_QUESTION'),
  summarize('SUMMARIZE'),
  pause('PAUSE');

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
  const TutorControlState({
    required this.version,
    required this.mode,
    required this.step,
    required this.turnFinished,
    required this.helpBias,
    required this.allowedActions,
    required this.recommendedAction,
  });

  static const int currentVersion = 1;

  final int version;
  final TutorMode mode;
  final TutorTurnStep step;
  final bool turnFinished;
  final TutorHelpBias helpBias;
  final List<TutorFinishedAction> allowedActions;
  final TutorFinishedAction? recommendedAction;

  TutorControlState copyWith({
    TutorMode? mode,
    TutorTurnStep? step,
    bool? turnFinished,
    TutorHelpBias? helpBias,
    List<TutorFinishedAction>? allowedActions,
    TutorFinishedAction? recommendedAction,
  }) {
    return TutorControlState(
      version: version,
      mode: mode ?? this.mode,
      step: step ?? this.step,
      turnFinished: turnFinished ?? this.turnFinished,
      helpBias: helpBias ?? this.helpBias,
      allowedActions: allowedActions ?? this.allowedActions,
      recommendedAction: recommendedAction ?? this.recommendedAction,
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
    final recommended =
        TutorFinishedAction.fromWire(recommendedRaw as String?);
    if (recommendedRaw is String &&
        recommendedRaw.trim().isNotEmpty &&
        recommended == null) {
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
    final mode = _modeFromWire(
      (parsed['next_mode'] as String?) ??
          (parsed['next_step'] as String?),
    );
    final turnState = (parsed['turn_state'] as String?)?.trim().toUpperCase();
    final helpBias = TutorHelpBias.fromWire(
      parsed['next_help_bias'] as String?,
    );
    if (mode == null || helpBias == null) {
      return null;
    }
    final finished = turnState == 'FINISHED';
    return TutorControlState(
      version: currentVersion,
      mode: mode,
      step: finished ? TutorTurnStep.newTurn : TutorTurnStep.continueTurn,
      turnFinished: finished,
      helpBias: helpBias,
      allowedActions: finished
          ? _legacyAllowedActionsForMode(mode)
          : const <TutorFinishedAction>[],
      recommendedAction:
          finished ? _legacyRecommendedAction(parsed: parsed, mode: mode) : null,
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

  static List<TutorFinishedAction> _legacyAllowedActionsForMode(
    TutorMode mode,
  ) {
    if (mode == TutorMode.review) {
      return const <TutorFinishedAction>[
        TutorFinishedAction.nextQuestion,
        TutorFinishedAction.learn,
        TutorFinishedAction.summarize,
        TutorFinishedAction.pause,
      ];
    }
    return const <TutorFinishedAction>[
      TutorFinishedAction.continueLearning,
      TutorFinishedAction.tryQuestion,
      TutorFinishedAction.summarize,
      TutorFinishedAction.pause,
    ];
  }

  static TutorFinishedAction _legacyRecommendedAction({
    required Map<String, dynamic> parsed,
    required TutorMode mode,
  }) {
    final nextAction = (parsed['next_action'] as String?)?.trim().toUpperCase();
    if (nextAction == 'SUMMARY') {
      return TutorFinishedAction.summarize;
    }
    if (mode == TutorMode.review) {
      return TutorFinishedAction.nextQuestion;
    }
    return TutorFinishedAction.continueLearning;
  }
}

class TutorEvidenceState {
  const TutorEvidenceState({
    required this.version,
    required this.policy,
    required this.gradedReviewCount,
    required this.summaryConsumedReviewCount,
    required this.lastAssessedAction,
    required this.lastMasteryLevel,
    required this.lastEvidence,
  });

  static const int currentVersion = 1;
  static const String reviewOnlyPolicy = 'REVIEW_ONLY';

  final int version;
  final String policy;
  final int gradedReviewCount;
  final int summaryConsumedReviewCount;
  final String? lastAssessedAction;
  final String? lastMasteryLevel;
  final Map<String, dynamic>? lastEvidence;

  bool get hasNewGradedReviewEvidence =>
      gradedReviewCount > summaryConsumedReviewCount;

  TutorEvidenceState copyWith({
    String? policy,
    int? gradedReviewCount,
    int? summaryConsumedReviewCount,
    String? lastAssessedAction,
    String? lastMasteryLevel,
    Map<String, dynamic>? lastEvidence,
  }) {
    return TutorEvidenceState(
      version: version,
      policy: policy ?? this.policy,
      gradedReviewCount: gradedReviewCount ?? this.gradedReviewCount,
      summaryConsumedReviewCount:
          summaryConsumedReviewCount ?? this.summaryConsumedReviewCount,
      lastAssessedAction: lastAssessedAction ?? this.lastAssessedAction,
      lastMasteryLevel: lastMasteryLevel ?? this.lastMasteryLevel,
      lastEvidence: lastEvidence ?? this.lastEvidence,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'policy': policy,
      'graded_review_count': gradedReviewCount,
      'summary_consumed_review_count': summaryConsumedReviewCount,
      'last_assessed_action': lastAssessedAction,
      'last_mastery_level': lastMasteryLevel,
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
      lastAssessedAction: null,
      lastMasteryLevel: null,
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
      lastAssessedAction: (json['last_assessed_action'] as String?)?.trim(),
      lastMasteryLevel: (json['last_mastery_level'] as String?)?.trim(),
      lastEvidence: json['last_evidence'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['last_evidence'] as Map)
          : null,
    );
  }

  static TutorEvidenceState updateFromAssistantPayload({
    required TutorEvidenceState current,
    required String actionMode,
    required Map<String, dynamic>? parsed,
  }) {
    final normalizedAction = actionMode.trim().toUpperCase();
    if (normalizedAction == 'REVIEW' && parsed != null) {
      final turnState = (parsed['turn_state'] as String?)?.trim().toUpperCase();
      final grading = parsed['grading'];
      final evidence = parsed['evidence'];
      final masteryLevel = (parsed['mastery_level'] as String?)?.trim();
      final isGradedFinal =
          turnState == 'FINISHED' && grading is Map<String, dynamic>;
      return current.copyWith(
        gradedReviewCount:
            current.gradedReviewCount + (isGradedFinal ? 1 : 0),
        lastAssessedAction: 'REVIEW',
        lastMasteryLevel:
            masteryLevel != null && masteryLevel.isNotEmpty
                ? masteryLevel
                : current.lastMasteryLevel,
        lastEvidence: evidence is Map<String, dynamic>
            ? Map<String, dynamic>.from(evidence)
            : current.lastEvidence,
      );
    }
    if (normalizedAction == 'LEARN') {
      return current.copyWith(lastAssessedAction: 'LEARN');
    }
    if (normalizedAction == 'SUMMARY') {
      return current.copyWith(
        lastAssessedAction: 'SUMMARY',
        summaryConsumedReviewCount: current.gradedReviewCount,
      );
    }
    return current;
  }
}
