import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/services/artifact_sync_api_service.dart';
import 'package:tutor1on1/services/home_sync_coordinator.dart';

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
}
