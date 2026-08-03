import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _storageKey = 'tutor1on1.auth.remote-user-id.v1';
final StreamController<int?> _authUserChanges =
    StreamController<int?>.broadcast(sync: true);
bool _isListening = false;

Stream<int?> get authUserChanges {
  _ensureListening();
  return _authUserChanges.stream;
}

int? readAuthUser() {
  final raw = web.window.localStorage.getItem(_storageKey);
  if (raw == null) {
    return null;
  }
  final remoteUserId = int.tryParse(raw.trim());
  return remoteUserId != null && remoteUserId > 0 ? remoteUserId : null;
}

void writeAuthUser(int? remoteUserId) {
  _ensureListening();
  if (remoteUserId == null || remoteUserId <= 0) {
    web.window.localStorage.removeItem(_storageKey);
    return;
  }
  web.window.localStorage.setItem(_storageKey, remoteUserId.toString());
}

void _ensureListening() {
  if (_isListening) {
    return;
  }
  _isListening = true;
  web.window.addEventListener(
    'storage',
    ((web.Event event) {
      final storageEvent = event as web.StorageEvent;
      if (storageEvent.key != _storageKey) {
        return;
      }
      final current = readAuthUser();
      if (current == null) {
        _authUserChanges.add(null);
        return;
      }
      _authUserChanges.add(current);
    }).toJS,
  );
}
