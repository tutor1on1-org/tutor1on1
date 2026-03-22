import 'package:flutter_test/flutter_test.dart';

import 'package:family_teacher/db/app_database.dart';
import 'package:family_teacher/services/marketplace_api_service.dart';
import 'package:family_teacher/services/screen_lock_service.dart';
import 'package:family_teacher/state/study_mode_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('teacher-enforced heartbeat enables study mode and PIN requirement',
      () async {
    final bridge = FakeStudyModePlatformBridge(isAndroid: true);
    final service = ScreenLockService(bridge: bridge);
    final controller = StudyModeController(screenLockService: service);
    addTearDown(service.stop);

    final student = _studentUser();
    await controller.syncAuthUser(student);
    await controller.applyHeartbeat(
      student,
      StudentDeviceHeartbeatResponse(
        effectiveEnabled: true,
        effectiveSource: 'manual',
        controllerTeacherUserId: 44,
        controllerTeacherName: 'teacher_a',
        activeScheduleId: 0,
        activeScheduleLabel: '',
      ),
    );

    expect(controller.enabled, isTrue);
    expect(controller.requiresTeacherPin, isTrue);
    expect(controller.controllerTeacherUserId, 44);
    expect(bridge.screenAwake, isTrue);
    expect(bridge.studyUiEnabled, isTrue);
  });

  test('default heartbeat clears teacher-enforced study mode', () async {
    final bridge = FakeStudyModePlatformBridge(isAndroid: true);
    final service = ScreenLockService(bridge: bridge);
    final controller = StudyModeController(screenLockService: service);
    addTearDown(service.stop);

    final student = _studentUser();
    await controller.syncAuthUser(student);
    await controller.applyHeartbeat(
      student,
      StudentDeviceHeartbeatResponse(
        effectiveEnabled: true,
        effectiveSource: 'schedule',
        controllerTeacherUserId: 45,
        controllerTeacherName: 'teacher_b',
        activeScheduleId: 7,
        activeScheduleLabel: 'weekday',
      ),
    );
    await controller.applyHeartbeat(
      student,
      StudentDeviceHeartbeatResponse(
        effectiveEnabled: false,
        effectiveSource: 'default',
        controllerTeacherUserId: 0,
        controllerTeacherName: '',
        activeScheduleId: 0,
        activeScheduleLabel: '',
      ),
    );

    expect(controller.enabled, isFalse);
    expect(controller.requiresTeacherPin, isFalse);
    expect(controller.controllerTeacherUserId, 0);
    expect(bridge.screenAwake, isFalse);
    expect(bridge.studyUiEnabled, isFalse);
  });

  test('auth change away from student clears enforced study mode', () async {
    final bridge = FakeStudyModePlatformBridge(isAndroid: true);
    final service = ScreenLockService(bridge: bridge);
    final controller = StudyModeController(screenLockService: service);
    addTearDown(service.stop);

    final student = _studentUser();
    await controller.syncAuthUser(student);
    await controller.applyHeartbeat(
      student,
      StudentDeviceHeartbeatResponse(
        effectiveEnabled: true,
        effectiveSource: 'manual',
        controllerTeacherUserId: 46,
        controllerTeacherName: 'teacher_c',
        activeScheduleId: 0,
        activeScheduleLabel: '',
      ),
    );

    await controller.syncAuthUser(_teacherUser());

    expect(controller.enabled, isFalse);
    expect(controller.requiresTeacherPin, isFalse);
    expect(bridge.screenAwake, isFalse);
    expect(bridge.studyUiEnabled, isFalse);
  });

  test('same student auth sync clears stale enforced study mode state',
      () async {
    final bridge = FakeStudyModePlatformBridge(isAndroid: true);
    final service = ScreenLockService(bridge: bridge);
    final controller = StudyModeController(screenLockService: service);
    addTearDown(service.stop);

    final student = _studentUser();
    await controller.syncAuthUser(student);
    await controller.applyHeartbeat(
      student,
      StudentDeviceHeartbeatResponse(
        effectiveEnabled: true,
        effectiveSource: 'manual',
        controllerTeacherUserId: 47,
        controllerTeacherName: 'teacher_d',
        activeScheduleId: 0,
        activeScheduleLabel: '',
      ),
    );

    await controller.syncAuthUser(student);

    expect(controller.enabled, isFalse);
    expect(controller.requiresTeacherPin, isFalse);
    expect(bridge.screenAwake, isFalse);
    expect(bridge.studyUiEnabled, isFalse);
  });
}

User _studentUser() {
  return User(
    id: 11,
    username: 'student_a',
    pinHash: 'hash',
    role: 'student',
    teacherId: null,
    remoteUserId: 301,
    createdAt: DateTime.utc(2026, 3, 22),
  );
}

User _teacherUser() {
  return User(
    id: 12,
    username: 'teacher_a',
    pinHash: 'hash',
    role: 'teacher',
    teacherId: null,
    remoteUserId: 401,
    createdAt: DateTime.utc(2026, 3, 22),
  );
}
