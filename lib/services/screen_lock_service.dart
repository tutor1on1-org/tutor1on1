/// Browser study-mode state holder.
///
/// Ordinary browser tabs cannot prevent closing, force focus, or lock the
/// workstation, so Tutor1on1 intentionally keeps only the logical state used
/// by the teacher-control flow.
class ScreenLockService {
  ScreenLockService();

  static final ScreenLockService instance = ScreenLockService();

  bool _enabled = false;

  bool get isEnabled => _enabled;

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
  }

  Future<void> start() => setEnabled(true);

  Future<void> stop() => setEnabled(false);

  Future<void> allowCloseOnce() async {}
}
