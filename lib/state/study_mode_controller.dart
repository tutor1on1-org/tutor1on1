import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../services/marketplace_api_service.dart';
import '../services/screen_lock_service.dart';

class StudyModeController extends ChangeNotifier {
  StudyModeController({
    ScreenLockService? screenLockService,
  }) : _screenLockService = screenLockService ?? ScreenLockService.instance;

  final ScreenLockService _screenLockService;

  bool _enabled = false;
  String _effectiveSource = 'default';
  int _controllerTeacherUserId = 0;
  String _controllerTeacherName = '';
  int _activeScheduleId = 0;
  String _activeScheduleLabel = '';
  int? _activeStudentUserId;
  int? _activeStudentRemoteUserId;

  bool get enabled => _enabled;
  String get effectiveSource => _effectiveSource;
  int get controllerTeacherUserId => _controllerTeacherUserId;
  String get controllerTeacherName => _controllerTeacherName;
  int get activeScheduleId => _activeScheduleId;
  String get activeScheduleLabel => _activeScheduleLabel;

  bool get requiresTeacherPin =>
      _enabled && _effectiveSource.trim().toLowerCase() != 'default';

  Future<void> syncAuthUser(User? user) async {
    final remoteUserId = user?.remoteUserId ?? 0;
    final isStudent = user?.role == 'student' && remoteUserId > 0;
    if (!isStudent) {
      await clear();
      return;
    }
    final sameStudent = _activeStudentUserId == user!.id &&
        _activeStudentRemoteUserId == remoteUserId;
    _activeStudentUserId = user.id;
    _activeStudentRemoteUserId = remoteUserId;
    if (sameStudent && !_enabled && _effectiveSource == 'default') {
      return;
    }
    await _setState(
      enabled: false,
      effectiveSource: 'default',
      controllerTeacherUserId: 0,
      controllerTeacherName: '',
      activeScheduleId: 0,
      activeScheduleLabel: '',
    );
  }

  Future<void> applyHeartbeat(
    User user,
    StudentDeviceHeartbeatResponse response,
  ) async {
    final remoteUserId = user.remoteUserId ?? 0;
    if (user.role != 'student' || remoteUserId <= 0) {
      await clear();
      return;
    }
    _activeStudentUserId = user.id;
    _activeStudentRemoteUserId = remoteUserId;
    await _setState(
      enabled: response.effectiveEnabled,
      effectiveSource: response.effectiveSource,
      controllerTeacherUserId: response.controllerTeacherUserId,
      controllerTeacherName: response.controllerTeacherName,
      activeScheduleId: response.activeScheduleId,
      activeScheduleLabel: response.activeScheduleLabel,
    );
  }

  Future<void> clear() async {
    _activeStudentUserId = null;
    _activeStudentRemoteUserId = null;
    await _setState(
      enabled: false,
      effectiveSource: 'default',
      controllerTeacherUserId: 0,
      controllerTeacherName: '',
      activeScheduleId: 0,
      activeScheduleLabel: '',
    );
  }

  Future<void> _setState({
    required bool enabled,
    required String effectiveSource,
    required int controllerTeacherUserId,
    required String controllerTeacherName,
    required int activeScheduleId,
    required String activeScheduleLabel,
  }) async {
    final normalizedSource = effectiveSource.trim().toLowerCase();
    final nextEnabled =
        enabled && normalizedSource.isNotEmpty && normalizedSource != 'default';
    final nextTeacherUserId = nextEnabled ? controllerTeacherUserId : 0;
    final nextTeacherName = nextEnabled ? controllerTeacherName.trim() : '';
    final nextScheduleId = nextEnabled ? activeScheduleId : 0;
    final nextScheduleLabel = nextEnabled ? activeScheduleLabel.trim() : '';
    if (_enabled == nextEnabled &&
        _effectiveSource == normalizedSource &&
        _controllerTeacherUserId == nextTeacherUserId &&
        _controllerTeacherName == nextTeacherName &&
        _activeScheduleId == nextScheduleId &&
        _activeScheduleLabel == nextScheduleLabel) {
      return;
    }
    _enabled = nextEnabled;
    _effectiveSource = normalizedSource.isEmpty ? 'default' : normalizedSource;
    _controllerTeacherUserId = nextTeacherUserId;
    _controllerTeacherName = nextTeacherName;
    _activeScheduleId = nextScheduleId;
    _activeScheduleLabel = nextScheduleLabel;
    await _screenLockService.setEnabled(nextEnabled);
    notifyListeners();
  }
}
