import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tutor1on1/state/auth_controller.dart';
import 'package:tutor1on1/ui/auth_session_guard.dart';

class _RevokedAuthController extends ChangeNotifier implements AuthController {
  @override
  Future<bool> validateCurrentSession() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('revoked auth blocks the guarded new-session action',
      (tester) async {
    final auth = _RevokedAuthController();
    addTearDown(auth.dispose);
    var startSessionCalls = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    await runWithActiveAuthSession<void>(
                      context,
                      () async {
                        startSessionCalls++;
                      },
                    );
                  },
                  child: const Text('Start session'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Start session'));
    await tester.pump();

    expect(startSessionCalls, 0);
  });
}
