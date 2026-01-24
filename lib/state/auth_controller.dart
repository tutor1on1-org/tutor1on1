import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../security/pin_hasher.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._db);

  final AppDatabase _db;
  User? _currentUser;

  User? get currentUser => _currentUser;

  Future<bool> login(String username, String pin) async {
    final user = await _db.findUserByUsername(username.trim());
    if (user == null) {
      return false;
    }
    final hashed = PinHasher.hash(pin);
    if (user.pinHash != hashed) {
      return false;
    }
    _currentUser = user;
    notifyListeners();
    return true;
  }

  Future<User?> registerTeacher(String username, String pin) async {
    final existing = await _db.findUserByUsername(username.trim());
    if (existing != null) {
      return null;
    }
    final userId = await _db.createUser(
      username: username.trim(),
      pinHash: PinHasher.hash(pin),
      role: 'teacher',
      teacherId: null,
    );
    final user = await _db.getUserById(userId);
    _currentUser = user;
    notifyListeners();
    return user;
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }
}
