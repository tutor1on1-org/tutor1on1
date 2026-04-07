import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart' hide SyncItemState;
import '../llm/prompt_repository.dart';
import '../security/hash_utils.dart';
import 'artifact_sync_api_service.dart';
import 'course_artifact_service.dart';
import 'course_bundle_service.dart';
import 'course_service.dart';
import 'marketplace_api_service.dart';
import 'prompt_bundle_compat.dart';
import 'prompt_template_validator.dart';
import 'remote_student_identity_service.dart';
import 'remote_teacher_identity_service.dart';
import 'secure_storage_service.dart';
import 'sync_log_repository.dart';

class EnrollmentSyncService {
  EnrollmentSyncService({
    required AppDatabase db,
    required SecureStorageService secureStorage,
    required CourseService courseService,
    required MarketplaceApiService marketplaceApi,
    required PromptRepository promptRepository,
    ArtifactSyncApiService? artifactApi,
    CourseArtifactService? courseArtifactService,
  })  : _db = db,
        _secureStorage = secureStorage,
        _courseService = courseService,
        _api = marketplaceApi,
        _artifactApi =
            artifactApi ?? ArtifactSyncApiService(secureStorage: secureStorage),
        _promptRepository = promptRepository,
        _courseArtifactService = courseArtifactService;

  final AppDatabase _db;
  final SecureStorageService _secureStorage;
  final CourseService _courseService;
  final MarketplaceApiService _api;
  final ArtifactSyncApiService _artifactApi;
  final PromptRepository _promptRepository;
  final CourseArtifactService? _courseArtifactService;
  final PromptTemplateValidator _promptValidator = PromptTemplateValidator();
  final RemoteTeacherIdentityService _remoteTeacherIdentity =
      const RemoteTeacherIdentityService();
  final RemoteStudentIdentityService _remoteStudentIdentity =
      const RemoteStudentIdentityService();
  bool _syncing = false;
  int _localState2RefreshSuppressionDepth = 0;
  static final RegExp _versionSuffixPattern = RegExp(r'_(\d{10,})$');
  static const String _artifactClassCourseBundle = 'course_bundle';
  static const String _artifactState2Version = 'artifact_state2_v1';
  static const Duration _syncMinInterval = Duration(seconds: 60);
  static const String _syncDomainStudentEnrollments = 'enrollment_sync_student';
  static const String _syncDomainStudentCourseBundles =
      'enrollment_sync_student_bundle';
  static const String _syncDomainTeacherCourses = 'enrollment_sync_teacher';
  static const String _syncDomainTeacherCourseUpload =
      'enrollment_sync_teacher_upload';
  static const String _syncMetadataKindLocalState1 = 'local_state1';
  static const String _syncMetadataKindTeacherPromptTimestamps =
      'teacher_prompt_timestamps';
  static const String _syncMetadataDomainTeacherPromptTimestamps =
      'enrollment_sync_teacher_prompt_timestamps';

  bool get _localState2RefreshSuppressed =>
      _localState2RefreshSuppressionDepth > 0;

  Future<T> _runWithLocalState2RefreshSuppressed<T>(
    Future<T> Function() action,
  ) async {
    _localState2RefreshSuppressionDepth++;
    try {
      return await action();
    } finally {
      _localState2RefreshSuppressionDepth--;
    }
  }

  Future<void> refreshStoredLocalState2ForLocalUsers({
    required Set<int> localUserIds,
  }) async {
    final seen = <int>{};
    for (final localUserId in localUserIds) {
      if (localUserId <= 0 || !seen.add(localUserId)) {
        continue;
      }
      final user = await _db.getUserById(localUserId);
      if (user == null) {
        continue;
      }
      await refreshStoredLocalState2(currentUser: user);
    }
  }

  Future<void> handleLocalSyncRelevantChange(
    SyncRelevantChange change,
  ) async {
    if (_localState2RefreshSuppressed || change.isEmpty) {
      return;
    }
    await refreshStoredLocalState2ForLocalUsers(
      localUserIds: change.localUserIds,
    );
  }

  Future<void> _syncIfState2Mismatch({
    required int remoteUserId,
    required String domain,
    required Future<String> Function() readRemoteState2,
    required Future<void> Function() onMismatch,
    Future<void> Function()? onMatch,
  }) async {
    final remoteState2 = await readRemoteState2();
    final localState2 = (await _secureStorage.readLocalSyncState2(
          remoteUserId: remoteUserId,
          domain: domain,
        ))
            ?.trim() ??
        '';
    if (remoteState2 == localState2) {
      if (onMatch != null) {
        await onMatch();
      }
      return;
    }
    await onMismatch();
  }

  Future<void> refreshStoredLocalState2({required User currentUser}) async {
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return;
    }
    late final String domain;
    late final Map<String, String> state1FingerprintsByScope;
    if (currentUser.role == 'teacher') {
      domain = _syncDomainTeacherCourses;
      state1FingerprintsByScope = await _buildTeacherCourseState1Fingerprints(
        currentUser: currentUser,
        remoteUserId: remoteUserId,
      );
    } else {
      domain = _syncDomainStudentEnrollments;
      state1FingerprintsByScope =
          await _buildStudentEnrollmentState1Fingerprints(
        currentUser: currentUser,
        remoteUserId: remoteUserId,
      );
    }
    await _writeLocalState1Fingerprints(
      remoteUserId: remoteUserId,
      domain: domain,
      fingerprintsByScope: state1FingerprintsByScope,
    );
    final localState2 = await _buildCanonicalLocalState2(
      currentUser: currentUser,
      remoteUserId: remoteUserId,
    );
    await _secureStorage.writeLocalSyncState2(
      remoteUserId: remoteUserId,
      domain: domain,
      state2: localState2,
    );
  }

  Future<void> _writeLocalState1Fingerprints({
    required int remoteUserId,
    required String domain,
    required Map<String, String> fingerprintsByScope,
  }) async {
    final staleEntries = await (_db.select(_db.syncMetadataEntries)
          ..where(
            (tbl) =>
                tbl.remoteUserId.equals(remoteUserId) &
                tbl.kind.equals(_syncMetadataKindLocalState1) &
                tbl.domain.equals(domain),
          ))
        .get();
    final activeScopes = fingerprintsByScope.keys.toSet();
    await _db.transaction(() async {
      for (final stale in staleEntries) {
        if (activeScopes.contains(stale.scopeKey)) {
          continue;
        }
        await (_db.delete(_db.syncMetadataEntries)
              ..where(
                (tbl) =>
                    tbl.remoteUserId.equals(remoteUserId) &
                    tbl.kind.equals(_syncMetadataKindLocalState1) &
                    tbl.domain.equals(domain) &
                    tbl.scopeKey.equals(stale.scopeKey),
              ))
            .go();
      }
      for (final entry in fingerprintsByScope.entries) {
        await _db.into(_db.syncMetadataEntries).insertOnConflictUpdate(
              SyncMetadataEntriesCompanion.insert(
                remoteUserId: remoteUserId,
                kind: _syncMetadataKindLocalState1,
                domain: domain,
                scopeKey: entry.key,
                value: entry.value,
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );
      }
    });
  }

  Future<Map<String, String>> _readStoredLocalState1Fingerprints({
    required int remoteUserId,
    required String domain,
  }) async {
    final rows = await (_db.select(_db.syncMetadataEntries)
          ..where(
            (tbl) =>
                tbl.remoteUserId.equals(remoteUserId) &
                tbl.kind.equals(_syncMetadataKindLocalState1) &
                tbl.domain.equals(domain),
          ))
        .get();
    final fingerprintsByScope = <String, String>{};
    for (final row in rows) {
      final scopeKey = row.scopeKey.trim();
      final value = row.value.trim();
      if (scopeKey.isEmpty || value.isEmpty) {
        continue;
      }
      fingerprintsByScope[scopeKey] = value;
    }
    return fingerprintsByScope;
  }

  Map<String, String> _buildRemoteTeacherCoursePayloadFingerprints(
    List<TeacherCourseSummary> remoteCourses,
  ) {
    final fingerprintsByScope = <String, String>{};
    for (final remoteCourse in remoteCourses) {
      if (remoteCourse.courseId <= 0) {
        continue;
      }
      fingerprintsByScope[_localState1ScopeKeyForRemoteCourse(
        remoteCourse.courseId,
      )] = _buildTeacherCourseItemFingerprint(
        remoteCourseId: remoteCourse.courseId,
        localCourseVersionId: null,
        bundleHash: remoteCourse.latestBundleHash,
      );
    }
    return fingerprintsByScope;
  }

  Map<String, String> _buildRemoteTeacherCourseArtifactFingerprints(
    List<ArtifactState1Item> items,
  ) {
    final fingerprintsByScope = <String, String>{};
    for (final item in items) {
      if (item.artifactClass != _artifactClassCourseBundle ||
          item.courseId <= 0) {
        continue;
      }
      fingerprintsByScope[_localState1ScopeKeyForRemoteCourse(
        item.courseId,
      )] = _buildTeacherCourseItemFingerprint(
        remoteCourseId: item.courseId,
        localCourseVersionId: null,
        bundleHash: item.sha256,
      );
    }
    return fingerprintsByScope;
  }

  Map<String, String> _buildRemoteStudentEnrollmentArtifactFingerprints(
    List<ArtifactState1Item> items,
  ) {
    final fingerprintsByScope = <String, String>{};
    for (final item in items) {
      if (item.artifactClass != _artifactClassCourseBundle ||
          item.courseId <= 0) {
        continue;
      }
      fingerprintsByScope[_localState1ScopeKeyForRemoteCourse(
        item.courseId,
      )] = _buildStudentEnrollmentItemFingerprint(
        remoteCourseId: item.courseId,
        teacherRemoteUserId: item.teacherUserId,
        bundleHash: item.sha256,
      );
    }
    return fingerprintsByScope;
  }

  List<TeacherCourseSummary> _resolveTeacherCoursesFromArtifacts({
    required List<ArtifactState1Item> artifactItems,
    required List<TeacherCourseSummary> remoteCourses,
  }) {
    final remoteCoursesById = <int, TeacherCourseSummary>{
      for (final remoteCourse in remoteCourses)
        if (remoteCourse.courseId > 0) remoteCourse.courseId: remoteCourse,
    };
    final resolved = <TeacherCourseSummary>[];
    final seenCourseIds = <int>{};
    for (final item in artifactItems) {
      if (item.artifactClass != _artifactClassCourseBundle ||
          item.courseId <= 0 ||
          item.bundleVersionId <= 0 ||
          !seenCourseIds.add(item.courseId)) {
        continue;
      }
      final remoteCourse = remoteCoursesById[item.courseId];
      if (remoteCourse == null) {
        throw StateError(
          'Course bundle artifact ${item.artifactId} is missing teacher '
          'course metadata for course ${item.courseId}.',
        );
      }
      resolved.add(
        TeacherCourseSummary(
          courseId: remoteCourse.courseId,
          subject: remoteCourse.subject,
          grade: remoteCourse.grade,
          description: remoteCourse.description,
          visibility: remoteCourse.visibility,
          approvalStatus: remoteCourse.approvalStatus,
          publishedAt: remoteCourse.publishedAt,
          latestBundleVersionId: item.bundleVersionId,
          latestBundleHash: item.sha256,
          status: remoteCourse.status,
          subjectLabels: remoteCourse.subjectLabels,
        ),
      );
    }
    return resolved;
  }

  List<EnrollmentSummary> _resolveEnrollmentsFromArtifacts({
    required List<ArtifactState1Item> artifactItems,
    required List<EnrollmentSummary> enrollments,
  }) {
    final enrollmentsByCourseId = <int, EnrollmentSummary>{
      for (final enrollment in enrollments)
        if (enrollment.courseId > 0) enrollment.courseId: enrollment,
    };
    final resolved = <EnrollmentSummary>[];
    final seenCourseIds = <int>{};
    for (final item in artifactItems) {
      if (item.artifactClass != _artifactClassCourseBundle ||
          item.courseId <= 0 ||
          item.bundleVersionId <= 0 ||
          !seenCourseIds.add(item.courseId)) {
        continue;
      }
      final enrollment = enrollmentsByCourseId[item.courseId];
      if (enrollment == null) {
        throw StateError(
          'Course bundle artifact ${item.artifactId} is missing student '
          'enrollment metadata for course ${item.courseId}.',
        );
      }
      final teacherRemoteUserId =
          item.teacherUserId > 0 ? item.teacherUserId : enrollment.teacherId;
      if (enrollment.teacherId > 0 &&
          item.teacherUserId > 0 &&
          enrollment.teacherId != item.teacherUserId) {
        throw StateError(
          'Course bundle artifact ${item.artifactId} teacher id mismatch. '
          'artifact=${item.teacherUserId} enrollment=${enrollment.teacherId}',
        );
      }
      resolved.add(
        EnrollmentSummary(
          enrollmentId: enrollment.enrollmentId,
          courseId: enrollment.courseId,
          teacherId: teacherRemoteUserId,
          status: enrollment.status,
          assignedAt: enrollment.assignedAt,
          courseSubject: enrollment.courseSubject,
          teacherName: enrollment.teacherName,
          latestBundleVersionId: item.bundleVersionId,
          latestBundleHash: item.sha256,
        ),
      );
    }
    return resolved;
  }

  List<T> _filterChangedState1Items<T>({
    required List<T> remoteItems,
    required Map<String, String> localFingerprintsByScope,
    required String? Function(T item) scopeKeyOf,
    required String Function(T item) fingerprintOf,
  }) {
    final changed = <T>[];
    for (final item in remoteItems) {
      final scopeKey = scopeKeyOf(item)?.trim() ?? '';
      if (scopeKey.isEmpty) {
        continue;
      }
      final remoteFingerprint = fingerprintOf(item).trim();
      final localFingerprint = localFingerprintsByScope[scopeKey]?.trim() ?? '';
      if (remoteFingerprint != localFingerprint) {
        changed.add(item);
      }
    }
    return changed;
  }

  Set<int> _extractRemovedRemoteCourseIds({
    required Map<String, String> localFingerprintsByScope,
    required Map<String, String> remoteFingerprintsByScope,
  }) {
    final removedRemoteCourseIds = <int>{};
    for (final scopeKey in localFingerprintsByScope.keys) {
      if (remoteFingerprintsByScope.containsKey(scopeKey)) {
        continue;
      }
      if (!scopeKey.startsWith('remote-course:')) {
        continue;
      }
      final remoteCourseId =
          int.tryParse(scopeKey.substring('remote-course:'.length));
      if (remoteCourseId != null && remoteCourseId > 0) {
        removedRemoteCourseIds.add(remoteCourseId);
      }
    }
    return removedRemoteCourseIds;
  }

  bool _hasLocalOnlyTeacherCourseDiff(
    Map<String, String> localFingerprintsByScope,
  ) {
    for (final entry in localFingerprintsByScope.entries) {
      if (!entry.key.startsWith('local-course:')) {
        continue;
      }
      if (entry.value.trim().isEmpty) {
        continue;
      }
      return true;
    }
    return false;
  }

  String _localState1ScopeKeyForRemoteCourse(int remoteCourseId) {
    return 'remote-course:$remoteCourseId';
  }

  String _localState1ScopeKeyForLocalCourse(int courseVersionId) {
    return 'local-course:$courseVersionId';
  }

  Future<void> recordTeacherMarketplaceUpload({
    required User currentUser,
    required int remoteCourseId,
    required int bundleVersionId,
    required String bundleHash,
  }) async {
    final remoteUserId = currentUser.remoteUserId;
    if (currentUser.role != 'teacher' ||
        remoteUserId == null ||
        remoteUserId <= 0 ||
        remoteCourseId <= 0) {
      return;
    }
    final now = DateTime.now().toUtc();
    await _writeCourseSyncState(
      remoteUserId: remoteUserId,
      domain: _syncDomainTeacherCourseUpload,
      remoteCourseId: remoteCourseId,
      bundleVersionId: bundleVersionId,
      contentHash: bundleHash,
      lastChangedAt: now,
      lastSyncedAt: now,
    );
    await refreshStoredLocalState2(currentUser: currentUser);
  }

  Future<void> recordStudentMarketplaceDownload({
    required User currentUser,
    required int remoteCourseId,
    required int bundleVersionId,
    required String bundleHash,
  }) async {
    final remoteUserId = currentUser.remoteUserId;
    if (currentUser.role != 'student' ||
        remoteUserId == null ||
        remoteUserId <= 0 ||
        remoteCourseId <= 0) {
      return;
    }
    await _writeStudentCourseSyncState(
      remoteUserId: remoteUserId,
      remoteCourseId: remoteCourseId,
      bundleVersionId: bundleVersionId,
      bundleHash: bundleHash,
    );
    await refreshStoredLocalState2(currentUser: currentUser);
  }

  Future<SyncRunStats> forcePullFromServer({required User currentUser}) async {
    final stats = SyncRunStats();
    if (_syncing) {
      return stats;
    }
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return stats;
    }
    final nowUtc = DateTime.now().toUtc();
    final summary = _SyncTransferSummary();
    _syncing = true;
    try {
      await _runWithLocalState2RefreshSuppressed(() async {
        await _resetForcePullState(
          remoteUserId: remoteUserId,
          role: currentUser.role,
        );
        if (currentUser.role == 'student') {
          final changed =
              await _autoApproveLegacyCoursesWithoutTeacher(currentUser.id);
          if (changed) {
            await refreshStoredLocalState2(currentUser: currentUser);
          }
        }
        if (currentUser.role == 'teacher') {
          await _runCategoryIfDue(
            remoteUserId: remoteUserId,
            domain: _syncDomainTeacherCourses,
            nowUtc: nowUtc,
            force: true,
            action: () async {
              final localFingerprintsByScope =
                  await _readStoredLocalState1Fingerprints(
                remoteUserId: remoteUserId,
                domain: _syncDomainTeacherCourses,
              );
              final remoteState1 = await _artifactApi.getState1(
                artifactClass: _artifactClassCourseBundle,
              );
              final removedRemoteCourseIds = _extractRemovedRemoteCourseIds(
                localFingerprintsByScope: localFingerprintsByScope,
                remoteFingerprintsByScope:
                    _buildRemoteTeacherCourseArtifactFingerprints(
                  remoteState1.items,
                ),
              );
              final remoteCourses = _resolveTeacherCoursesFromArtifacts(
                artifactItems: remoteState1.items,
                remoteCourses: await _api.listTeacherCourses(),
              );
              await _syncTeacherCourses(
                currentUser: currentUser,
                remoteUserId: remoteUserId,
                remoteCourses: remoteCourses,
                changedRemoteCourses: remoteCourses,
                removedRemoteCourseIds: removedRemoteCourseIds,
                summary: summary,
              );
            },
          );
        } else {
          await _runCategoryIfDue(
            remoteUserId: remoteUserId,
            domain: _syncDomainStudentEnrollments,
            nowUtc: nowUtc,
            force: true,
            action: () async {
              final localFingerprintsByScope =
                  await _readStoredLocalState1Fingerprints(
                remoteUserId: remoteUserId,
                domain: _syncDomainStudentEnrollments,
              );
              final remoteState1 = await _artifactApi.getState1(
                artifactClass: _artifactClassCourseBundle,
              );
              final removedRemoteCourseIds = _extractRemovedRemoteCourseIds(
                localFingerprintsByScope: localFingerprintsByScope,
                remoteFingerprintsByScope:
                    _buildRemoteStudentEnrollmentArtifactFingerprints(
                  remoteState1.items,
                ),
              );
              final remoteEnrollments = _resolveEnrollmentsFromArtifacts(
                artifactItems: remoteState1.items,
                enrollments: await _api.listEnrollments(),
              );
              await _syncStudentEnrollments(
                currentUser: currentUser,
                remoteUserId: remoteUserId,
                enrollments: remoteEnrollments,
                allRemoteEnrollments: remoteEnrollments,
                removedRemoteCourseIds: removedRemoteCourseIds,
                summary: summary,
              );
            },
          );
        }
      });
      return summary.toStats();
    } finally {
      _syncing = false;
    }
  }

  Future<SyncRunStats> syncIfReady({required User currentUser}) async {
    final stats = SyncRunStats();
    if (_syncing) {
      return stats;
    }
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      return stats;
    }
    final nowUtc = DateTime.now().toUtc();
    final summary = _SyncTransferSummary();
    _syncing = true;
    try {
      await _runWithLocalState2RefreshSuppressed(() async {
        if (currentUser.role == 'student') {
          final changed =
              await _autoApproveLegacyCoursesWithoutTeacher(currentUser.id);
          if (changed) {
            await refreshStoredLocalState2(currentUser: currentUser);
          }
        }
        if (currentUser.role == 'teacher') {
          await _runCategoryIfDue(
            remoteUserId: remoteUserId,
            domain: _syncDomainTeacherCourses,
            nowUtc: nowUtc,
            force: false,
            action: () => _syncIfState2Mismatch(
              remoteUserId: remoteUserId,
              domain: _syncDomainTeacherCourses,
              readRemoteState2: () => _artifactApi.getState2(
                artifactClass: _artifactClassCourseBundle,
              ),
              onMismatch: () async {
                final remoteState1 = await _artifactApi.getState1(
                  artifactClass: _artifactClassCourseBundle,
                );
                final localFingerprintsByScope =
                    await _readStoredLocalState1Fingerprints(
                  remoteUserId: remoteUserId,
                  domain: _syncDomainTeacherCourses,
                );
                final remoteFingerprintsByScope =
                    _buildRemoteTeacherCourseArtifactFingerprints(
                  remoteState1.items,
                );
                final changedRemoteCourses = _filterChangedState1Items(
                  remoteItems: remoteState1.items,
                  localFingerprintsByScope: localFingerprintsByScope,
                  scopeKeyOf: (item) => item.courseId > 0
                      ? _localState1ScopeKeyForRemoteCourse(item.courseId)
                      : null,
                  fingerprintOf: (item) => _buildTeacherCourseItemFingerprint(
                    remoteCourseId: item.courseId,
                    localCourseVersionId: null,
                    bundleHash: item.sha256,
                  ),
                );
                final removedRemoteCourseIds = _extractRemovedRemoteCourseIds(
                  localFingerprintsByScope: localFingerprintsByScope,
                  remoteFingerprintsByScope: remoteFingerprintsByScope,
                );
                if (changedRemoteCourses.isEmpty &&
                    removedRemoteCourseIds.isEmpty &&
                    !_hasLocalOnlyTeacherCourseDiff(
                      localFingerprintsByScope,
                    )) {
                  throw StateError(
                    'Stored teacher sync state drifted from canonical local '
                    'state1. Sync-time repair is not allowed.',
                  );
                }
                final remoteCourses = _resolveTeacherCoursesFromArtifacts(
                  artifactItems: remoteState1.items,
                  remoteCourses: await _api.listTeacherCourses(),
                );
                await _syncTeacherCourses(
                  currentUser: currentUser,
                  remoteUserId: remoteUserId,
                  remoteCourses: remoteCourses,
                  changedRemoteCourses: _resolveTeacherCoursesFromArtifacts(
                    artifactItems: changedRemoteCourses,
                    remoteCourses: remoteCourses,
                  ),
                  removedRemoteCourseIds: removedRemoteCourseIds,
                  summary: summary,
                );
              },
            ),
          );
        } else {
          await _runCategoryIfDue(
            remoteUserId: remoteUserId,
            domain: _syncDomainStudentEnrollments,
            nowUtc: nowUtc,
            force: false,
            action: () => _syncIfState2Mismatch(
              remoteUserId: remoteUserId,
              domain: _syncDomainStudentEnrollments,
              readRemoteState2: () => _artifactApi.getState2(
                artifactClass: _artifactClassCourseBundle,
              ),
              onMismatch: () async {
                final remoteState1 = await _artifactApi.getState1(
                  artifactClass: _artifactClassCourseBundle,
                );
                final localFingerprintsByScope =
                    await _readStoredLocalState1Fingerprints(
                  remoteUserId: remoteUserId,
                  domain: _syncDomainStudentEnrollments,
                );
                final remoteFingerprintsByScope =
                    _buildRemoteStudentEnrollmentArtifactFingerprints(
                  remoteState1.items,
                );
                final changedEnrollments = _filterChangedState1Items(
                  remoteItems: remoteState1.items,
                  localFingerprintsByScope: localFingerprintsByScope,
                  scopeKeyOf: (item) => item.courseId > 0
                      ? _localState1ScopeKeyForRemoteCourse(
                          item.courseId,
                        )
                      : null,
                  fingerprintOf: (item) =>
                      _buildStudentEnrollmentItemFingerprint(
                    remoteCourseId: item.courseId,
                    teacherRemoteUserId: item.teacherUserId,
                    bundleHash: item.sha256,
                  ),
                );
                final removedRemoteCourseIds = _extractRemovedRemoteCourseIds(
                  localFingerprintsByScope: localFingerprintsByScope,
                  remoteFingerprintsByScope: remoteFingerprintsByScope,
                );
                if (changedEnrollments.isEmpty &&
                    removedRemoteCourseIds.isEmpty) {
                  throw StateError(
                    'Stored student enrollment sync state drifted from '
                    'canonical local state1. Sync-time repair is not allowed.',
                  );
                }
                final allRemoteEnrollments = _resolveEnrollmentsFromArtifacts(
                  artifactItems: remoteState1.items,
                  enrollments: await _api.listEnrollments(),
                );
                await _syncStudentEnrollments(
                  currentUser: currentUser,
                  remoteUserId: remoteUserId,
                  enrollments: _resolveEnrollmentsFromArtifacts(
                    artifactItems: changedEnrollments,
                    enrollments: allRemoteEnrollments,
                  ),
                  allRemoteEnrollments: allRemoteEnrollments,
                  removedRemoteCourseIds: removedRemoteCourseIds,
                  summary: summary,
                );
              },
            ),
          );
        }
      });
      return summary.toStats();
    } finally {
      _syncing = false;
    }
  }

  Future<CourseVersion> pullLatestTeacherCourse({
    required User currentUser,
    required CourseVersion course,
  }) async {
    if (currentUser.role != 'teacher') {
      throw StateError('Only teachers can pull latest server course bundles.');
    }
    final remoteUserId = currentUser.remoteUserId;
    if (remoteUserId == null || remoteUserId <= 0) {
      throw StateError('Teacher remote user id is missing.');
    }

    return _runWithLocalState2RefreshSuppressed(() async {
      final teacherCourses = await _api.listTeacherCourses();
      final normalizedCourseName = _normalizeCourseName(course.subject);
      var remoteCourseId = await _db.getRemoteCourseId(course.id);
      TeacherCourseSummary? remoteCourse;
      if (remoteCourseId != null && remoteCourseId > 0) {
        for (final candidate in teacherCourses) {
          if (candidate.courseId == remoteCourseId) {
            remoteCourse = candidate;
            break;
          }
        }
      }
      if (remoteCourse == null) {
        for (final candidate in teacherCourses) {
          if (_normalizeCourseName(candidate.subject) == normalizedCourseName) {
            remoteCourse = candidate;
            remoteCourseId = candidate.courseId;
            break;
          }
        }
      }
      if (remoteCourse == null ||
          remoteCourseId == null ||
          remoteCourseId <= 0) {
        throw StateError(
          'No remote server course found for "${course.subject}".',
        );
      }
      await _db.upsertCourseRemoteLink(
        courseVersionId: course.id,
        remoteCourseId: remoteCourseId,
      );

      final latestBundleVersionId = remoteCourse.latestBundleVersionId ?? 0;
      if (latestBundleVersionId <= 0) {
        throw StateError(
          'Remote server course "${remoteCourse.subject}" has no bundle to pull.',
        );
      }
      final remoteBundle = await _resolveRemoteBundleInfo(
        remoteCourseId: remoteCourseId,
        courseSubject: remoteCourse.subject,
        latestBundleVersionId: latestBundleVersionId,
        latestBundleHash: remoteCourse.latestBundleHash,
      );
      final pulledCourse = await _downloadAndImportTeacherCourse(
        currentUser: currentUser,
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourseId,
        courseSubject: remoteCourse.subject,
        bundleHash: remoteBundle.hash,
        bundleVersionId: remoteBundle.bundleVersionId,
        existingCourseVersionId: course.id,
        summary: _SyncTransferSummary(),
      );
      await refreshStoredLocalState2(currentUser: currentUser);
      return pulledCourse;
    });
  }

  Future<void> _runCategoryIfDue({
    required int remoteUserId,
    required String domain,
    required DateTime nowUtc,
    required bool force,
    required Future<void> Function() action,
  }) async {
    if (!force) {
      final lastRun = await _secureStorage.readSyncRunAt(
        remoteUserId: remoteUserId,
        domain: domain,
      );
      if (lastRun != null &&
          nowUtc.difference(lastRun.toUtc()) < _syncMinInterval) {
        return;
      }
    }
    await action();
    await _secureStorage.writeSyncRunAt(
      remoteUserId: remoteUserId,
      domain: domain,
      runAt: nowUtc,
    );
  }

  Future<void> _resetForcePullState({
    required int remoteUserId,
    required String role,
  }) async {
    if (role == 'teacher') {
      await _secureStorage.clearSyncDomainState(
        remoteUserId: remoteUserId,
        domain: _syncDomainTeacherCourses,
        clearItemStates: false,
      );
      return;
    }
    await _secureStorage.clearSyncDomainState(
      remoteUserId: remoteUserId,
      domain: _syncDomainStudentEnrollments,
      clearItemStates: false,
    );
  }

  Future<bool> _autoApproveLegacyCoursesWithoutTeacher(int studentId) async {
    var changed = false;
    final assignedCourses = await _db.getAssignedCoursesForStudent(studentId);
    for (final course in assignedCourses) {
      final teacher = await _db.getUserById(course.teacherId);
      if (teacher != null && teacher.role == 'teacher') {
        continue;
      }
      final remoteCourseId = await _db.getRemoteCourseId(course.id);
      if (remoteCourseId != null && remoteCourseId > 0) {
        continue;
      }
      await _db.deleteStudentCourseData(
        studentId: studentId,
        courseVersionId: course.id,
        removeAssignment: true,
      );
      await _cleanupCourseIfOrphaned(course.id);
      changed = true;
    }
    return changed;
  }

  Future<void> _syncStudentEnrollments({
    required User currentUser,
    required int remoteUserId,
    required List<EnrollmentSummary> enrollments,
    required List<EnrollmentSummary> allRemoteEnrollments,
    required Set<int> removedRemoteCourseIds,
    required _SyncTransferSummary summary,
  }) async {
    for (final enrollment in enrollments) {
      if (enrollment.courseId <= 0) {
        continue;
      }
      final localTeacherId =
          await _remoteTeacherIdentity.resolveOrCreateLocalTeacherId(
        db: _db,
        remoteTeacherId: enrollment.teacherId,
        usernameHint: enrollment.teacherName,
      );
      final latestBundleVersionId = enrollment.latestBundleVersionId;
      if (latestBundleVersionId == null || latestBundleVersionId <= 0) {
        final existingCourseVersionId =
            await _db.getCourseVersionIdForRemoteCourse(enrollment.courseId);
        if (existingCourseVersionId != null) {
          await _ensureCourseTeacher(
            courseVersionId: existingCourseVersionId,
            expectedTeacherId: localTeacherId,
          );
        }
        continue;
      }
      var existingCourseVersionId =
          await _db.getCourseVersionIdForRemoteCourse(enrollment.courseId);
      if (existingCourseVersionId != null) {
        await _ensureCourseTeacher(
          courseVersionId: existingCourseVersionId,
          expectedTeacherId: localTeacherId,
        );
      }
      final remoteBundle = await _resolveRemoteBundleInfo(
        remoteCourseId: enrollment.courseId,
        courseSubject: enrollment.courseSubject,
        latestBundleVersionId: latestBundleVersionId,
        latestBundleHash: enrollment.latestBundleHash,
      );
      final syncResult = await _syncRemoteCourseFromServer(
        remoteUserId: remoteUserId,
        remoteCourseId: enrollment.courseId,
        courseSubject: enrollment.courseSubject,
        latestBundleVersionId: remoteBundle.bundleVersionId,
        latestBundleHash: remoteBundle.hash,
        syncStateDomain: _syncDomainStudentCourseBundles,
        readLocalHash: (_, __, syncState) async =>
            _readStudentCourseSyncHash(syncState),
        onHashesMatch: (_, __, ___, ____) async {},
        shouldTrustLinkedCourse: (_, installedVersion, syncState) =>
            _hasTrustedStudentBundleIdentity(
          installedVersion: installedVersion,
          syncState: syncState,
        ),
        importRemoteCourse: (resolvedCourseVersionId) =>
            _downloadAndImportCourse(
          currentUser: currentUser,
          enrollment: enrollment,
          bundleVersionId: remoteBundle.bundleVersionId,
          existingCourseVersionId: resolvedCourseVersionId,
          localTeacherId: localTeacherId,
          bundleHash: remoteBundle.hash,
          summary: summary,
        ),
        onHashesDiffer: (localCourse, __, ___, ____) =>
            _downloadAndImportCourse(
          currentUser: currentUser,
          enrollment: enrollment,
          bundleVersionId: remoteBundle.bundleVersionId,
          existingCourseVersionId: localCourse.id,
          localTeacherId: localTeacherId,
          bundleHash: remoteBundle.hash,
          summary: summary,
        ),
      );
      final syncedCourse = syncResult.course;
      existingCourseVersionId = syncedCourse.id;
      await _ensureCourseTeacher(
        courseVersionId: existingCourseVersionId,
        expectedTeacherId: localTeacherId,
      );
      await _db.upsertCourseRemoteLink(
        courseVersionId: existingCourseVersionId,
        remoteCourseId: enrollment.courseId,
      );
      final replacedCourseVersionId = syncResult.replacedCourseVersionId;
      if (replacedCourseVersionId != null &&
          replacedCourseVersionId != existingCourseVersionId) {
        await _db.migrateStudentCourseData(
          studentId: currentUser.id,
          fromCourseVersionId: replacedCourseVersionId,
          toCourseVersionId: existingCourseVersionId,
        );
        await _cleanupCourseIfOrphaned(replacedCourseVersionId);
      }
      await _db.assignStudent(
        studentId: currentUser.id,
        courseVersionId: existingCourseVersionId,
      );
      await _ensureCourseSubject(
        courseVersionId: existingCourseVersionId,
        expectedSubject: enrollment.courseSubject,
      );
      await _writeStudentCourseSyncState(
        remoteUserId: remoteUserId,
        remoteCourseId: enrollment.courseId,
        bundleVersionId: remoteBundle.bundleVersionId,
        bundleHash: remoteBundle.hash,
      );
    }

    for (final remoteCourseId in removedRemoteCourseIds) {
      await _removeRemoteCourseFromStudent(
        localStudentId: currentUser.id,
        remoteCourseId: remoteCourseId,
      );
    }
    await _repairStudentStaleDuplicateCourses(
      currentUser: currentUser,
      enrollments: allRemoteEnrollments,
    );
    await refreshStoredLocalState2(currentUser: currentUser);
  }

  Future<File> _downloadCourseBundleArtifactToFile({
    required int remoteCourseId,
    required String courseSubject,
    required String expectedSha256,
  }) async {
    final bundleService = CourseBundleService();
    final artifactId = 'course_bundle:$remoteCourseId';
    final downloaded = await _artifactApi.downloadArtifact(artifactId);
    final echoedArtifactId = downloaded.artifactId.trim();
    if (echoedArtifactId.isNotEmpty && echoedArtifactId != artifactId) {
      throw StateError(
        'Downloaded course artifact id mismatch. expected=$artifactId '
        'actual=${downloaded.artifactId}',
      );
    }
    final expectedHash = expectedSha256.trim();
    final targetPath = await bundleService.createTempBundlePath(
      label: courseSubject,
    );
    final bundleFile = File(targetPath);
    await bundleFile.parent.create(recursive: true);
    await bundleFile.writeAsBytes(downloaded.bytes, flush: true);
    final computedHash = await bundleService.computeBundleByteHash(bundleFile);
    if (expectedHash.isNotEmpty && computedHash != expectedHash) {
      await bundleFile.delete();
      throw StateError(
        'Downloaded course artifact sha256 mismatch for $artifactId. '
        'expected=$expectedHash actual=$computedHash',
      );
    }
    final echoedHash = downloaded.sha256.trim();
    if (echoedHash.isNotEmpty && echoedHash != computedHash) {
      await bundleFile.delete();
      throw StateError(
        'Downloaded course artifact file sha256 mismatch for $artifactId. '
        'header=$echoedHash computed=$computedHash',
      );
    }
    return bundleFile;
  }

  Future<CourseVersion> _downloadAndImportCourse({
    required User currentUser,
    required EnrollmentSummary enrollment,
    required int bundleVersionId,
    required int? existingCourseVersionId,
    required int localTeacherId,
    required String bundleHash,
    required _SyncTransferSummary summary,
  }) async {
    final bundleService = CourseBundleService();
    File? bundleFile;
    try {
      bundleFile = await _downloadCourseBundleArtifactToFile(
        remoteCourseId: enrollment.courseId,
        courseSubject: enrollment.courseSubject,
        expectedSha256: bundleHash,
      );
      summary.downloaded.add(
        SyncTransferLogItem(
          direction: 'download',
          fileName: p.basename(bundleFile.path),
          sizeBytes: bundleFile.lengthSync(),
          courseSubject: enrollment.courseSubject,
          remoteCourseId: enrollment.courseId,
          bundleVersionId: bundleVersionId,
          hash: bundleHash,
          source: 'student_enrollment_sync',
        ),
      );
      await bundleService.validateBundleForImport(bundleFile);
      final promptMetadata =
          await bundleService.readPromptMetadataFromBundleFile(bundleFile);
      final folderPath = await bundleService.extractBundleFromFile(
        bundleFile: bundleFile,
        courseName: enrollment.courseSubject,
      );
      final preview = await _courseService.previewCourseLoad(
        folderPath: folderPath,
        courseVersionId: existingCourseVersionId,
        courseNameOverride: enrollment.courseSubject,
      );
      if (!preview.success) {
        throw StateError(preview.message);
      }
      final mode = existingCourseVersionId == null
          ? CourseReloadMode.fresh
          : CourseReloadMode.override;
      final result = await _courseService.applyCourseLoad(
        teacherId: localTeacherId,
        preview: preview,
        mode: mode,
        rebuildCourseArtifacts: _courseArtifactService == null,
      );
      if (!result.success || result.course == null) {
        throw StateError(result.message);
      }
      if (promptMetadata != null) {
        await _applyPromptMetadataForStudent(
          currentUser: currentUser,
          metadata: promptMetadata,
          course: result.course!,
        );
      }
      final remoteHash =
          await bundleService.computeBundleSemanticHash(bundleFile);
      if (_courseArtifactService != null) {
        final artifactFolderPath =
            (result.course!.sourcePath ?? '').trim().isNotEmpty
                ? result.course!.sourcePath!.trim()
                : folderPath;
        await _courseArtifactService.storeImportedContentBundle(
          courseVersionId: result.course!.id,
          folderPath: artifactFolderPath,
          bundleFile: bundleFile,
          buildChapterArtifacts: false,
        );
        final localHash = await _courseArtifactService.computeUploadHash(
          courseVersionId: result.course!.id,
          promptMetadata: promptMetadata,
        );
        if (localHash.trim() != remoteHash.trim()) {
          throw StateError(
            'Imported student bundle fingerprint mismatch after local '
            'materialization. remote=$remoteHash local=$localHash',
          );
        }
      }
      return result.course!;
    } finally {
      if (bundleFile != null && bundleFile.existsSync()) {
        await bundleFile.delete();
      }
    }
  }

  Future<void> _removeRemoteCourseFromStudent({
    required int localStudentId,
    required int remoteCourseId,
  }) async {
    final courseVersionId =
        await _db.getCourseVersionIdForRemoteCourse(remoteCourseId);
    if (courseVersionId == null) {
      return;
    }
    await _db.deleteStudentCourseData(
      studentId: localStudentId,
      courseVersionId: courseVersionId,
      removeAssignment: true,
    );
    await _cleanupCourseIfOrphaned(courseVersionId);
  }

  Future<void> _cleanupCourseIfOrphaned(int courseVersionId) async {
    final assignments = await _db.getAssignmentsForCourse(courseVersionId);
    if (assignments.isNotEmpty) {
      return;
    }
    await _db.deleteCourseVersion(courseVersionId);
  }

  Future<void> _syncTeacherCourses({
    required User currentUser,
    required int remoteUserId,
    required List<TeacherCourseSummary> remoteCourses,
    required List<TeacherCourseSummary> changedRemoteCourses,
    required Set<int> removedRemoteCourseIds,
    required _SyncTransferSummary summary,
  }) async {
    final firstSync = await _secureStorage.readSyncRunAt(
          remoteUserId: remoteUserId,
          domain: _syncDomainTeacherCourses,
        ) ==
        null;
    await _detachRemovedTeacherCourses(
      teacherId: currentUser.id,
      removedRemoteCourseIds: removedRemoteCourseIds,
    );
    await _reconcileTeacherCourseMetadata(
      currentUser: currentUser,
      remoteCourses: remoteCourses,
    );
    await _pullTeacherCoursesFromServer(
      currentUser: currentUser,
      remoteUserId: remoteUserId,
      remoteCourses: changedRemoteCourses,
      initializeOnly: firstSync,
      summary: summary,
    );
    if (firstSync) {
      await _cleanupTeacherLocalDuplicates(currentUser.id);
      await refreshStoredLocalState2(currentUser: currentUser);
      return;
    }
    await _uploadLocalTeacherCourses(
      currentUser: currentUser,
      remoteUserId: remoteUserId,
      remoteCourses: remoteCourses,
      summary: summary,
    );
    final refreshedRemoteState1 = await _artifactApi.getState1(
      artifactClass: _artifactClassCourseBundle,
    );
    final previousRemoteFingerprintsByScope =
        _buildRemoteTeacherCoursePayloadFingerprints(remoteCourses);
    final refreshedChangedRemoteCourses = _filterChangedState1Items(
      remoteItems: refreshedRemoteState1.items,
      localFingerprintsByScope: previousRemoteFingerprintsByScope,
      scopeKeyOf: (item) => item.courseId > 0
          ? _localState1ScopeKeyForRemoteCourse(item.courseId)
          : null,
      fingerprintOf: (item) => _buildTeacherCourseItemFingerprint(
        remoteCourseId: item.courseId,
        localCourseVersionId: null,
        bundleHash: item.sha256,
      ),
    );
    final refreshedRemoteCourses = _resolveTeacherCoursesFromArtifacts(
      artifactItems: refreshedRemoteState1.items,
      remoteCourses: await _api.listTeacherCourses(),
    );
    await _reconcileTeacherCourseMetadata(
      currentUser: currentUser,
      remoteCourses: refreshedRemoteCourses,
    );
    await _pullTeacherCoursesFromServer(
      currentUser: currentUser,
      remoteUserId: remoteUserId,
      remoteCourses: _resolveTeacherCoursesFromArtifacts(
        artifactItems: refreshedChangedRemoteCourses,
        remoteCourses: refreshedRemoteCourses,
      ),
      initializeOnly: false,
      summary: summary,
    );
    await _cleanupTeacherLocalDuplicates(currentUser.id);
    await refreshStoredLocalState2(currentUser: currentUser);
  }

  Future<Map<String, String>> _buildStudentEnrollmentState1Fingerprints({
    required User currentUser,
    required int remoteUserId,
  }) async {
    final assignedRemoteCourses =
        await _db.getAssignedRemoteCoursesForStudent(currentUser.id);
    final fingerprintsByScope = <String, String>{};
    for (final info in assignedRemoteCourses) {
      final course = await _db.getCourseVersionById(info.courseVersionId);
      if (course == null) {
        continue;
      }
      final teacher = await _db.getUserById(course.teacherId);
      final syncState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainStudentCourseBundles,
        scopeKey: _teacherCourseScopeKey(info.remoteCourseId),
      );
      fingerprintsByScope[_localState1ScopeKeyForRemoteCourse(
        info.remoteCourseId,
      )] = _buildStudentEnrollmentItemFingerprint(
        remoteCourseId: info.remoteCourseId,
        teacherRemoteUserId: teacher?.remoteUserId ?? 0,
        bundleHash: syncState?.contentHash ?? '',
      );
    }
    return fingerprintsByScope;
  }

  Future<Map<String, String>> _buildTeacherCourseState1Fingerprints({
    required User currentUser,
    required int remoteUserId,
  }) async {
    final localCourses = await _db.getCourseVersionsForTeacher(currentUser.id);
    final fingerprintsByScope = <String, String>{};
    for (final course in localCourses) {
      final remoteCourseId = await _db.getRemoteCourseId(course.id);
      final localHash = await _resolveTeacherCourseLocalState1Hash(
        teacher: currentUser,
        remoteUserId: remoteUserId,
        course: course,
        remoteCourseId: remoteCourseId,
      );
      final scopeKey = remoteCourseId != null && remoteCourseId > 0
          ? _localState1ScopeKeyForRemoteCourse(remoteCourseId)
          : _localState1ScopeKeyForLocalCourse(course.id);
      fingerprintsByScope[scopeKey] = _buildTeacherCourseItemFingerprint(
        remoteCourseId: remoteCourseId,
        localCourseVersionId:
            remoteCourseId != null && remoteCourseId > 0 ? null : course.id,
        bundleHash: localHash,
      );
    }
    return fingerprintsByScope;
  }

  Future<String> _resolveTeacherCourseLocalState1Hash({
    required User teacher,
    required int remoteUserId,
    required CourseVersion course,
    required int? remoteCourseId,
  }) async {
    final hasArtifacts = await _hasCachedCourseArtifacts(course.id);
    if (!hasArtifacts) {
      return '';
    }
    if (remoteCourseId != null && remoteCourseId > 0) {
      final syncState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainTeacherCourseUpload,
        scopeKey: _teacherCourseScopeKey(remoteCourseId),
      );
      return (await _readTeacherCourseSyncHash(
            teacher: teacher,
            remoteUserId: remoteUserId,
            syncStateDomain: _syncDomainTeacherCourseUpload,
            course: course,
            remoteCourseId: remoteCourseId,
            syncState: syncState,
          ))
              ?.trim() ??
          '';
    }
    if (!await _canComputeTeacherCourseSyncHash(course)) {
      return '';
    }
    return (await _computeTeacherCourseSyncHash(
      teacher: teacher,
      course: course,
      remoteCourseId: 0,
    ))
        .trim();
  }

  String _buildStudentEnrollmentItemFingerprint({
    required int remoteCourseId,
    required int teacherRemoteUserId,
    required String bundleHash,
  }) {
    return [
      'student_course',
      '$remoteCourseId',
      '$teacherRemoteUserId',
      bundleHash.trim(),
    ].join('|');
  }

  String _buildTeacherCourseItemFingerprint({
    required int? remoteCourseId,
    required int? localCourseVersionId,
    required String bundleHash,
  }) {
    final scopeIdentity = remoteCourseId != null && remoteCourseId > 0
        ? 'remote:$remoteCourseId'
        : 'local:${localCourseVersionId ?? 0}';
    return [
      'teacher_course',
      scopeIdentity,
      bundleHash.trim(),
    ].join('|');
  }

  Future<String> _buildCanonicalLocalState2({
    required User currentUser,
    required int remoteUserId,
  }) async {
    if (currentUser.role == 'teacher') {
      return _buildTeacherLocalState2(
        currentUser: currentUser,
        remoteUserId: remoteUserId,
      );
    }
    return _buildStudentEnrollmentLocalState2(
      currentUser: currentUser,
      remoteUserId: remoteUserId,
    );
  }

  Future<String> _buildStudentEnrollmentLocalState2({
    required User currentUser,
    required int remoteUserId,
  }) async {
    final artifactHashesById = <String, String>{};
    final assignedRemoteCourses =
        await _db.getAssignedRemoteCoursesForStudent(currentUser.id);
    for (final info in assignedRemoteCourses) {
      if (info.remoteCourseId <= 0) {
        continue;
      }
      final syncState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainStudentCourseBundles,
        scopeKey: _teacherCourseScopeKey(info.remoteCourseId),
      );
      final bundleHash = syncState?.contentHash.trim() ?? '';
      if (bundleHash.isEmpty) {
        continue;
      }
      artifactHashesById['$_artifactClassCourseBundle:${info.remoteCourseId}'] =
          bundleHash;
    }
    return _buildState2FromArtifactHashes(artifactHashesById);
  }

  Future<String> _buildTeacherLocalState2({
    required User currentUser,
    required int remoteUserId,
  }) async {
    final artifactHashesById = <String, String>{};
    final localCourses = await _db.getCourseVersionsForTeacher(currentUser.id);
    for (final course in localCourses) {
      final remoteCourseId = await _db.getRemoteCourseId(course.id);
      final localHash = (await _resolveTeacherCourseLocalState1Hash(
        teacher: currentUser,
        remoteUserId: remoteUserId,
        course: course,
        remoteCourseId: remoteCourseId,
      ))
          .trim();
      if (localHash.isEmpty) {
        continue;
      }
      final artifactId = remoteCourseId != null && remoteCourseId > 0
          ? '$_artifactClassCourseBundle:$remoteCourseId'
          : 'local-course:${course.id}';
      artifactHashesById[artifactId] = localHash;
    }
    return _buildState2FromArtifactHashes(artifactHashesById);
  }

  String _buildState2FromArtifactHashes(
      Map<String, String> artifactHashesById) {
    final canonical = artifactHashesById.entries
        .where(
          (entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
        )
        .toList(growable: false)
      ..sort((left, right) {
        final artifactCompare = left.key.compareTo(right.key);
        if (artifactCompare != 0) {
          return artifactCompare;
        }
        return left.value.compareTo(right.value);
      });
    final builder = StringBuffer();
    for (final entry in canonical) {
      builder
        ..write(entry.key.trim())
        ..write('|')
        ..write(entry.value.trim())
        ..write('\n');
    }
    return '$_artifactState2Version:${sha256Hex(builder.toString())}';
  }

  Future<void> _reconcileTeacherCourseMetadata({
    required User currentUser,
    required List<TeacherCourseSummary> remoteCourses,
  }) async {
    final localCourses = await _db.getCourseVersionsForTeacher(currentUser.id);
    final localRemoteIdByCourseVersion = <int, int?>{};
    for (final course in localCourses) {
      localRemoteIdByCourseVersion[course.id] = await _db.getRemoteCourseId(
        course.id,
      );
    }

    for (final remoteCourse in remoteCourses) {
      var localCourseVersionId = await _db.getCourseVersionIdForRemoteCourse(
        remoteCourse.courseId,
      );
      if (localCourseVersionId == null) {
        final candidate = _findLocalCourseCandidate(
          localCourses: localCourses,
          localRemoteIdByCourseVersion: localRemoteIdByCourseVersion,
          targetSubject: remoteCourse.subject,
        );
        if (candidate != null) {
          localCourseVersionId = candidate.id;
        } else {
          localCourseVersionId = await _db.createCourseVersion(
            teacherId: currentUser.id,
            subject: remoteCourse.subject,
            granularity: 1,
            textbookText: '',
            sourcePath: null,
          );
          final created = await _db.getCourseVersionById(localCourseVersionId);
          if (created != null) {
            localCourses.add(created);
          }
        }
        await _db.upsertCourseRemoteLink(
          courseVersionId: localCourseVersionId,
          remoteCourseId: remoteCourse.courseId,
        );
        localRemoteIdByCourseVersion[localCourseVersionId] =
            remoteCourse.courseId;
      }
      await _claimTeacherCourseOwnership(
        currentUser: currentUser,
        courseVersionId: localCourseVersionId,
        localCourses: localCourses,
        localRemoteIdByCourseVersion: localRemoteIdByCourseVersion,
      );
      await _ensureCourseSubject(
        courseVersionId: localCourseVersionId,
        expectedSubject: remoteCourse.subject,
      );
    }
  }

  Future<void> _pullTeacherCoursesFromServer({
    required User currentUser,
    required int remoteUserId,
    required List<TeacherCourseSummary> remoteCourses,
    required bool initializeOnly,
    required _SyncTransferSummary summary,
  }) async {
    for (final remoteCourse in remoteCourses) {
      final latestBundleVersionId = remoteCourse.latestBundleVersionId ?? 0;
      if (latestBundleVersionId <= 0) {
        continue;
      }
      final remoteBundle = await _resolveRemoteBundleInfo(
        remoteCourseId: remoteCourse.courseId,
        courseSubject: remoteCourse.subject,
        latestBundleVersionId: latestBundleVersionId,
        latestBundleHash: remoteCourse.latestBundleHash,
      );
      await _syncRemoteCourseFromServer(
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourse.courseId,
        courseSubject: remoteCourse.subject,
        latestBundleVersionId: remoteBundle.bundleVersionId,
        latestBundleHash: remoteBundle.hash,
        syncStateDomain: _syncDomainTeacherCourseUpload,
        readLocalHash: (localCourse, _, syncState) =>
            _readTeacherCourseSyncHash(
          teacher: currentUser,
          remoteUserId: remoteUserId,
          syncStateDomain: _syncDomainTeacherCourseUpload,
          course: localCourse,
          remoteCourseId: remoteCourse.courseId,
          syncState: syncState,
        ),
        onHashesMatch: (_, localHash, __, syncState) =>
            _markTeacherCourseSyncStateSynced(
          remoteUserId: remoteUserId,
          remoteCourseId: remoteCourse.courseId,
          bundleVersionId: remoteBundle.bundleVersionId,
          bundleHash: localHash,
          syncState: syncState,
        ),
        importRemoteCourse: (resolvedCourseVersionId) =>
            _downloadAndImportTeacherCourse(
          currentUser: currentUser,
          remoteUserId: remoteUserId,
          remoteCourseId: remoteCourse.courseId,
          courseSubject: remoteCourse.subject,
          bundleHash: remoteBundle.hash,
          bundleVersionId: remoteBundle.bundleVersionId,
          existingCourseVersionId: resolvedCourseVersionId,
          summary: summary,
        ),
        onHashesDiffer:
            (localCourse, localHash, installedVersion, syncState) async {
          if (initializeOnly || installedVersion == null) {
            return _downloadAndImportTeacherCourse(
              currentUser: currentUser,
              remoteUserId: remoteUserId,
              remoteCourseId: remoteCourse.courseId,
              courseSubject: remoteCourse.subject,
              bundleHash: remoteBundle.hash,
              bundleVersionId: remoteBundle.bundleVersionId,
              existingCourseVersionId: localCourse.id,
              summary: summary,
            );
          }
          final hasUnsyncedLocalChanges = _hasUnsyncedLocalCourseChanges(
            syncState: syncState,
            localHash: localHash,
          );
          final serverHasNewerBundle =
              remoteBundle.bundleVersionId > installedVersion;
          if (serverHasNewerBundle && hasUnsyncedLocalChanges) {
            throw StateError(
              'Teacher bundle sync conflict for "${remoteCourse.subject}". '
              'Server has a newer course bundle, which may include prompt '
              'or profile changes. Pull latest server bundle before '
              'uploading local changes.',
            );
          }
          if (hasUnsyncedLocalChanges) {
            return localCourse;
          }
          return _downloadAndImportTeacherCourse(
            currentUser: currentUser,
            remoteUserId: remoteUserId,
            remoteCourseId: remoteCourse.courseId,
            courseSubject: remoteCourse.subject,
            bundleHash: remoteBundle.hash,
            bundleVersionId: remoteBundle.bundleVersionId,
            existingCourseVersionId: localCourse.id,
            summary: summary,
          );
        },
      );
    }
  }

  Future<_ResolvedRemoteBundleInfo> _resolveRemoteBundleInfo({
    required int remoteCourseId,
    required String courseSubject,
    required int latestBundleVersionId,
    required String latestBundleHash,
  }) async {
    final normalizedHash = latestBundleHash.trim();
    if (normalizedHash.isNotEmpty) {
      return _ResolvedRemoteBundleInfo(
        bundleVersionId: latestBundleVersionId,
        hash: normalizedHash,
      );
    }
    LatestCourseBundleInfo resolved;
    try {
      resolved = await _api.getLatestCourseBundleInfo(remoteCourseId);
    } on MarketplaceApiException catch (error) {
      if (error.statusCode == 404) {
        return _ResolvedRemoteBundleInfo(
          bundleVersionId: latestBundleVersionId,
          hash: '',
        );
      }
      rethrow;
    }
    final resolvedHash = resolved.hash.trim();
    if (resolved.bundleVersionId <= 0 || resolvedHash.isEmpty) {
      throw StateError(
        'Remote bundle hash is missing for "$courseSubject".',
      );
    }
    return _ResolvedRemoteBundleInfo(
      bundleVersionId: resolved.bundleVersionId,
      hash: resolvedHash,
    );
  }

  Future<_ResolvedCourseSyncState> _resolveCourseSyncState({
    required int remoteUserId,
    required int remoteCourseId,
    required String syncStateDomain,
    bool Function(
      CourseVersion localCourse,
      int? installedVersion,
      SyncItemState? syncState,
    )? shouldTrustLinkedCourse,
  }) async {
    final courseVersionId =
        await _db.getCourseVersionIdForRemoteCourse(remoteCourseId);
    final installedVersion =
        await _secureStorage.readInstalledCourseBundleVersion(
      remoteUserId: remoteUserId,
      remoteCourseId: remoteCourseId,
    );
    final syncState = await _secureStorage.readSyncItemState(
      remoteUserId: remoteUserId,
      domain: syncStateDomain,
      scopeKey: _teacherCourseScopeKey(remoteCourseId),
    );
    final localCourse = courseVersionId == null
        ? null
        : await _db.getCourseVersionById(courseVersionId);
    if (localCourse == null) {
      return _ResolvedCourseSyncState(
        courseVersionId: courseVersionId,
        installedVersion: installedVersion,
        syncState: syncState,
        localCourse: null,
        replacedCourseVersionId: null,
      );
    }
    if (shouldTrustLinkedCourse != null &&
        !shouldTrustLinkedCourse(localCourse, installedVersion, syncState)) {
      return _ResolvedCourseSyncState(
        courseVersionId: null,
        installedVersion: installedVersion,
        syncState: syncState,
        localCourse: null,
        replacedCourseVersionId: localCourse.id,
      );
    }
    return _ResolvedCourseSyncState(
      courseVersionId: courseVersionId,
      installedVersion: installedVersion,
      syncState: syncState,
      localCourse: localCourse,
      replacedCourseVersionId: null,
    );
  }

  Future<_RemoteCourseSyncResult> _syncRemoteCourseFromServer({
    required int remoteUserId,
    required int remoteCourseId,
    required String courseSubject,
    required int latestBundleVersionId,
    required String latestBundleHash,
    required String syncStateDomain,
    required Future<String?> Function(
      CourseVersion localCourse,
      int? installedVersion,
      SyncItemState? syncState,
    ) readLocalHash,
    required Future<void> Function(
      CourseVersion localCourse,
      String localHash,
      int? installedVersion,
      SyncItemState? syncState,
    ) onHashesMatch,
    required Future<CourseVersion> Function(int? existingCourseVersionId)
        importRemoteCourse,
    required Future<CourseVersion> Function(
      CourseVersion localCourse,
      String localHash,
      int? installedVersion,
      SyncItemState? syncState,
    ) onHashesDiffer,
    bool Function(
      CourseVersion localCourse,
      int? installedVersion,
      SyncItemState? syncState,
    )? shouldTrustLinkedCourse,
  }) async {
    final remoteHash = latestBundleHash.trim();
    final localState = await _resolveCourseSyncState(
      remoteUserId: remoteUserId,
      remoteCourseId: remoteCourseId,
      syncStateDomain: syncStateDomain,
      shouldTrustLinkedCourse: shouldTrustLinkedCourse,
    );
    if (remoteHash.isEmpty) {
      if (localState.localCourse != null &&
          localState.installedVersion != null &&
          latestBundleVersionId <= localState.installedVersion! &&
          _hasLocalCourseMaterialization(localState.localCourse!)) {
        return _RemoteCourseSyncResult(
          course: localState.localCourse!,
          replacedCourseVersionId: localState.replacedCourseVersionId,
        );
      }
      return _RemoteCourseSyncResult(
        course: await importRemoteCourse(localState.courseVersionId),
        replacedCourseVersionId: localState.replacedCourseVersionId,
      );
    }
    if (localState.localCourse == null) {
      return _RemoteCourseSyncResult(
        course: await importRemoteCourse(localState.courseVersionId),
        replacedCourseVersionId: localState.replacedCourseVersionId,
      );
    }
    final localHash = (await readLocalHash(
          localState.localCourse!,
          localState.installedVersion,
          localState.syncState,
        ))
            ?.trim() ??
        '';
    if (localHash.isEmpty) {
      return _RemoteCourseSyncResult(
        course: await importRemoteCourse(localState.courseVersionId),
        replacedCourseVersionId: localState.replacedCourseVersionId,
      );
    }
    final resolvedSyncState = await _secureStorage.readSyncItemState(
      remoteUserId: remoteUserId,
      domain: syncStateDomain,
      scopeKey: _teacherCourseScopeKey(remoteCourseId),
    );
    if (localHash == remoteHash) {
      await onHashesMatch(
        localState.localCourse!,
        localHash,
        localState.installedVersion,
        resolvedSyncState,
      );
      return _RemoteCourseSyncResult(
        course: localState.localCourse!,
        replacedCourseVersionId: localState.replacedCourseVersionId,
      );
    }
    return _RemoteCourseSyncResult(
      course: await onHashesDiffer(
        localState.localCourse!,
        localHash,
        localState.installedVersion,
        resolvedSyncState,
      ),
      replacedCourseVersionId: localState.replacedCourseVersionId,
    );
  }

  bool _hasLocalCourseMaterialization(CourseVersion course) {
    final sourcePath = (course.sourcePath ?? '').trim();
    if (sourcePath.isEmpty) {
      return false;
    }
    return Directory(sourcePath).existsSync();
  }

  bool _hasTrustedStudentBundleIdentity({
    required int? installedVersion,
    required SyncItemState? syncState,
  }) {
    if (installedVersion != null && installedVersion > 0) {
      return true;
    }
    final contentHash = syncState?.contentHash.trim() ?? '';
    return contentHash.isNotEmpty;
  }

  String? _readStudentCourseSyncHash(SyncItemState? syncState) {
    final normalized = syncState?.contentHash.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<void> _writeStudentCourseSyncState({
    required int remoteUserId,
    required int remoteCourseId,
    required int bundleVersionId,
    required String bundleHash,
  }) async {
    final now = DateTime.now().toUtc();
    await _writeCourseSyncState(
      remoteUserId: remoteUserId,
      domain: _syncDomainStudentCourseBundles,
      remoteCourseId: remoteCourseId,
      bundleVersionId: bundleVersionId,
      contentHash: bundleHash.trim(),
      lastChangedAt: now,
      lastSyncedAt: now,
    );
  }

  Future<void> _markTeacherCourseSyncStateSynced({
    required int remoteUserId,
    required int remoteCourseId,
    required int bundleVersionId,
    required String bundleHash,
    required SyncItemState? syncState,
  }) async {
    final now = DateTime.now().toUtc();
    final normalizedHash = bundleHash.trim();
    final lastChangedAt =
        syncState != null && syncState.contentHash.trim() == normalizedHash
            ? syncState.lastChangedAt.toUtc()
            : now;
    await _writeCourseSyncState(
      remoteUserId: remoteUserId,
      domain: _syncDomainTeacherCourseUpload,
      remoteCourseId: remoteCourseId,
      bundleVersionId: bundleVersionId,
      contentHash: normalizedHash,
      lastChangedAt: lastChangedAt,
      lastSyncedAt: now,
    );
  }

  Future<void> _writeCourseSyncState({
    required int remoteUserId,
    required String domain,
    required int remoteCourseId,
    required int bundleVersionId,
    required String contentHash,
    required DateTime lastChangedAt,
    required DateTime lastSyncedAt,
  }) async {
    await _secureStorage.writeInstalledCourseBundleVersion(
      remoteUserId: remoteUserId,
      remoteCourseId: remoteCourseId,
      versionId: bundleVersionId,
    );
    await _secureStorage.writeSyncItemState(
      remoteUserId: remoteUserId,
      domain: domain,
      scopeKey: _teacherCourseScopeKey(remoteCourseId),
      contentHash: contentHash.trim(),
      lastChangedAt: lastChangedAt,
      lastSyncedAt: lastSyncedAt,
    );
  }

  bool _hasUnsyncedLocalCourseChanges({
    required SyncItemState? syncState,
    required String localHash,
  }) {
    final normalizedHash = localHash.trim();
    if (normalizedHash.isEmpty) {
      return false;
    }
    if (syncState == null) {
      return true;
    }
    if (syncState.contentHash.trim() != normalizedHash) {
      return true;
    }
    return syncState.lastChangedAt
        .toUtc()
        .isAfter(syncState.lastSyncedAt.toUtc());
  }

  Future<String?> _readTeacherCourseSyncHash({
    required User teacher,
    required int remoteUserId,
    required String syncStateDomain,
    required CourseVersion course,
    required int remoteCourseId,
    required SyncItemState? syncState,
  }) async {
    final storedHash = syncState?.contentHash.trim() ?? '';
    final latestInputAt = await _readTeacherCourseSyncInputUpdatedAt(
      teacher: teacher,
      course: course,
    );
    final canComputeHash = await _canComputeTeacherCourseSyncHash(course);
    final lastChangedAt = syncState?.lastChangedAt.toUtc();
    if (storedHash.isNotEmpty &&
        canComputeHash &&
        lastChangedAt != null &&
        (latestInputAt == null || !latestInputAt.isAfter(lastChangedAt))) {
      return storedHash;
    }
    if (!canComputeHash) {
      return null;
    }
    final preparedBundle = await _prepareTeacherCourseBundle(
      teacher: teacher,
      course: course,
      remoteCourseId: remoteCourseId,
    );
    final normalizedHash = preparedBundle.hash.trim();
    if (normalizedHash.isEmpty) {
      return null;
    }
    if (syncState != null && storedHash == normalizedHash) {
      return normalizedHash;
    }
    final nextChangedAt = latestInputAt ?? DateTime.now().toUtc();
    final lastSyncedAt = syncState?.lastSyncedAt.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    await _secureStorage.writeSyncItemState(
      remoteUserId: remoteUserId,
      domain: syncStateDomain,
      scopeKey: _teacherCourseScopeKey(remoteCourseId),
      contentHash: normalizedHash,
      lastChangedAt: nextChangedAt,
      lastSyncedAt: lastSyncedAt,
    );
    return normalizedHash;
  }

  Future<bool> _canComputeTeacherCourseSyncHash(CourseVersion course) async {
    _requireCourseArtifactService();
    return await _hasCachedCourseArtifacts(course.id);
  }

  Future<DateTime?> _readTeacherCourseSyncInputUpdatedAt({
    required User teacher,
    required CourseVersion course,
  }) async {
    var latest = _maxUtc(
      course.createdAt.toUtc(),
      course.updatedAt?.toUtc(),
    );
    final artifactService = _courseArtifactService;
    if (artifactService != null) {
      final manifest = await artifactService.readCourseArtifacts(course.id);
      latest = _maxUtc(latest, manifest?.builtAt.toUtc());
    }

    final courseKey = (course.sourcePath ?? '').trim();
    final assignments = await _db.getAssignmentsForCourse(course.id);
    final assignedStudentIds =
        assignments.map((assignment) => assignment.studentId).toSet();
    for (final assignment in assignments) {
      latest = _maxUtc(latest, assignment.assignedAt.toUtc());
    }

    final promptTemplates = await (_db.select(_db.promptTemplates)
          ..where((tbl) {
            final studentGlobalScope = assignedStudentIds.isEmpty
                ? const Constant(false)
                : tbl.courseKey.isNull() &
                    tbl.studentId.isIn(assignedStudentIds);
            final courseScope = courseKey.isEmpty
                ? const Constant(false)
                : tbl.courseKey.equals(courseKey);
            return tbl.teacherId.equals(teacher.id) &
                tbl.isActive.equals(true) &
                ((tbl.courseKey.isNull() & tbl.studentId.isNull()) |
                    studentGlobalScope |
                    courseScope);
          }))
        .get();
    for (final template in promptTemplates) {
      latest = _maxUtc(latest, template.createdAt.toUtc());
    }

    final profiles = await (_db.select(_db.studentPromptProfiles)
          ..where((tbl) {
            final studentGlobalScope = assignedStudentIds.isEmpty
                ? const Constant(false)
                : tbl.courseKey.isNull() &
                    tbl.studentId.isIn(assignedStudentIds);
            final courseScope = courseKey.isEmpty
                ? const Constant(false)
                : tbl.courseKey.equals(courseKey);
            return tbl.teacherId.equals(teacher.id) &
                ((tbl.courseKey.isNull() & tbl.studentId.isNull()) |
                    studentGlobalScope |
                    courseScope);
          }))
        .get();
    for (final profile in profiles) {
      latest = _maxUtc(
        latest,
        (profile.updatedAt ?? profile.createdAt).toUtc(),
      );
    }

    final passConfigs = await (_db.select(_db.studentPassConfigs)
          ..where((tbl) => tbl.courseVersionId.equals(course.id)))
        .get();
    for (final config in passConfigs) {
      latest = _maxUtc(
        latest,
        (config.updatedAt ?? config.createdAt).toUtc(),
      );
    }
    return latest;
  }

  DateTime? _maxUtc(DateTime? left, DateTime? right) {
    if (left == null) {
      return right?.toUtc();
    }
    if (right == null) {
      return left.toUtc();
    }
    final normalizedLeft = left.toUtc();
    final normalizedRight = right.toUtc();
    return normalizedRight.isAfter(normalizedLeft)
        ? normalizedRight
        : normalizedLeft;
  }

  Future<void> _uploadLocalTeacherCourses({
    required User currentUser,
    required int remoteUserId,
    required List<TeacherCourseSummary> remoteCourses,
    required _SyncTransferSummary summary,
  }) async {
    final remoteCoursesById = <int, TeacherCourseSummary>{
      for (final remoteCourse in remoteCourses)
        remoteCourse.courseId: remoteCourse,
    };
    final localCourses = await _db.getCourseVersionsForTeacher(currentUser.id);
    for (final course in localCourses) {
      final hasArtifacts = await _hasCachedCourseArtifacts(course.id);
      if (!hasArtifacts) {
        throw StateError(
          'Cached course artifacts are missing for "${course.subject}". '
          'Teacher sync cannot rebuild bundles on the hot path.',
        );
      }
      final target = await _resolveTeacherUploadTarget(
        courseVersionId: course.id,
        courseSubject: course.subject,
        remoteCoursesById: remoteCoursesById,
      );
      final remoteCourseId = target.courseId;
      final scopeKey = _teacherCourseScopeKey(remoteCourseId);
      final remoteCourse = remoteCoursesById[remoteCourseId];
      final remoteLatestVersion = remoteCourse?.latestBundleVersionId ?? 0;
      final installedVersion =
          await _secureStorage.readInstalledCourseBundleVersion(
        remoteUserId: remoteUserId,
        remoteCourseId: remoteCourseId,
      );
      final initialSyncState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainTeacherCourseUpload,
        scopeKey: scopeKey,
      );
      final localHash = await _readTeacherCourseSyncHash(
        teacher: currentUser,
        remoteUserId: remoteUserId,
        syncStateDomain: _syncDomainTeacherCourseUpload,
        course: course,
        remoteCourseId: remoteCourseId,
        syncState: initialSyncState,
      );
      final syncState = await _secureStorage.readSyncItemState(
        remoteUserId: remoteUserId,
        domain: _syncDomainTeacherCourseUpload,
        scopeKey: scopeKey,
      );
      final hasUnsyncedLocalChanges = _hasUnsyncedLocalCourseChanges(
        syncState: syncState,
        localHash: localHash ?? '',
      );
      if (!hasUnsyncedLocalChanges &&
          installedVersion != null &&
          installedVersion == remoteLatestVersion) {
        continue;
      }
      if (remoteLatestVersion > 0 &&
          installedVersion != null &&
          remoteLatestVersion > installedVersion) {
        if (hasUnsyncedLocalChanges) {
          throw StateError(
            'Teacher bundle sync conflict for "${course.subject}". '
            'Server has a newer course bundle, which may include prompt '
            'or profile changes. Pull latest server bundle before '
            'uploading local changes.',
          );
        }
        continue;
      }
      final preparedBundle = await _prepareTeacherCourseBundle(
        teacher: currentUser,
        course: course,
        remoteCourseId: remoteCourseId,
      );
      final uploadResponse = await _artifactApi.uploadArtifact(
        artifactId: 'course_bundle:$remoteCourseId',
        sha256: preparedBundle.hash,
        bytes: await preparedBundle.bundleFile.readAsBytes(),
        baseSha256: remoteCourse?.latestBundleHash.trim() ?? '',
        overwriteServer: false,
      );
      final uploadedVersionId = uploadResponse.bundleVersionId > 0
          ? uploadResponse.bundleVersionId
          : remoteLatestVersion;
      summary.uploaded.add(
        SyncTransferLogItem(
          direction: 'upload',
          fileName: p.basename(preparedBundle.bundleFile.path),
          sizeBytes: preparedBundle.bundleFile.lengthSync(),
          courseSubject: course.subject,
          remoteCourseId: remoteCourseId,
          bundleId: target.bundleId,
          bundleVersionId: uploadedVersionId,
          hash: preparedBundle.hash,
          source: 'teacher_course_sync',
        ),
      );
      final now = DateTime.now().toUtc();
      final lastChangedAt = syncState != null &&
              syncState.contentHash.trim() == preparedBundle.hash
          ? syncState.lastChangedAt.toUtc()
          : now;
      await _writeCourseSyncState(
        remoteUserId: remoteUserId,
        domain: _syncDomainTeacherCourseUpload,
        remoteCourseId: remoteCourseId,
        bundleVersionId: uploadedVersionId,
        contentHash: preparedBundle.hash,
        lastChangedAt: lastChangedAt,
        lastSyncedAt: now,
      );
    }
  }

  Future<void> _detachRemovedTeacherCourses({
    required int teacherId,
    required Set<int> removedRemoteCourseIds,
  }) async {
    if (removedRemoteCourseIds.isEmpty) {
      return;
    }
    final localCourses = await _db.getCourseVersionsForTeacher(teacherId);
    for (final course in localCourses) {
      final remoteCourseId = await _db.getRemoteCourseId(course.id);
      if (remoteCourseId == null ||
          remoteCourseId <= 0 ||
          !removedRemoteCourseIds.contains(remoteCourseId)) {
        continue;
      }
      await _db.deleteCourseRemoteLink(course.id);
    }
  }

  Future<EnsureBundleResult> _resolveTeacherUploadTarget({
    required int courseVersionId,
    required String courseSubject,
    required Map<int, TeacherCourseSummary> remoteCoursesById,
  }) async {
    final storedRemoteCourseId = await _db.getRemoteCourseId(courseVersionId);
    var remoteCourseId = storedRemoteCourseId;
    final normalizedCourseName = _normalizeCourseName(courseSubject);

    if (remoteCourseId == null || remoteCoursesById[remoteCourseId] == null) {
      for (final remoteCourse in remoteCoursesById.values) {
        if (_normalizeCourseName(remoteCourse.subject) ==
            normalizedCourseName) {
          remoteCourseId = remoteCourse.courseId;
          break;
        }
      }
    }
    if (remoteCourseId == null || remoteCourseId <= 0) {
      final created = await _api.createTeacherCourse(
        subject: courseSubject,
        grade: '',
        description: 'Uploaded from Tutor1on1.',
      );
      remoteCourseId = created.courseId;
      remoteCoursesById[remoteCourseId] = created;
    }
    await _db.upsertCourseRemoteLink(
      courseVersionId: courseVersionId,
      remoteCourseId: remoteCourseId,
    );

    try {
      final ensured = await _api.ensureBundle(
        remoteCourseId,
        courseName: courseSubject,
      );
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: ensured.courseId,
      );
      return ensured;
    } on MarketplaceApiException catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
      final created = await _api.createTeacherCourse(
        subject: courseSubject,
        grade: '',
        description: 'Uploaded from Tutor1on1.',
      );
      remoteCourseId = created.courseId;
      remoteCoursesById[remoteCourseId] = created;
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: remoteCourseId,
      );
      final ensured = await _api.ensureBundle(
        remoteCourseId,
        courseName: courseSubject,
      );
      await _db.upsertCourseRemoteLink(
        courseVersionId: courseVersionId,
        remoteCourseId: ensured.courseId,
      );
      return ensured;
    }
  }

  Future<_PreparedTeacherCourseBundle> _prepareTeacherCourseBundle({
    required User teacher,
    required CourseVersion course,
    required int remoteCourseId,
  }) async {
    final promptMetadata = await _buildPromptBundleMetadata(
      teacher: teacher,
      course: course,
      remoteCourseId: remoteCourseId,
    );
    final prepared = await _requireCourseArtifactService().prepareUploadBundle(
      courseVersionId: course.id,
      promptMetadata: promptMetadata,
      bundleLabel: course.subject,
    );
    return _PreparedTeacherCourseBundle(
      bundleFile: prepared.bundleFile,
      hash: prepared.hash,
    );
  }

  Future<String> _computeTeacherCourseSyncHash({
    required User teacher,
    required CourseVersion course,
    required int remoteCourseId,
  }) async {
    final preparedBundle = await _prepareTeacherCourseBundle(
      teacher: teacher,
      course: course,
      remoteCourseId: remoteCourseId,
    );
    return preparedBundle.hash;
  }

  Future<CourseVersion> _downloadAndImportTeacherCourse({
    required User currentUser,
    required int remoteUserId,
    required int remoteCourseId,
    required String courseSubject,
    required String bundleHash,
    required int bundleVersionId,
    required int? existingCourseVersionId,
    required _SyncTransferSummary summary,
  }) async {
    final bundleService = CourseBundleService();
    File? bundleFile;
    try {
      final normalizedBundleHash = bundleHash.trim();
      bundleFile = await _downloadCourseBundleArtifactToFile(
        remoteCourseId: remoteCourseId,
        courseSubject: courseSubject,
        expectedSha256: bundleHash,
      );
      await bundleService.validateBundleForImport(bundleFile);
      final promptMetadata =
          await bundleService.readPromptMetadataFromBundleFile(bundleFile);
      final folderPath = await bundleService.extractBundleFromFile(
        bundleFile: bundleFile,
        courseName: courseSubject,
      );
      final preview = await _courseService.previewCourseLoad(
        folderPath: folderPath,
        courseVersionId: existingCourseVersionId,
        courseNameOverride: courseSubject,
      );
      if (!preview.success) {
        throw StateError(preview.message);
      }
      final mode = existingCourseVersionId == null
          ? CourseReloadMode.fresh
          : CourseReloadMode.override;
      final result = await _courseService.applyCourseLoad(
        teacherId: currentUser.id,
        preview: preview,
        mode: mode,
        rebuildCourseArtifacts: _courseArtifactService == null,
      );
      if (!result.success || result.course == null) {
        throw StateError(result.message);
      }
      await _db.upsertCourseRemoteLink(
        courseVersionId: result.course!.id,
        remoteCourseId: remoteCourseId,
      );
      if (promptMetadata != null) {
        await _applyPromptMetadataForTeacher(
          currentUser: currentUser,
          remoteCourseId: remoteCourseId,
          metadata: promptMetadata,
          course: result.course!,
        );
      }
      if (_courseArtifactService != null) {
        final artifactFolderPath =
            (result.course!.sourcePath ?? '').trim().isNotEmpty
                ? result.course!.sourcePath!.trim()
                : folderPath;
        await _courseArtifactService.storeImportedContentBundle(
          courseVersionId: result.course!.id,
          folderPath: artifactFolderPath,
          bundleFile: bundleFile,
          buildChapterArtifacts: false,
        );
      }
      final remoteHash =
          await bundleService.computeBundleSemanticHash(bundleFile);
      final localPromptMetadata = await _buildPromptBundleMetadata(
        teacher: currentUser,
        course: result.course!,
        remoteCourseId: remoteCourseId,
      );
      final localHash = await _requireCourseArtifactService().computeUploadHash(
        courseVersionId: result.course!.id,
        promptMetadata: localPromptMetadata,
      );
      if (localHash.trim() != remoteHash.trim()) {
        final remoteContentWithLocalMetadataHash =
            await bundleService.computeBundleSemanticHashFromBundle(
          bundleFile,
          promptMetadataOverride: localPromptMetadata,
        );
        throw StateError(
          'Imported teacher bundle fingerprint mismatch after local '
          'materialization. remote=$remoteHash local=$localHash '
          'remote_content_local_metadata='
          '$remoteContentWithLocalMetadataHash',
        );
      }
      summary.downloaded.add(
        SyncTransferLogItem(
          direction: 'download',
          fileName: p.basename(bundleFile.path),
          sizeBytes: bundleFile.lengthSync(),
          courseSubject: courseSubject,
          remoteCourseId: remoteCourseId,
          bundleVersionId: bundleVersionId,
          hash: bundleHash,
          source: 'teacher_course_sync',
        ),
      );
      final now = DateTime.now().toUtc();
      await _writeCourseSyncState(
        remoteUserId: remoteUserId,
        domain: _syncDomainTeacherCourseUpload,
        remoteCourseId: remoteCourseId,
        bundleVersionId: bundleVersionId,
        contentHash: normalizedBundleHash.isNotEmpty
            ? normalizedBundleHash
            : await bundleService.computeBundleByteHash(bundleFile),
        lastChangedAt: now,
        lastSyncedAt: now,
      );
      return result.course!;
    } finally {
      if (bundleFile != null && bundleFile.existsSync()) {
        await bundleFile.delete();
      }
    }
  }

  CourseArtifactService _requireCourseArtifactService() {
    final artifactService = _courseArtifactService;
    if (artifactService == null) {
      throw StateError(
        'Teacher sync requires cached course artifacts and cannot rebuild '
        'bundles on the hot path.',
      );
    }
    return artifactService;
  }

  Future<bool> _hasCachedCourseArtifacts(int courseVersionId) async {
    final manifest = await _requireCourseArtifactService().readCourseArtifacts(
      courseVersionId,
    );
    if (manifest == null) {
      return false;
    }
    return File(manifest.contentBundlePath).existsSync();
  }

  Future<Map<String, dynamic>> _buildPromptBundleMetadata({
    required User teacher,
    required CourseVersion course,
    required int remoteCourseId,
  }) async {
    final courseKey = (course.sourcePath ?? '').trim();
    if (courseKey.isEmpty) {
      return <String, dynamic>{
        'schema': kCurrentPromptBundleSchema,
        'remote_course_id': remoteCourseId,
        'teacher_username': teacher.username,
        'prompt_templates': const <Map<String, dynamic>>[],
        'student_prompt_profiles': const <Map<String, dynamic>>[],
        'student_pass_configs': const <Map<String, dynamic>>[],
      };
    }

    final scopeTemplates = <PromptTemplate>[];
    final assignments = await _db.getAssignmentsForCourse(course.id);
    final assignedStudentIds =
        assignments.map((assignment) => assignment.studentId).toSet();

    final systemTemplates = await (_db.select(_db.promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacher.id) &
              tbl.isActive.equals(true) &
              tbl.courseKey.isNull() &
              tbl.studentId.isNull())
          ..orderBy([
            (tbl) =>
                OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
    scopeTemplates.addAll(systemTemplates);

    if (assignedStudentIds.isNotEmpty) {
      final studentGlobalTemplates = await (_db.select(_db.promptTemplates)
            ..where((tbl) =>
                tbl.teacherId.equals(teacher.id) &
                tbl.isActive.equals(true) &
                tbl.courseKey.isNull() &
                tbl.studentId.isIn(assignedStudentIds))
            ..orderBy([
              (tbl) => OrderingTerm(
                    expression: tbl.createdAt,
                    mode: OrderingMode.desc,
                  )
            ]))
          .get();
      scopeTemplates.addAll(studentGlobalTemplates);
    }

    final courseTemplates = await (_db.select(_db.promptTemplates)
          ..where((tbl) =>
              tbl.teacherId.equals(teacher.id) &
              tbl.isActive.equals(true) &
              tbl.courseKey.equals(courseKey))
          ..orderBy([
            (tbl) =>
                OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
    scopeTemplates.addAll(courseTemplates);

    final dedupedByScope = <String, PromptTemplate>{};
    for (final template in scopeTemplates) {
      final key = [
        template.promptName,
        template.courseKey ?? '',
        template.studentId?.toString() ?? '',
      ].join('::');
      dedupedByScope.putIfAbsent(key, () => template);
    }

    final studentCache = <int, User?>{};
    final rawTimestampMetadata =
        teacher.remoteUserId != null && teacher.remoteUserId! > 0
            ? await _readTeacherPromptTimestampMetadata(
                remoteUserId: teacher.remoteUserId!,
                remoteCourseId: remoteCourseId,
              )
            : const <String, Map<String, String>>{};
    final promptTemplatesPayload = <Map<String, dynamic>>[];
    for (final template in dedupedByScope.values) {
      final studentId = template.studentId;
      User? student;
      if (studentId != null) {
        student = studentCache[studentId];
        student ??= await _db.getUserById(studentId);
        studentCache[studentId] = student;
      }

      var scope = 'teacher';
      if (template.courseKey == null && template.studentId != null) {
        scope = 'student_global';
      } else if (template.courseKey != null && template.studentId == null) {
        scope = 'course';
      } else if (template.courseKey != null && template.studentId != null) {
        scope = 'student_course';
      }
      final timestampKey = _teacherPromptTemplateTimestampKey(
        promptName: template.promptName,
        scope: scope,
        studentRemoteUserId: student?.remoteUserId,
      );
      final timestampStrings = rawTimestampMetadata[timestampKey];

      promptTemplatesPayload.add({
        'prompt_name': template.promptName,
        'scope': scope,
        'content': template.content,
        'student_remote_user_id': student?.remoteUserId,
        'student_username': student?.username,
        'created_at': _resolveTeacherPromptTimestampString(
          raw: timestampStrings?['created_at'],
          actual: template.createdAt.toUtc(),
        ),
      });
    }

    final profilesPayload = <Map<String, dynamic>>[];
    final systemProfile = await _db.getStudentPromptProfile(
      teacherId: teacher.id,
      courseKey: null,
      studentId: null,
    );
    if (systemProfile != null) {
      profilesPayload.add(
        _profileToJson(
          systemProfile,
          scope: 'teacher',
          timestampStrings: rawTimestampMetadata[_teacherProfileTimestampKey(
            scope: 'teacher',
            studentRemoteUserId: null,
          )],
        ),
      );
    }

    for (final studentId in assignedStudentIds) {
      final profile = await _db.getStudentPromptProfile(
        teacherId: teacher.id,
        courseKey: null,
        studentId: studentId,
      );
      if (profile == null) {
        continue;
      }
      var student = studentCache[studentId];
      student ??= await _db.getUserById(studentId);
      studentCache[studentId] = student;
      profilesPayload.add(
        _profileToJson(
          profile,
          scope: 'student_global',
          studentRemoteUserId: student?.remoteUserId,
          studentUsername: student?.username,
          timestampStrings: rawTimestampMetadata[_teacherProfileTimestampKey(
            scope: 'student_global',
            studentRemoteUserId: student?.remoteUserId,
          )],
        ),
      );
    }

    final courseProfile = await _db.getStudentPromptProfile(
      teacherId: teacher.id,
      courseKey: courseKey,
      studentId: null,
    );
    if (courseProfile != null) {
      profilesPayload.add(
        _profileToJson(
          courseProfile,
          scope: 'course',
          timestampStrings: rawTimestampMetadata[_teacherProfileTimestampKey(
            scope: 'course',
            studentRemoteUserId: null,
          )],
        ),
      );
    }

    final studentProfileRows = await (_db.select(_db.studentPromptProfiles)
          ..where((tbl) =>
              tbl.teacherId.equals(teacher.id) &
              tbl.courseKey.equals(courseKey) &
              tbl.studentId.isNotNull())
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.updatedAt,
                  mode: OrderingMode.desc,
                ),
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();

    final studentIds = <int>{};
    for (final row in studentProfileRows) {
      final studentId = row.studentId;
      if (studentId != null) {
        studentIds.add(studentId);
      }
    }

    for (final studentId in studentIds) {
      final profile = await _db.getStudentPromptProfile(
        teacherId: teacher.id,
        courseKey: courseKey,
        studentId: studentId,
      );
      if (profile == null) {
        continue;
      }
      var student = studentCache[studentId];
      student ??= await _db.getUserById(studentId);
      studentCache[studentId] = student;
      profilesPayload.add(
        _profileToJson(
          profile,
          scope: 'student_course',
          studentRemoteUserId: student?.remoteUserId,
          studentUsername: student?.username,
          timestampStrings: rawTimestampMetadata[_teacherProfileTimestampKey(
            scope: 'student_course',
            studentRemoteUserId: student?.remoteUserId,
          )],
        ),
      );
    }

    final passConfigsPayload = <Map<String, dynamic>>[];
    final passConfigRows = await (_db.select(_db.studentPassConfigs)
          ..where(
            (tbl) => tbl.courseVersionId.equals(course.id),
          )
          ..orderBy([
            (tbl) => OrderingTerm(
                  expression: tbl.updatedAt,
                  mode: OrderingMode.desc,
                ),
            (tbl) => OrderingTerm(
                  expression: tbl.createdAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
    for (final config in passConfigRows) {
      var student = studentCache[config.studentId];
      student ??= await _db.getUserById(config.studentId);
      studentCache[config.studentId] = student;
      passConfigsPayload.add({
        'student_remote_user_id': student?.remoteUserId,
        'student_username': student?.username,
        'easy_weight': config.easyWeight,
        'medium_weight': config.mediumWeight,
        'hard_weight': config.hardWeight,
        'pass_threshold': config.passThreshold,
        'created_at': _resolveTeacherPromptTimestampString(
          raw: rawTimestampMetadata[_teacherPassConfigTimestampKey(
            studentRemoteUserId: student?.remoteUserId,
          )]?['created_at'],
          actual: config.createdAt.toUtc(),
        ),
        'updated_at': _resolveTeacherPromptTimestampString(
          raw: rawTimestampMetadata[_teacherPassConfigTimestampKey(
            studentRemoteUserId: student?.remoteUserId,
          )]?['updated_at'],
          actual: (config.updatedAt ?? config.createdAt).toUtc(),
        ),
      });
    }

    return {
      'schema': kCurrentPromptBundleSchema,
      'remote_course_id': remoteCourseId,
      'teacher_username': teacher.username,
      'prompt_templates': promptTemplatesPayload,
      'student_prompt_profiles': profilesPayload,
      'student_pass_configs': passConfigsPayload,
    };
  }

  Map<String, dynamic> _profileToJson(
    StudentPromptProfile profile, {
    required String scope,
    int? studentRemoteUserId,
    String? studentUsername,
    Map<String, String>? timestampStrings,
  }) {
    return {
      'scope': scope,
      'student_remote_user_id': studentRemoteUserId,
      'student_username': studentUsername,
      'grade_level': profile.gradeLevel,
      'reading_level': profile.readingLevel,
      'preferred_language': profile.preferredLanguage,
      'interests': profile.interests,
      'preferred_tone': profile.preferredTone,
      'preferred_pace': profile.preferredPace,
      'preferred_format': profile.preferredFormat,
      'support_notes': profile.supportNotes,
      'created_at': _resolveTeacherPromptTimestampString(
        raw: timestampStrings?['created_at'],
        actual: profile.createdAt.toUtc(),
      ),
      'updated_at': _resolveTeacherPromptTimestampString(
        raw: timestampStrings?['updated_at'],
        actual: (profile.updatedAt ?? profile.createdAt).toUtc(),
      ),
    };
  }

  DateTime? _parseMetadataTimestamp(Object? value) {
    final raw = value is String ? value.trim() : '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  String _resolveTeacherPromptTimestampString({
    required String? raw,
    required DateTime actual,
  }) {
    final parsed = _parseMetadataTimestamp(raw);
    if (parsed != null && parsed.isAtSameMomentAs(actual.toUtc())) {
      return raw!.trim();
    }
    return actual.toUtc().toIso8601String();
  }

  String _teacherPromptTemplateTimestampKey({
    required String promptName,
    required String scope,
    required int? studentRemoteUserId,
  }) {
    return [
      'prompt',
      promptName.trim(),
      scope.trim(),
      studentRemoteUserId?.toString() ?? '',
    ].join('::');
  }

  String _teacherProfileTimestampKey({
    required String scope,
    required int? studentRemoteUserId,
  }) {
    return [
      'profile',
      scope.trim(),
      studentRemoteUserId?.toString() ?? '',
    ].join('::');
  }

  String _teacherPassConfigTimestampKey({
    required int? studentRemoteUserId,
  }) {
    return [
      'pass_config',
      studentRemoteUserId?.toString() ?? '',
    ].join('::');
  }

  Future<Map<String, Map<String, String>>> _readTeacherPromptTimestampMetadata({
    required int remoteUserId,
    required int remoteCourseId,
  }) async {
    final row = await (_db.select(_db.syncMetadataEntries)
          ..where((tbl) =>
              tbl.remoteUserId.equals(remoteUserId) &
              tbl.kind.equals(_syncMetadataKindTeacherPromptTimestamps) &
              tbl.domain.equals(_syncMetadataDomainTeacherPromptTimestamps) &
              tbl.scopeKey.equals(_teacherCourseScopeKey(remoteCourseId))))
        .getSingleOrNull();
    if (row == null) {
      return const <String, Map<String, String>>{};
    }
    final normalizedValue = row.value.trim();
    if (normalizedValue.isEmpty) {
      return const <String, Map<String, String>>{};
    }
    try {
      final decoded = jsonDecode(normalizedValue);
      if (decoded is! Map<String, dynamic>) {
        return const <String, Map<String, String>>{};
      }
      final result = <String, Map<String, String>>{};
      for (final entry in decoded.entries) {
        final item = entry.value;
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final createdAt = (item['created_at'] as String?)?.trim() ?? '';
        final updatedAt = (item['updated_at'] as String?)?.trim() ?? '';
        final values = <String, String>{};
        if (createdAt.isNotEmpty) {
          values['created_at'] = createdAt;
        }
        if (updatedAt.isNotEmpty) {
          values['updated_at'] = updatedAt;
        }
        if (values.isNotEmpty) {
          result[entry.key] = values;
        }
      }
      return result;
    } catch (_) {
      return const <String, Map<String, String>>{};
    }
  }

  Future<void> _writeTeacherPromptTimestampMetadata({
    required int remoteUserId,
    required int remoteCourseId,
    required Map<String, Map<String, String>> values,
  }) async {
    final encoded = jsonEncode(values);
    await _db.into(_db.syncMetadataEntries).insertOnConflictUpdate(
          SyncMetadataEntriesCompanion.insert(
            remoteUserId: remoteUserId,
            kind: _syncMetadataKindTeacherPromptTimestamps,
            domain: _syncMetadataDomainTeacherPromptTimestamps,
            scopeKey: _teacherCourseScopeKey(remoteCourseId),
            value: encoded,
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<void> _applyPromptMetadataForTeacher({
    required User currentUser,
    required int remoteCourseId,
    required Map<String, dynamic> metadata,
    required CourseVersion course,
  }) async {
    final schema = (metadata['schema'] as String?)?.trim() ?? '';
    if (!isSupportedPromptBundleSchema(schema)) {
      return;
    }
    final courseKey = course.sourcePath?.trim();
    if (courseKey == null || courseKey.isEmpty) {
      return;
    }
    final assignments = await _db.getAssignmentsForCourse(course.id);
    final assignedStudentIds =
        assignments.map((assignment) => assignment.studentId).toSet();
    final referencedStudentIds = <int>{};
    final importedTimestampStrings = <String, Map<String, String>>{};

    await _db.transaction(() async {
      await (_db.update(_db.promptTemplates)
            ..where((tbl) =>
                tbl.teacherId.equals(currentUser.id) &
                (tbl.courseKey.equals(courseKey) |
                    (tbl.courseKey.isNull() &
                        (tbl.studentId.isNull() |
                            (assignedStudentIds.isEmpty
                                ? const Constant(false)
                                : tbl.studentId.isIn(assignedStudentIds)))))))
          .write(PromptTemplatesCompanion(isActive: Value(false)));
      await (_db.delete(_db.studentPromptProfiles)
            ..where((tbl) =>
                tbl.teacherId.equals(currentUser.id) &
                ((tbl.courseKey.equals(courseKey)) |
                    (tbl.courseKey.isNull() &
                        (tbl.studentId.isNull() |
                            (assignedStudentIds.isEmpty
                                ? const Constant(false)
                                : tbl.studentId.isIn(assignedStudentIds)))))))
          .go();
      await _db.deleteStudentPassConfigsForCourse(course.id);
    });

    final promptTemplates = metadata['prompt_templates'];
    if (promptTemplates is List) {
      for (final item in promptTemplates) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final promptName = (item['prompt_name'] as String?)?.trim() ?? '';
        final content = (item['content'] as String?)?.trim() ?? '';
        final scope = (item['scope'] as String?)?.trim() ?? '';
        if (promptName.isEmpty || content.isEmpty) {
          continue;
        }
        final validation = _promptValidator.validate(
          promptName: promptName,
          content: content,
        );
        if (!validation.isValid) {
          throw StateError(
            'Synced prompt metadata is invalid for "$promptName" scope '
            '"$scope". missing=${validation.missingVariables.join(',')} '
            'unknown=${validation.unknownVariables.join(',')} '
            'invalid=${validation.invalidVariables.join(',')}',
          );
        }

        String? scopeCourseKey;
        int? scopeStudentId;
        int? targetRemoteUserId;
        if (scope == 'teacher') {
          scopeCourseKey = null;
          scopeStudentId = null;
        } else if (scope == 'student_global') {
          targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt() ?? 0;
          if (targetRemoteUserId <= 0) {
            continue;
          }
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          scopeCourseKey = null;
          scopeStudentId =
              await _remoteStudentIdentity.resolveOrCreateLocalStudentId(
            db: _db,
            remoteStudentId: targetRemoteUserId,
            usernameHint: targetUsername,
            teacherId: currentUser.id,
          );
        } else if (scope == 'course') {
          scopeCourseKey = courseKey;
          scopeStudentId = null;
        } else if (scope == 'student_course' || scope == 'student') {
          targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt() ?? 0;
          if (targetRemoteUserId <= 0) {
            continue;
          }
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          scopeCourseKey = courseKey;
          scopeStudentId =
              await _remoteStudentIdentity.resolveOrCreateLocalStudentId(
            db: _db,
            remoteStudentId: targetRemoteUserId,
            usernameHint: targetUsername,
            teacherId: currentUser.id,
          );
        } else {
          continue;
        }

        if (scopeStudentId != null) {
          referencedStudentIds.add(scopeStudentId);
        }
        final createdAtRaw = (item['created_at'] as String?)?.trim() ?? '';
        if (createdAtRaw.isNotEmpty) {
          importedTimestampStrings[_teacherPromptTemplateTimestampKey(
            promptName: promptName,
            scope: scope,
            studentRemoteUserId: targetRemoteUserId,
          )] = <String, String>{'created_at': createdAtRaw};
        }
        await _db.importPromptTemplate(
          teacherId: currentUser.id,
          promptName: promptName,
          content: content,
          createdAt:
              _parseMetadataTimestamp(item['created_at']) ?? DateTime.now(),
          courseKey: scopeCourseKey,
          studentId: scopeStudentId,
        );
      }
    }

    final profiles = metadata['student_prompt_profiles'];
    if (profiles is List) {
      for (final item in profiles) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final scope = (item['scope'] as String?)?.trim() ?? '';
        String? scopeCourseKey;
        int? scopeStudentId;
        int? targetRemoteUserId;

        if (scope == 'teacher') {
          scopeCourseKey = null;
          scopeStudentId = null;
        } else if (scope == 'student_global') {
          targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt() ?? 0;
          if (targetRemoteUserId <= 0) {
            continue;
          }
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          scopeCourseKey = null;
          scopeStudentId =
              await _remoteStudentIdentity.resolveOrCreateLocalStudentId(
            db: _db,
            remoteStudentId: targetRemoteUserId,
            usernameHint: targetUsername,
            teacherId: currentUser.id,
          );
        } else if (scope == 'course') {
          scopeCourseKey = courseKey;
          scopeStudentId = null;
        } else if (scope == 'student_course' || scope == 'student') {
          targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt() ?? 0;
          if (targetRemoteUserId <= 0) {
            continue;
          }
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          scopeCourseKey = courseKey;
          scopeStudentId =
              await _remoteStudentIdentity.resolveOrCreateLocalStudentId(
            db: _db,
            remoteStudentId: targetRemoteUserId,
            usernameHint: targetUsername,
            teacherId: currentUser.id,
          );
        } else {
          continue;
        }

        if (scopeStudentId != null) {
          referencedStudentIds.add(scopeStudentId);
        }
        final profileTimestamps = <String, String>{};
        final createdAtRaw = (item['created_at'] as String?)?.trim() ?? '';
        final updatedAtRaw = (item['updated_at'] as String?)?.trim() ?? '';
        if (createdAtRaw.isNotEmpty) {
          profileTimestamps['created_at'] = createdAtRaw;
        }
        if (updatedAtRaw.isNotEmpty) {
          profileTimestamps['updated_at'] = updatedAtRaw;
        }
        if (profileTimestamps.isNotEmpty) {
          importedTimestampStrings[_teacherProfileTimestampKey(
            scope: scope,
            studentRemoteUserId: targetRemoteUserId,
          )] = profileTimestamps;
        }
        await _db.importStudentPromptProfile(
          teacherId: currentUser.id,
          courseKey: scopeCourseKey,
          studentId: scopeStudentId,
          gradeLevel: item['grade_level'] as String?,
          readingLevel: item['reading_level'] as String?,
          preferredLanguage: item['preferred_language'] as String?,
          interests: item['interests'] as String?,
          preferredTone: item['preferred_tone'] as String?,
          preferredPace: item['preferred_pace'] as String?,
          preferredFormat: item['preferred_format'] as String?,
          supportNotes: item['support_notes'] as String?,
          createdAt: _parseMetadataTimestamp(item['created_at']),
          updatedAt: _parseMetadataTimestamp(item['updated_at']),
        );
      }
    }

    final passConfigs = metadata['student_pass_configs'];
    if (passConfigs is List) {
      for (final item in passConfigs) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final targetRemoteUserId =
            (item['student_remote_user_id'] as num?)?.toInt() ?? 0;
        if (targetRemoteUserId <= 0) {
          continue;
        }
        final targetUsername =
            (item['student_username'] as String?)?.trim() ?? '';
        final targetStudentId =
            await _remoteStudentIdentity.resolveOrCreateLocalStudentId(
          db: _db,
          remoteStudentId: targetRemoteUserId,
          usernameHint: targetUsername,
          teacherId: currentUser.id,
        );
        referencedStudentIds.add(targetStudentId);
        final passTimestamps = <String, String>{};
        final createdAtRaw = (item['created_at'] as String?)?.trim() ?? '';
        final updatedAtRaw = (item['updated_at'] as String?)?.trim() ?? '';
        if (createdAtRaw.isNotEmpty) {
          passTimestamps['created_at'] = createdAtRaw;
        }
        if (updatedAtRaw.isNotEmpty) {
          passTimestamps['updated_at'] = updatedAtRaw;
        }
        if (passTimestamps.isNotEmpty) {
          importedTimestampStrings[_teacherPassConfigTimestampKey(
            studentRemoteUserId: targetRemoteUserId,
          )] = passTimestamps;
        }
        await _db.importStudentPassConfig(
          courseVersionId: course.id,
          studentId: targetStudentId,
          easyWeight: ((item['easy_weight'] as num?)?.toDouble()) ??
              ResolvedStudentPassRule.defaultEasyWeight,
          mediumWeight: ((item['medium_weight'] as num?)?.toDouble()) ??
              ResolvedStudentPassRule.defaultMediumWeight,
          hardWeight: ((item['hard_weight'] as num?)?.toDouble()) ??
              ResolvedStudentPassRule.defaultHardWeight,
          passThreshold: ((item['pass_threshold'] as num?)?.toDouble()) ??
              ResolvedStudentPassRule.defaultPassThreshold,
          createdAt: _parseMetadataTimestamp(item['created_at']),
          updatedAt: _parseMetadataTimestamp(item['updated_at']),
        );
      }
    }

    for (final studentId in referencedStudentIds) {
      await _db.assignStudent(
        studentId: studentId,
        courseVersionId: course.id,
      );
    }
    if (currentUser.remoteUserId != null && currentUser.remoteUserId! > 0) {
      await _writeTeacherPromptTimestampMetadata(
        remoteUserId: currentUser.remoteUserId!,
        remoteCourseId: remoteCourseId,
        values: importedTimestampStrings,
      );
    }

    _promptRepository.invalidatePromptCache();
  }

  Future<void> _applyPromptMetadataForStudent({
    required User currentUser,
    required Map<String, dynamic> metadata,
    required CourseVersion course,
  }) async {
    final schema = (metadata['schema'] as String?)?.trim() ?? '';
    if (!isSupportedPromptBundleSchema(schema)) {
      return;
    }
    final courseKey = course.sourcePath?.trim();
    if (courseKey == null || courseKey.isEmpty) {
      return;
    }

    await _db.transaction(() async {
      for (final promptName in const <String>['learn', 'review']) {
        await _db.clearActivePromptTemplates(
          teacherId: course.teacherId,
          promptName: promptName,
          courseKey: null,
          studentId: null,
        );
        await _db.clearActivePromptTemplates(
          teacherId: course.teacherId,
          promptName: promptName,
          courseKey: null,
          studentId: currentUser.id,
        );
        await _db.clearActivePromptTemplates(
          teacherId: course.teacherId,
          promptName: promptName,
          courseKey: courseKey,
          studentId: null,
        );
        await _db.clearActivePromptTemplates(
          teacherId: course.teacherId,
          promptName: promptName,
          courseKey: courseKey,
          studentId: currentUser.id,
        );
      }
      await _db.deleteStudentPromptProfile(
        teacherId: course.teacherId,
        courseKey: null,
        studentId: null,
      );
      await _db.deleteStudentPromptProfile(
        teacherId: course.teacherId,
        courseKey: null,
        studentId: currentUser.id,
      );
      await _db.deleteStudentPromptProfile(
        teacherId: course.teacherId,
        courseKey: courseKey,
        studentId: null,
      );
      await _db.deleteStudentPromptProfile(
        teacherId: course.teacherId,
        courseKey: courseKey,
        studentId: currentUser.id,
      );
      await _db.deleteStudentPassConfig(
        courseVersionId: course.id,
        studentId: currentUser.id,
      );
    });

    final promptTemplates = metadata['prompt_templates'];
    if (promptTemplates is List) {
      for (final item in promptTemplates) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final promptName = (item['prompt_name'] as String?)?.trim() ?? '';
        final content = (item['content'] as String?)?.trim() ?? '';
        final scope = (item['scope'] as String?)?.trim() ?? '';
        if (promptName.isEmpty || content.isEmpty) {
          continue;
        }
        final validation = _promptValidator.validate(
          promptName: promptName,
          content: content,
        );
        if (!validation.isValid) {
          throw StateError(
            'Synced prompt metadata is invalid for "$promptName" scope '
            '"$scope". missing=${validation.missingVariables.join(',')} '
            'unknown=${validation.unknownVariables.join(',')} '
            'invalid=${validation.invalidVariables.join(',')}',
          );
        }

        String? scopeCourseKey;
        int? scopeStudentId;
        if (scope == 'teacher') {
          scopeCourseKey = null;
          scopeStudentId = null;
        } else if (scope == 'student_global') {
          final targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt();
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          final remoteMatched = currentUser.remoteUserId != null &&
              targetRemoteUserId != null &&
              targetRemoteUserId > 0 &&
              currentUser.remoteUserId == targetRemoteUserId;
          final usernameMatched = targetUsername.isNotEmpty &&
              targetUsername.toLowerCase() ==
                  currentUser.username.toLowerCase();
          if (!remoteMatched && !usernameMatched) {
            continue;
          }
          scopeCourseKey = null;
          scopeStudentId = currentUser.id;
        } else if (scope == 'course') {
          scopeCourseKey = courseKey;
          scopeStudentId = null;
        } else if (scope == 'student_course' || scope == 'student') {
          final targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt();
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          final remoteMatched = currentUser.remoteUserId != null &&
              targetRemoteUserId != null &&
              targetRemoteUserId > 0 &&
              currentUser.remoteUserId == targetRemoteUserId;
          final usernameMatched = targetUsername.isNotEmpty &&
              targetUsername.toLowerCase() ==
                  currentUser.username.toLowerCase();
          if (!remoteMatched && !usernameMatched) {
            continue;
          }
          scopeCourseKey = courseKey;
          scopeStudentId = currentUser.id;
        } else {
          continue;
        }

        await _db.importPromptTemplate(
          teacherId: course.teacherId,
          promptName: promptName,
          content: content,
          createdAt:
              _parseMetadataTimestamp(item['created_at']) ?? DateTime.now(),
          courseKey: scopeCourseKey,
          studentId: scopeStudentId,
        );
      }
    }

    final profiles = metadata['student_prompt_profiles'];
    if (profiles is List) {
      for (final item in profiles) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final scope = (item['scope'] as String?)?.trim() ?? '';
        String? scopeCourseKey;
        int? scopeStudentId;
        if (scope == 'teacher') {
          scopeCourseKey = null;
          scopeStudentId = null;
        } else if (scope == 'student_global') {
          final targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt();
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          final remoteMatched = currentUser.remoteUserId != null &&
              targetRemoteUserId != null &&
              targetRemoteUserId > 0 &&
              currentUser.remoteUserId == targetRemoteUserId;
          final usernameMatched = targetUsername.isNotEmpty &&
              targetUsername.toLowerCase() ==
                  currentUser.username.toLowerCase();
          if (!remoteMatched && !usernameMatched) {
            continue;
          }
          scopeCourseKey = null;
          scopeStudentId = currentUser.id;
        } else if (scope == 'course') {
          scopeCourseKey = courseKey;
          scopeStudentId = null;
        } else if (scope == 'student_course' || scope == 'student') {
          final targetRemoteUserId =
              (item['student_remote_user_id'] as num?)?.toInt();
          final targetUsername =
              (item['student_username'] as String?)?.trim() ?? '';
          final remoteMatched = currentUser.remoteUserId != null &&
              targetRemoteUserId != null &&
              targetRemoteUserId > 0 &&
              currentUser.remoteUserId == targetRemoteUserId;
          final usernameMatched = targetUsername.isNotEmpty &&
              targetUsername.toLowerCase() ==
                  currentUser.username.toLowerCase();
          if (!remoteMatched && !usernameMatched) {
            continue;
          }
          scopeCourseKey = courseKey;
          scopeStudentId = currentUser.id;
        } else {
          continue;
        }

        await _db.importStudentPromptProfile(
          teacherId: course.teacherId,
          courseKey: scopeCourseKey,
          studentId: scopeStudentId,
          gradeLevel: item['grade_level'] as String?,
          readingLevel: item['reading_level'] as String?,
          preferredLanguage: item['preferred_language'] as String?,
          interests: item['interests'] as String?,
          preferredTone: item['preferred_tone'] as String?,
          preferredPace: item['preferred_pace'] as String?,
          preferredFormat: item['preferred_format'] as String?,
          supportNotes: item['support_notes'] as String?,
          createdAt: _parseMetadataTimestamp(item['created_at']),
          updatedAt: _parseMetadataTimestamp(item['updated_at']),
        );
      }
    }

    final passConfigs = metadata['student_pass_configs'];
    if (passConfigs is List) {
      for (final item in passConfigs) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final targetRemoteUserId =
            (item['student_remote_user_id'] as num?)?.toInt();
        final targetUsername =
            (item['student_username'] as String?)?.trim() ?? '';
        final remoteMatched = currentUser.remoteUserId != null &&
            targetRemoteUserId != null &&
            targetRemoteUserId > 0 &&
            currentUser.remoteUserId == targetRemoteUserId;
        final usernameMatched = targetUsername.isNotEmpty &&
            targetUsername.toLowerCase() == currentUser.username.toLowerCase();
        if (!remoteMatched && !usernameMatched) {
          continue;
        }
        await _db.importStudentPassConfig(
          courseVersionId: course.id,
          studentId: currentUser.id,
          easyWeight: ((item['easy_weight'] as num?)?.toDouble()) ??
              ResolvedStudentPassRule.defaultEasyWeight,
          mediumWeight: ((item['medium_weight'] as num?)?.toDouble()) ??
              ResolvedStudentPassRule.defaultMediumWeight,
          hardWeight: ((item['hard_weight'] as num?)?.toDouble()) ??
              ResolvedStudentPassRule.defaultHardWeight,
          passThreshold: ((item['pass_threshold'] as num?)?.toDouble()) ??
              ResolvedStudentPassRule.defaultPassThreshold,
          createdAt: _parseMetadataTimestamp(item['created_at']),
          updatedAt: _parseMetadataTimestamp(item['updated_at']),
        );
      }
    }

    _promptRepository.invalidatePromptCache();
  }

  String _teacherCourseScopeKey(int remoteCourseId) {
    return 'course:$remoteCourseId';
  }

  CourseVersion? _findLocalCourseCandidate({
    required List<CourseVersion> localCourses,
    required Map<int, int?> localRemoteIdByCourseVersion,
    required String targetSubject,
  }) {
    final normalizedTarget =
        _normalizeCourseName(_stripVersionSuffix(targetSubject));
    final candidates = localCourses.where((course) {
      if ((localRemoteIdByCourseVersion[course.id] ?? 0) > 0) {
        return false;
      }
      final normalizedCourse =
          _normalizeCourseName(_stripVersionSuffix(course.subject));
      return normalizedCourse == normalizedTarget;
    }).toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((left, right) {
      final leftSuffix = _hasVersionSuffix(left.subject) ? 1 : 0;
      final rightSuffix = _hasVersionSuffix(right.subject) ? 1 : 0;
      if (leftSuffix != rightSuffix) {
        return leftSuffix - rightSuffix;
      }
      final leftHasSource = ((left.sourcePath ?? '').trim().isNotEmpty) ? 0 : 1;
      final rightHasSource =
          ((right.sourcePath ?? '').trim().isNotEmpty) ? 0 : 1;
      if (leftHasSource != rightHasSource) {
        return leftHasSource - rightHasSource;
      }
      return left.id - right.id;
    });
    return candidates.first;
  }

  Future<bool> _cleanupTeacherLocalDuplicates(int teacherId) async {
    var changed = false;
    final localCourses = await _db.getCourseVersionsForTeacher(teacherId);
    final localRemoteIdByCourseVersion = <int, int?>{};
    for (final course in localCourses) {
      localRemoteIdByCourseVersion[course.id] = await _db.getRemoteCourseId(
        course.id,
      );
    }

    for (final course in localCourses) {
      final remoteId = localRemoteIdByCourseVersion[course.id];
      if (remoteId != null && remoteId > 0) {
        continue;
      }
      if (!_hasVersionSuffix(course.subject)) {
        continue;
      }
      final baseSubject = _stripVersionSuffix(course.subject);
      CourseVersion? canonical;
      for (final other in localCourses) {
        if (other.id == course.id) {
          continue;
        }
        final otherRemoteId = localRemoteIdByCourseVersion[other.id];
        if (otherRemoteId == null || otherRemoteId <= 0) {
          continue;
        }
        final otherBase = _stripVersionSuffix(other.subject);
        if (_normalizeCourseName(otherBase) ==
            _normalizeCourseName(baseSubject)) {
          canonical = other;
          break;
        }
      }
      if (canonical == null) {
        continue;
      }
      final assignments = await _db.getAssignmentsForCourse(course.id);
      for (final assignment in assignments) {
        await _db.migrateStudentCourseData(
          studentId: assignment.studentId,
          fromCourseVersionId: course.id,
          toCourseVersionId: canonical.id,
        );
      }
      await _cleanupCourseIfOrphaned(course.id);
      changed = true;
    }
    return changed;
  }

  Future<void> _repairStudentStaleDuplicateCourses({
    required User currentUser,
    required List<EnrollmentSummary> enrollments,
  }) async {
    final canonicalCourseByBase = <String, int>{};
    for (final enrollment in enrollments) {
      final courseVersionId =
          await _db.getCourseVersionIdForRemoteCourse(enrollment.courseId);
      if (courseVersionId == null) {
        continue;
      }
      final baseKey = _normalizeCourseName(enrollment.courseSubject);
      canonicalCourseByBase[baseKey] = courseVersionId;
    }

    final assignedCourses =
        await _db.getAssignedCoursesForStudent(currentUser.id);
    for (final course in assignedCourses) {
      final remoteCourseId = await _db.getRemoteCourseId(course.id);
      if (remoteCourseId != null && remoteCourseId > 0) {
        continue;
      }
      if (!_hasVersionSuffix(course.subject)) {
        continue;
      }
      final baseKey = _normalizeCourseName(_stripVersionSuffix(course.subject));
      final canonicalCourseVersionId = canonicalCourseByBase[baseKey];
      if (canonicalCourseVersionId == null ||
          canonicalCourseVersionId == course.id) {
        continue;
      }
      await _db.migrateStudentCourseData(
        studentId: currentUser.id,
        fromCourseVersionId: course.id,
        toCourseVersionId: canonicalCourseVersionId,
      );
      await _cleanupCourseIfOrphaned(course.id);
    }
  }

  Future<void> _ensureCourseSubject({
    required int courseVersionId,
    required String expectedSubject,
  }) async {
    final normalizedExpected = expectedSubject.trim();
    if (normalizedExpected.isEmpty) {
      return;
    }
    final existing = await _db.getCourseVersionById(courseVersionId);
    if (existing == null) {
      return;
    }
    if (existing.subject.trim() == normalizedExpected) {
      return;
    }
    await _db.updateCourseVersionSubject(
      id: courseVersionId,
      subject: normalizedExpected,
    );
  }

  Future<void> _ensureCourseTeacher({
    required int courseVersionId,
    required int expectedTeacherId,
  }) async {
    final existing = await _db.getCourseVersionById(courseVersionId);
    if (existing == null) {
      return;
    }
    if (existing.teacherId == expectedTeacherId) {
      return;
    }
    await _db.updateCourseVersionTeacherId(
      id: courseVersionId,
      teacherId: expectedTeacherId,
    );
  }

  Future<void> _claimTeacherCourseOwnership({
    required User currentUser,
    required int courseVersionId,
    required List<CourseVersion> localCourses,
    required Map<int, int?> localRemoteIdByCourseVersion,
  }) async {
    final existing = await _db.getCourseVersionById(courseVersionId);
    if (existing == null) {
      return;
    }
    if (existing.teacherId != currentUser.id) {
      final existingTeacher = await _db.getUserById(existing.teacherId);
      if (existingTeacher != null && existingTeacher.role == 'teacher') {
        await _db.mergeUsers(
          keepUserId: currentUser.id,
          removeUserId: existingTeacher.id,
        );
      } else {
        await _db.updateCourseVersionTeacherId(
          id: courseVersionId,
          teacherId: currentUser.id,
        );
      }
    }
    final refreshed = await _db.getCourseVersionById(courseVersionId);
    if (refreshed == null) {
      return;
    }
    final assignments = await _db.getAssignmentsForCourse(refreshed.id);
    for (final assignment in assignments) {
      await _db.updateStudentTeacherId(
        studentId: assignment.studentId,
        teacherId: currentUser.id,
      );
    }
    final existingIndex = localCourses.indexWhere((course) {
      return course.id == refreshed.id;
    });
    if (existingIndex >= 0) {
      localCourses[existingIndex] = refreshed;
    } else {
      localCourses.add(refreshed);
    }
    localRemoteIdByCourseVersion[refreshed.id] = await _db.getRemoteCourseId(
      refreshed.id,
    );
  }

  String _normalizeCourseName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _hasVersionSuffix(String value) {
    return _versionSuffixPattern.hasMatch(value.trim());
  }

  String _stripVersionSuffix(String value) {
    final trimmed = value.trim();
    return trimmed.replaceFirst(_versionSuffixPattern, '');
  }
}

class _PreparedTeacherCourseBundle {
  _PreparedTeacherCourseBundle({
    required this.bundleFile,
    required this.hash,
  });

  final File bundleFile;
  final String hash;
}

class _ResolvedRemoteBundleInfo {
  const _ResolvedRemoteBundleInfo({
    required this.bundleVersionId,
    required this.hash,
  });

  final int bundleVersionId;
  final String hash;
}

class _ResolvedCourseSyncState {
  const _ResolvedCourseSyncState({
    required this.courseVersionId,
    required this.installedVersion,
    required this.syncState,
    required this.localCourse,
    required this.replacedCourseVersionId,
  });

  final int? courseVersionId;
  final int? installedVersion;
  final SyncItemState? syncState;
  final CourseVersion? localCourse;
  final int? replacedCourseVersionId;
}

class _RemoteCourseSyncResult {
  const _RemoteCourseSyncResult({
    required this.course,
    required this.replacedCourseVersionId,
  });

  final CourseVersion course;
  final int? replacedCourseVersionId;
}

class _SyncTransferSummary {
  _SyncTransferSummary();
  final List<SyncTransferLogItem> uploaded = <SyncTransferLogItem>[];
  final List<SyncTransferLogItem> downloaded = <SyncTransferLogItem>[];

  SyncRunStats toStats() {
    final stats = SyncRunStats();
    stats.addUploaded(
      count: uploaded.length,
      bytes: uploaded.fold<int>(0, (total, item) => total + item.sizeBytes),
    );
    stats.addDownloaded(
      count: downloaded.length,
      bytes: downloaded.fold<int>(0, (total, item) => total + item.sizeBytes),
    );
    return stats;
  }
}
