import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> requestStoragePersistence() async {
  try {
    return (await web.window.navigator.storage.persist().toDart).toDart;
  } catch (_) {
    return false;
  }
}
