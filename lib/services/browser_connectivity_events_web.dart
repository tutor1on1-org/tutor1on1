import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

final Stream<void> onlineEvents = _createOnlineEvents();

Stream<void> _createOnlineEvents() {
  final controller = StreamController<void>.broadcast();
  web.window.addEventListener(
    'online',
    ((web.Event _) => controller.add(null)).toJS,
  );
  return controller.stream;
}
