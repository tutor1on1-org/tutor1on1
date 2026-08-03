import 'browser_exclusive_lock_stub.dart'
    if (dart.library.js_interop) 'browser_exclusive_lock_web.dart';

Future<T?> runWithBrowserExclusiveLock<T>(
  String name,
  Future<T> Function() action,
) =>
    runExclusiveLock<T>(name, action, wait: true);

Future<T?> tryWithBrowserExclusiveLock<T>(
  String name,
  Future<T> Function() action,
) =>
    runExclusiveLock<T>(name, action, wait: false);

String browserSyncLockName(int remoteUserId) => 'tutor1on1-sync';

const String browserAuthRefreshLockName = 'tutor1on1-auth-refresh';
