import '../db/app_database.dart';
import '../security/pin_hasher.dart';

class RemoteTeacherIdentityService {
  const RemoteTeacherIdentityService();

  static const String _placeholderPinSeed = 'remote_teacher_placeholder';
  static final RegExp _placeholderUsernamePattern = RegExp(
    r'^remote_teacher_\d+(?:_\d+)?$',
  );

  Future<int> resolveOrCreateLocalTeacherId({
    required AppDatabase db,
    required int remoteTeacherId,
    String? usernameHint,
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
      await _syncPlaceholderUsernameIfNeeded(
        db: db,
        user: existing,
        usernameHint: usernameHint,
      );
      return existing.id;
    }
    final username = await _buildUniquePlaceholderUsername(
      db: db,
      remoteTeacherId: remoteTeacherId,
      usernameHint: usernameHint,
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
    String? usernameHint,
  }) async {
    final hinted = _normalizeUsernameHint(usernameHint);
    final base = hinted ?? 'remote_teacher_$remoteTeacherId';
    var candidate = base;
    var suffix = 1;
    while (await db.findUserByUsername(candidate) != null) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }

  Future<void> _syncPlaceholderUsernameIfNeeded({
    required AppDatabase db,
    required User user,
    String? usernameHint,
  }) async {
    final normalizedHint = _normalizeUsernameHint(usernameHint);
    if (normalizedHint == null || normalizedHint == user.username) {
      return;
    }
    if (!_placeholderUsernamePattern.hasMatch(user.username)) {
      return;
    }
    final uniqueUsername = await _buildUniqueUsernameForExistingUser(
      db: db,
      currentUserId: user.id,
      base: normalizedHint,
    );
    if (uniqueUsername == user.username) {
      return;
    }
    await db.updateUsername(
      userId: user.id,
      username: uniqueUsername,
    );
  }

  Future<String> _buildUniqueUsernameForExistingUser({
    required AppDatabase db,
    required int currentUserId,
    required String base,
  }) async {
    var candidate = base;
    var suffix = 1;
    while (true) {
      final existing = await db.findUserByUsername(candidate);
      if (existing == null || existing.id == currentUserId) {
        return candidate;
      }
      candidate = '${base}_$suffix';
      suffix++;
    }
  }

  String? _normalizeUsernameHint(String? usernameHint) {
    final trimmed = (usernameHint ?? '').trim().toLowerCase();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
