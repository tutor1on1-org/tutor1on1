import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'app_database_path_unsupported.dart'
    if (dart.library.io) 'app_database_path_native.dart' as platform;

const String appDatabaseName = 'tutor1on1';
const String appDatabaseSqliteWasmAsset = 'sqlite3.wasm';
const String appDatabaseDriftWorkerAsset = 'drift_worker.js';

QueryExecutor openAppDatabaseConnection() {
  return driftDatabase(
    name: appDatabaseName,
    native: DriftNativeOptions(
      databasePath: platform.resolveAppDatabasePath,
    ),
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse(appDatabaseSqliteWasmAsset),
      driftWorker: Uri.parse(appDatabaseDriftWorkerAsset),
      onResult: (result) => validateWebDatabaseStorage(
        result.chosenImplementation,
        result.missingFeatures,
      ),
    ),
  );
}

/// Refuses a browser database that would silently lose data or bypass the
/// worker needed for safe access across Chrome tabs.
void validateWebDatabaseStorage(
  WasmStorageImplementation implementation,
  Set<MissingBrowserFeature> missingFeatures,
) {
  if (missingFeatures.contains(MissingBrowserFeature.workerError)) {
    throw StateError(
      'Could not start the Drift web worker. Ensure '
      '$appDatabaseDriftWorkerAsset is deployed at the application root.',
    );
  }
  if (implementation == WasmStorageImplementation.inMemory) {
    throw StateError(
      'This browser cannot provide persistent SQLite storage. Missing '
      'features: ${missingFeatures.map((feature) => feature.name).join(', ')}.',
    );
  }
}
