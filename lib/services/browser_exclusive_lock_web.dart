import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<T?> runExclusiveLock<T>(
  String name,
  Future<T> Function() action, {
  required bool wait,
}) async {
  final completer = Completer<T?>();
  final callback = ((web.Lock? lock) {
    if (lock == null) {
      completer.complete(null);
      return null;
    }
    return action().then<JSAny?>((value) {
      completer.complete(value);
      return null;
    }, onError: (Object error, StackTrace stackTrace) {
      completer.completeError(error, stackTrace);
      return null;
    }).toJS;
  }).toJS;
  await web.window.navigator.locks
      .request(
        name,
        web.LockOptions(mode: 'exclusive', ifAvailable: !wait),
        callback,
      )
      .toDart;
  return completer.future;
}
