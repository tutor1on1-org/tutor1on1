import 'browser_auth_session_stub.dart'
    if (dart.library.js_interop) 'browser_auth_session_web.dart';

Stream<int?> get browserAuthUserChanges => authUserChanges;

int? readBrowserAuthUser() => readAuthUser();

void writeBrowserAuthUser(int? remoteUserId) {
  writeAuthUser(remoteUserId);
}
