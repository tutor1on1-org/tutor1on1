import 'browser_storage_persistence_stub.dart'
    if (dart.library.js_interop) 'browser_storage_persistence_web.dart';

Future<bool> requestPersistentBrowserStorage() => requestStoragePersistence();
