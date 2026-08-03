import 'browser_connectivity_events_stub.dart'
    if (dart.library.js_interop) 'browser_connectivity_events_web.dart';

Stream<void> get browserOnlineEvents => onlineEvents;
