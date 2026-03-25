import 'dart:io';

import 'package:drift/native.dart';
import 'package:tutor1on1/app.dart';
import 'package:tutor1on1/db/app_database.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:tutor1on1/security/pin_hasher.dart';
import 'package:tutor1on1/services/app_services.dart';
import 'package:tutor1on1/services/log_crypto_service.dart';
import 'package:tutor1on1/services/secure_storage_service.dart';
import 'package:tutor1on1/state/auth_controller.dart';
import 'package:tutor1on1/state/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._db, SecureStorageService secureStorage)
      : super(_db, secureStorage);

  final AppDatabase _db;
  User? _fakeCurrentUser;
  String? _fakeLastError;

  @override
  User? get currentUser => _fakeCurrentUser;

  @override
  String? get lastError => _fakeLastError;

  @override
  Future<bool> login(String username, String password) async {
    _fakeLastError = null;
    final normalizedUsername = _normalizeUsername(username);
    final user = await _db.findUserByUsername(normalizedUsername);
    if (user == null || user.pinHash != PinHasher.hash(password)) {
      _fakeLastError = 'Invalid username or password.';
      return false;
    }
    _fakeCurrentUser = user;
    await LogCryptoService.instance.activate(
      userId: user.id,
      role: user.role,
      password: password,
    );
    notifyListeners();
    return true;
  }

  @override
  Future<User?> registerTeacher({
    required String username,
    required String email,
    required String password,
    required String displayName,
    String? bio,
    String? avatarUrl,
    String? contact,
    required bool contactPublished,
    List<int> subjectLabelIds = const <int>[],
  }) async {
    return _register(
      username: username,
      password: password,
      role: 'teacher',
    );
  }

  @override
  Future<User?> registerStudent({
    required String username,
    required String email,
    required String password,
  }) async {
    return _register(
      username: username,
      password: password,
      role: 'student',
    );
  }

  @override
  Future<void> logout() async {
    LogCryptoService.instance.clear();
    _fakeCurrentUser = null;
    _fakeLastError = null;
    notifyListeners();
  }

  @override
  Future<void> refreshCurrentUser() async {
    final current = _fakeCurrentUser;
    if (current == null) {
      return;
    }
    _fakeCurrentUser = await _db.getUserById(current.id);
    notifyListeners();
  }

  Future<User?> _register({
    required String username,
    required String password,
    required String role,
  }) async {
    _fakeLastError = null;
    final normalizedUsername = _normalizeUsername(username);
    final existing = await _db.findUserByUsername(normalizedUsername);
    if (existing != null) {
      _fakeLastError = 'Username already exists.';
      return null;
    }
    final userId = await _db.createUser(
      username: normalizedUsername,
      pinHash: PinHasher.hash(password),
      role: role,
      teacherId: null,
      remoteUserId: null,
    );
    _fakeCurrentUser = await _db.getUserById(userId);
    if (_fakeCurrentUser != null) {
      await LogCryptoService.instance.activate(
        userId: _fakeCurrentUser!.id,
        role: _fakeCurrentUser!.role,
        password: password,
      );
    }
    notifyListeners();
    return _fakeCurrentUser;
  }

  String _normalizeUsername(String username) {
    return username.trim().toLowerCase();
  }
}

Widget _buildTestApp({
  required AppServices services,
  required AuthController authController,
  required SettingsController settingsController,
}) {
  return MultiProvider(
    providers: [
      Provider<AppServices>.value(value: services),
      Provider<AppDatabase>.value(value: services.db),
      ChangeNotifierProvider<AuthController>.value(value: authController),
      ChangeNotifierProvider<SettingsController>.value(
        value: settingsController,
      ),
    ],
    child: Consumer<SettingsController>(
      builder: (context, controller, _) {
        final settings = controller.settings;
        Locale? locale;
        final localeCode = settings?.locale?.trim();
        if (localeCode != null && localeCode.isNotEmpty) {
          locale = Locale(localeCode);
        }
        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const AuthGate(),
        );
      },
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  late Directory tempDir;
  late AppDatabase db;
  late AppServices services;
  late _FakeAuthController authController;
  late SettingsController settingsController;

  setUp(() async {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tempDir = await Directory.systemTemp.createTemp('app_flow_test_');
    messenger.setMockMethodCallHandler(_pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getTemporaryDirectory':
          return tempDir.path;
      }
      return null;
    });

    db = AppDatabase.forTesting(NativeDatabase.memory());
    services = await AppServices.create(databaseOverride: db);
    await services.settingsRepository.updateLocale('en');
    settingsController = SettingsController(services.settingsRepository);
    authController = _FakeAuthController(db, services.secureStorage);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(_pathProviderChannel, null);
    settingsController.dispose();
    authController.dispose();
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('teacher register, logout, and login flow', (tester) async {
    await tester.pumpWidget(
      _buildTestApp(
        services: services,
        authController: authController,
        settingsController: settingsController,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_username')), findsOneWidget);

    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('register_teacher_username')),
      'teacher_flow',
    );
    await tester.enterText(
      find.byKey(const Key('register_teacher_password')),
      'pass1234',
    );
    await tester.enterText(
      find.byKey(const Key('register_teacher_recovery_email')),
      'teacher@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register_teacher_display_name')),
      'Teacher Flow',
    );
    await tester.tap(find.byKey(const Key('register_teacher_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('create_course_button')), findsOneWidget);
    expect(find.byKey(const Key('enrollment_requests_button')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_username')), findsOneWidget);
    expect(find.byKey(const Key('create_course_button')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('login_username')),
      'teacher_flow',
    );
    await tester.enterText(
      find.byKey(const Key('login_password')),
      'pass1234',
    );
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('create_course_button')), findsOneWidget);
    expect(find.byKey(const Key('prompt_settings_button')), findsOneWidget);
  });
}
