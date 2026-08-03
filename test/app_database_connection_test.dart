import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutor1on1/db/app_database_connection.dart';

void main() {
  test('uses stable root-relative Drift web asset names', () {
    expect(appDatabaseName, 'tutor1on1');
    expect(appDatabaseSqliteWasmAsset, 'sqlite3.wasm');
    expect(appDatabaseDriftWorkerAsset, 'drift_worker.js');
  });

  test('accepts persistent browser storage', () {
    expect(
      () => validateWebDatabaseStorage(
        WasmStorageImplementation.sharedIndexedDb,
        const <MissingBrowserFeature>{},
      ),
      returnsNormally,
    );
  });

  test('rejects an unavailable Drift worker', () {
    expect(
      () => validateWebDatabaseStorage(
        WasmStorageImplementation.unsafeIndexedDb,
        const <MissingBrowserFeature>{MissingBrowserFeature.workerError},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(appDatabaseDriftWorkerAsset),
        ),
      ),
    );
  });

  test('rejects non-persistent browser storage', () {
    expect(
      () => validateWebDatabaseStorage(
        WasmStorageImplementation.inMemory,
        const <MissingBrowserFeature>{MissingBrowserFeature.indexedDb},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('persistent SQLite storage'),
        ),
      ),
    );
  });
}
