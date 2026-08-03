Future<T?> runExclusiveLock<T>(
  String name,
  Future<T> Function() action, {
  required bool wait,
}) =>
    action();
