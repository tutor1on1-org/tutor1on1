import '../db/app_database.dart';
import '../security/pin_hasher.dart';

class RemoteStudentIdentityService {
  const RemoteStudentIdentityService();

  static const String _placeholderPinSeed = 'remote_student_placeholder';

  Future<int> resolveOrCreateLocalStudentId({
    required AppDatabase db,
    required int remoteStudentId,
    String? usernameHint,
    int? teacherId,
  }) async {
    if (remoteStudentId <= 0) {
      throw StateError(
        'Remote student id must be positive for prompt metadata sync.',
      );
    }
    final existing = await db.findUserByRemoteId(remoteStudentId);
    if (existing != null) {
      if (existing.role != 'student') {
        throw StateError(
          'Remote student id $remoteStudentId maps to non-student local user '
          '${existing.id} (${existing.role}).',
        );
      }
      if ((usernameHint ?? '').trim().isNotEmpty) {
        final username = await _buildUniquePlaceholderUsername(
          db: db,
          remoteStudentId: remoteStudentId,
          usernameHint: usernameHint,
          excludeUserId: existing.id,
        );
        if (username.trim().isNotEmpty && username != existing.username) {
          await db.updateUsername(
            userId: existing.id,
            username: username,
          );
        }
      }
      if (teacherId != null && existing.teacherId != teacherId) {
        await db.updateStudentTeacherId(
          studentId: existing.id,
          teacherId: teacherId,
        );
      }
      return existing.id;
    }
    final username = await _buildUniquePlaceholderUsername(
      db: db,
      remoteStudentId: remoteStudentId,
      usernameHint: usernameHint,
    );
    return db.createUser(
      username: username,
      pinHash: PinHasher.hash(_placeholderPinSeed),
      role: 'student',
      teacherId: teacherId,
      remoteUserId: remoteStudentId,
    );
  }

  Future<String> _buildUniquePlaceholderUsername({
    required AppDatabase db,
    required int remoteStudentId,
    String? usernameHint,
    int? excludeUserId,
  }) async {
    final hinted = (usernameHint ?? '').trim();
    final base = hinted.isNotEmpty ? hinted : 'remote_student_$remoteStudentId';
    var candidate = base;
    var suffix = 1;
    while (true) {
      final existing = await db.findUserByUsername(candidate);
      if (existing == null || existing.id == excludeUserId) {
        return candidate;
      }
      candidate = '${base}_$suffix';
      suffix++;
    }
  }
}
