import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/services/artifact_sync_api_service.dart';
import 'package:tutor1on1/services/enrollment_sync_service.dart';
import 'package:tutor1on1/services/home_sync_coordinator.dart';
import 'package:tutor1on1/services/session_sync_service.dart';
import 'package:tutor1on1/services/sync_log_repository.dart';
import 'package:tutor1on1/services/sync_progress.dart';

class _LoginEnrollmentSyncService implements EnrollmentSyncService {
  _LoginEnrollmentSyncService(this.remoteState2);

  final String remoteState2;
  int state1ReadCalls = 0;
  int fastPathRefreshCalls = 0;

  @override
  Future<Map<String, String>> buildCanonicalVisibleArtifactHashes({
    required User currentUser,
  }) async {
    return const <String, String>{};
  }

  @override
  Future<String> readCanonicalRemoteState2() async => remoteState2;

  @override
  Future<ArtifactState1Result> readCanonicalRemoteState1() async {
    state1ReadCalls++;
    return ArtifactState1Result(
      state2: remoteState2,
      items: const <ArtifactState1Item>[],
    );
  }

  @override
  Future<void> refreshStoredLocalState2({required User currentUser}) async {
    fastPathRefreshCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoginSessionSyncService implements SessionSyncService {
  _LoginSessionSyncService({
    required this.artifactId,
    required this.shaValue,
    required this.hasPendingManifestChanges,
  });

  final String artifactId;
  final String shaValue;
  final bool hasPendingManifestChanges;
  int canonicalSyncCalls = 0;

  @override
  Future<Map<String, String>> buildCanonicalVisibleArtifactHashes({
    required User currentUser,
  }) async {
    return <String, String>{artifactId: shaValue};
  }

  @override
  Future<bool> hasPendingCanonicalManifestChanges({
    required User currentUser,
  }) async {
    return hasPendingManifestChanges;
  }

  @override
  Future<SyncRunStats> syncFromCanonicalState1({
    required User currentUser,
    required List<ArtifactState1Item> visibleItems,
    SyncProgressCallback? onProgress,
    SessionSyncMode mode = SessionSyncMode.downloadOnly,
  }) async {
    canonicalSyncCalls++;
    return SyncRunStats();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoginSyncLogRepository implements SyncLogRepository {
  @override
  Future<void> appendRunEvent({
    required String trigger,
    required String actorRole,
    required int actorUserId,
    required SyncRunStats stats,
    required bool success,
    String? error,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('describeSyncFailure keeps user message neutral and raw detail in log',
      () {
    final presentation = describeSyncFailure(
      stage: 'Enrollment sync',
      error: ArtifactSyncApiException(
        'Could not contact api.tutor1on1.org from this device. Check DNS, proxy, VPN, or firewall settings and retry.',
        debugMessage:
            "Transport request to https://api.tutor1on1.org/api/artifacts/sync/state2?artifact_class=course_bundle failed: ClientException with SocketException: Failed host lookup: 'api.tutor1on1.org'",
      ),
    );

    expect(
      presentation.userMessage,
      'Enrollment sync failed: Could not contact api.tutor1on1.org from this device. Check DNS, proxy, VPN, or firewall settings and retry.',
    );
    expect(
      presentation.logMessage,
      contains('Failed host lookup'),
    );
    expect(
      presentation.logMessage,
      startsWith(
          'Enrollment sync failed: Transport request to https://api.tutor1on1.org'),
    );
  });

  test('describeSyncFailure keeps non-network errors readable', () {
    final presentation = describeSyncFailure(
      stage: 'Session sync',
      error: StateError('student artifact invalid'),
    );

    expect(
      presentation.userMessage,
      'Session sync failed: Bad state: student artifact invalid',
    );
    expect(
      presentation.logMessage,
      'Session sync failed: StateError: Bad state: student artifact invalid',
    );
  });

  test('login state2 fast path does not hide a pending session manifest base',
      () async {
    const artifactId = 'student_kp:3001:200:1.1';
    const shaValue =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final remoteState2 =
        'artifact_state2_v1:${sha256.convert(utf8.encode('$artifactId|$shaValue\n'))}';
    final enrollmentSync = _LoginEnrollmentSyncService(remoteState2);
    final sessionSync = _LoginSessionSyncService(
      artifactId: artifactId,
      shaValue: shaValue,
      hasPendingManifestChanges: true,
    );
    final coordinator = HomeSyncCoordinator(
      enrollmentSyncService: enrollmentSync,
      sessionSyncService: sessionSync,
      syncLogRepository: _LoginSyncLogRepository(),
    );
    final user = User(
      id: 7,
      username: 'albert',
      pinHash: 'hash',
      role: 'student',
      remoteUserId: 3001,
      createdAt: DateTime.utc(2026, 7, 26),
    );

    await coordinator.runLoginSync(
      user: user,
      trigger: 'login',
      onProgress: null,
      includeEnrollmentSync: false,
      includeSessionSync: true,
      sessionSyncMode: SessionSyncMode.downloadOnly,
    );

    expect(enrollmentSync.state1ReadCalls, 1);
    expect(enrollmentSync.fastPathRefreshCalls, 0);
    expect(sessionSync.canonicalSyncCalls, 1);
  });
}
