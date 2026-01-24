import '../db/app_database.dart';
import '../llm/llm_service.dart';
import '../llm/prompt_repository.dart';
import '../llm/schema_validator.dart';
import 'backup_service.dart';
import 'course_service.dart';
import 'llm_call_repository.dart';
import 'secure_storage_service.dart';
import 'settings_repository.dart';
import 'session_service.dart';
import '../security/pin_hasher.dart';

class AppServices {
  AppServices._({
    required this.db,
    required this.settingsRepository,
    required this.secureStorage,
    required this.promptRepository,
    required this.schemaValidator,
    required this.llmService,
    required this.backupService,
    required this.courseService,
    required this.sessionService,
  });

  final AppDatabase db;
  final SettingsRepository settingsRepository;
  final SecureStorageService secureStorage;
  final PromptRepository promptRepository;
  final SchemaValidator schemaValidator;
  final LlmService llmService;
  final BackupService backupService;
  final CourseService courseService;
  final SessionService sessionService;

  static Future<AppServices> create({AppDatabase? databaseOverride}) async {
    final db = databaseOverride ?? AppDatabase.open();
    await db.ensureAdminUser(
      username: 'admin',
      pinHash: PinHasher.hash('dennis_yang_edu'),
    );
    final settingsRepository = SettingsRepository(db);
    final secureStorage = SecureStorageService();
    final promptRepository = PromptRepository(db: db);
    final schemaValidator = SchemaValidator();
    final callRepository = LlmCallRepository(db);
    final llmService = LlmService(
      settingsRepository,
      secureStorage,
      callRepository,
      schemaValidator,
    );
    final backupService = BackupService(db);
    final courseService = CourseService(db);
    final sessionService = SessionService(
      db,
      llmService,
      promptRepository,
    );
    return AppServices._(
      db: db,
      settingsRepository: settingsRepository,
      secureStorage: secureStorage,
      promptRepository: promptRepository,
      schemaValidator: schemaValidator,
      llmService: llmService,
      backupService: backupService,
      courseService: courseService,
      sessionService: sessionService,
    );
  }
}
