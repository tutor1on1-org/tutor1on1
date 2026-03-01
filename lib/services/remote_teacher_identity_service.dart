import '../db/app_database.dart';
import '../security/pin_hasher.dart';

class RemoteTeacherIdentityService {
  const RemoteTeacherIdentityService();

  static const String _placeholderPinSeed = 'remote_teacher_placeholder';

  Future<int> resolveOrCreateLocalTeacherId({
    required AppDatabase db,
    required int remoteTeacherId,
  }) async {
    if (remoteTeacherId <= 0) {
      throw StateError(
        'Remote teacher id must be positive for marketplace enrollment sync.',
      );
    }
    final existing = await db.findUserByRemoteId(remoteTeacherId);
    if (existing != null) {
      if (existing.role != 'teacher') {
        throw StateError(
          'Remote teacher id $remoteTeacherId maps to non-teacher local user '
          '${existing.id} (${existing.role}).',
        );
      }
      return existing.id;
    }
    final username = await _buildUniquePlaceholderUsername(
      db: db,
      remoteTeacherId: remoteTeacherId,
    );
    return db.createUser(
      username: username,
      pinHash: PinHasher.hash(_placeholderPinSeed),
      role: 'teacher',
      remoteUserId: remoteTeacherId,
    );
  }

  Future<String> _buildUniquePlaceholderUsername({
    required AppDatabase db,
    required int remoteTeacherId,
  }) async {
    final base = 'remote_teacher_$remoteTeacherId';
    var candidate = base;
    var suffix = 1;
    while (await db.findUserByUsername(candidate) != null) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }
}
