import '../db/app_database.dart';
import '../llm/llm_service.dart';
import '../llm/prompt_repository.dart';
import '../llm/schema_validator.dart';
import 'backup_service.dart';
import 'course_service.dart';
import 'enrollment_sync_service.dart';
import 'llm_call_repository.dart';
import 'llm_log_repository.dart';
import 'marketplace_api_service.dart';
import 'session_crypto_service.dart';
import 'session_sync_api_service.dart';
import 'session_sync_service.dart';
import 'secure_storage_service.dart';
import 'settings_repository.dart';
import 'session_service.dart';
import 'stt_service.dart';
import 'tts_service.dart';
import 'tts_log_repository.dart';
import 'user_key_service.dart';
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
    required this.enrollmentSyncService,
    required this.sessionSyncService,
    required this.sttService,
    required this.ttsService,
    required this.ttsLogRepository,
    required this.llmLogRepository,
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
  final EnrollmentSyncService enrollmentSyncService;
  final SessionSyncService sessionSyncService;
  final SttService sttService;
  final TtsService ttsService;
  final TtsLogRepository ttsLogRepository;
  final LlmLogRepository llmLogRepository;

  static Future<AppServices> create({AppDatabase? databaseOverride}) async {
    final db = databaseOverride ?? AppDatabase.open();
    await db.ensureAdminUser(
      username: 'admin',
      pinHash: PinHasher.hash('dennis_yang_edu'),
    );
    final settingsRepository = SettingsRepository(db);
    final secureStorage = SecureStorageService();
    final settings = await settingsRepository.load();
    final baseUrl = settings.baseUrl.trim();
    final legacyKey = await secureStorage.readApiKey();
    if ((legacyKey ?? '').trim().isNotEmpty) {
      final stored = await secureStorage.readApiKeyForBaseUrl(baseUrl);
      if ((stored ?? '').trim().isEmpty) {
        await secureStorage.writeApiKeyForBaseUrl(baseUrl, legacyKey!.trim());
      }
    }
    final promptRepository = PromptRepository(db: db);
    final schemaValidator = SchemaValidator();
    final callRepository = LlmCallRepository(db);
    final llmLogRepository = LlmLogRepository(settingsRepository);
    final llmService = LlmService(
      settingsRepository,
      secureStorage,
      callRepository,
      llmLogRepository,
      schemaValidator,
    );
    final backupService = BackupService(db);
    final courseService = CourseService(db);
    final marketplaceApi = MarketplaceApiService(secureStorage: secureStorage);
    final enrollmentSyncService = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: courseService,
      marketplaceApi: marketplaceApi,
    );
    final sessionService = SessionService(
      db,
      llmService,
      promptRepository,
      settingsRepository,
      llmLogRepository,
    );
    final sessionSyncApi = SessionSyncApiService(secureStorage: secureStorage);
    final cryptoService = SessionCryptoService();
    final userKeyService = UserKeyService(
      secureStorage: secureStorage,
      api: sessionSyncApi,
      crypto: cryptoService,
    );
    final sessionSyncService = SessionSyncService(
      db: db,
      secureStorage: secureStorage,
      api: sessionSyncApi,
      userKeyService: userKeyService,
      crypto: cryptoService,
    );
    final ttsLogRepository = TtsLogRepository(settingsRepository, db: db);
    final ttsService =
        TtsService(secureStorage, settingsRepository, ttsLogRepository);
    final sttService =
        SttService(secureStorage, settingsRepository, ttsLogRepository);
    await promptRepository.backfillAssignmentPrompts();
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
      enrollmentSyncService: enrollmentSyncService,
      sessionSyncService: sessionSyncService,
      sttService: sttService,
      ttsService: ttsService,
      ttsLogRepository: ttsLogRepository,
      llmLogRepository: llmLogRepository,
    );
  }
}
