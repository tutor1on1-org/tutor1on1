import 'package:family_teacher/l10n/app_localizations.dart';

enum TutorMode {
  learn,
  review,
}

extension TutorModeX on TutorMode {
  String label(AppLocalizations l10n) {
    switch (this) {
      case TutorMode.learn:
        return l10n.promptLearn;
      case TutorMode.review:
        return l10n.promptReview;
    }
  }

  String get promptName {
    switch (this) {
      case TutorMode.learn:
        return 'learn';
      case TutorMode.review:
        return 'review';
    }
  }
}
