import '../services/db_path_provider.dart';

Future<String> resolveAppDatabasePath() async {
  return (await DbPathProvider.getDatabaseFile()).path;
}
