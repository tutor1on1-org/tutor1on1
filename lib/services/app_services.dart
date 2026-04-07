import '../db/app_database.dart';
import '../llm/llm_service.dart';
import '../llm/prompt_repository.dart';
import '../llm/schema_validator.dart';
import 'artifact_sync_api_service.dart';
import 'backup_service.dart';
import 'course_artifact_service.dart';
import 'course_service.dart';
import 'device_identity_service.dart';
import 'enrollment_sync_service.dart';
import 'llm_call_repository.dart';
import 'llm_log_repository.dart';
import 'marketplace_api_service.dart';
import 'session_sync_service.dart';
import 'session_upload_cache_service.dart';
import 'secure_storage_service.dart';
import 'settings_repository.dart';
import 'session_service.dart';
import 'student_kp_artifact_store_service.dart';
import 'stt_service.dart';
import 'sync_log_repository.dart';
import 'tts_service.dart';
import 'tts_log_repository.dart';

class AppServices {
  AppServices._({
    required this.db,
    required this.settingsRepository,
    required this.secureStorage,
    required this.deviceIdentityService,
    required this.promptRepository,
    required this.schemaValidator,
    required this.llmService,
    required this.backupService,
    required this.courseArtifactService,
    required this.courseService,
    required this.sessionService,
    required this.enrollmentSyncService,
    required this.sessionSyncService,
    required this.sessionUploadCacheService,
    required this.sttService,
    required this.syncLogRepository,
    required this.ttsService,
    required this.ttsLogRepository,
    required this.llmLogRepository,
  });

  final AppDatabase db;
  final SettingsRepository settingsRepository;
  final SecureStorageService secureStorage;
  final DeviceIdentityService deviceIdentityService;
  final PromptRepository promptRepository;
  final SchemaValidator schemaValidator;
  final LlmService llmService;
  final BackupService backupService;
  final CourseArtifactService courseArtifactService;
  final CourseService courseService;
  final SessionService sessionService;
  final EnrollmentSyncService enrollmentSyncService;
  final SessionSyncService sessionSyncService;
  final SessionUploadCacheService sessionUploadCacheService;
  final SttService sttService;
  final SyncLogRepository syncLogRepository;
  final TtsService ttsService;
  final TtsLogRepository ttsLogRepository;
  final LlmLogRepository llmLogRepository;

  static Future<AppServices> create({AppDatabase? databaseOverride}) async {
    final db = databaseOverride ?? AppDatabase.open();
    final settingsRepository = SettingsRepository(db);
    final secureStorage = SecureStorageService();
    await secureStorage.ensureReadableOrReset();
    await secureStorage.clearLegacySyncCompatibilityState();
    final deviceIdentityService = DeviceIdentityService(secureStorage);
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
    final syncLogRepository = SyncLogRepository(settingsRepository);
    final llmLogRepository = LlmLogRepository(settingsRepository);
    final llmService = LlmService(
      settingsRepository,
      secureStorage,
      callRepository,
      llmLogRepository,
      schemaValidator,
    );
    final backupService = BackupService(db);
    final courseArtifactService = CourseArtifactService();
    final courseService = CourseService(
      db,
      courseArtifactService: courseArtifactService,
    );
    final marketplaceApi = MarketplaceApiService(secureStorage: secureStorage);
    final artifactSyncApi =
        ArtifactSyncApiService(secureStorage: secureStorage);
    final enrollmentSyncService = EnrollmentSyncService(
      db: db,
      secureStorage: secureStorage,
      courseService: courseService,
      marketplaceApi: marketplaceApi,
      promptRepository: promptRepository,
      artifactApi: artifactSyncApi,
      courseArtifactService: courseArtifactService,
    );
    final sessionUploadCacheService = SessionUploadCacheService(db: db);
    final sessionService = SessionService(
      db,
      llmService,
      promptRepository,
      settingsRepository,
      llmLogRepository,
      courseArtifactService: courseArtifactService,
      sessionUploadCacheService: sessionUploadCacheService,
    );
    final artifactStore = StudentKpArtifactStoreService();
    final sessionSyncService = SessionSyncService(
      db: db,
      api: artifactSyncApi,
      artifactStore: artifactStore,
    );
    await sessionSyncService.ensureLocalCutoverInitialized();
    db.setSyncRelevantChangeCallback((change) async {
      await enrollmentSyncService.handleLocalSyncRelevantChange(change);
      await sessionSyncService.handleLocalSyncRelevantChange(change);
    });
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
      deviceIdentityService: deviceIdentityService,
      promptRepository: promptRepository,
      schemaValidator: schemaValidator,
      llmService: llmService,
      backupService: backupService,
      courseArtifactService: courseArtifactService,
      courseService: courseService,
      sessionService: sessionService,
      enrollmentSyncService: enrollmentSyncService,
      sessionSyncService: sessionSyncService,
      sessionUploadCacheService: sessionUploadCacheService,
      sttService: sttService,
      syncLogRepository: syncLogRepository,
      ttsService: ttsService,
      ttsLogRepository: ttsLogRepository,
      llmLogRepository: llmLogRepository,
    );
  }
}
