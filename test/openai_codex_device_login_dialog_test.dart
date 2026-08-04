import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/services/openai_codex_oauth_service.dart';
import 'package:tutor1on1/ui/widgets/openai_codex_device_login_dialog.dart';

void main() {
  testWidgets('Cancel resolves null and closes the attempt exactly once',
      (tester) async {
    final attempt = _AttemptHarness();
    OpenAiCodexOAuthCredentials? result;
    await _openDialogHost(
      tester,
      attempt: attempt,
      onResult: (value) => result = value,
    );

    await tester.tap(find.byKey(const Key('openai-device-cancel')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(attempt.waitCalls, equals(1));
    expect(attempt.closeCalls, equals(1));
    expect(find.text('OAuth host route'), findsOneWidget);
  });

  testWidgets('late polling completion cannot pop the underlying route',
      (tester) async {
    final attempt = _AttemptHarness();
    var resultCount = 0;
    await _openDialogHost(
      tester,
      attempt: attempt,
      onResult: (_) => resultCount += 1,
    );

    await tester.tap(find.byKey(const Key('openai-device-cancel')));
    attempt.complete(_credentials);
    await tester.pumpAndSettle();

    expect(resultCount, equals(1));
    expect(find.text('OAuth host route'), findsOneWidget);
    expect(find.text('Open OAuth host'), findsNothing);
    expect(attempt.closeCalls, equals(1));
  });

  testWidgets('successful polling completion closes only the dialog route',
      (tester) async {
    final attempt = _AttemptHarness();
    OpenAiCodexOAuthCredentials? result;
    await _openDialogHost(
      tester,
      attempt: attempt,
      onResult: (value) => result = value,
    );

    attempt.complete(_credentials);
    await tester.pumpAndSettle();

    expect(result, same(_credentials));
    expect(find.text('OAuth host route'), findsOneWidget);
    expect(find.text('Open OAuth host'), findsNothing);
    expect(find.byType(OpenAiCodexDeviceLoginDialog), findsNothing);
    expect(attempt.waitCalls, equals(1));
    expect(attempt.closeCalls, equals(1));
  });

  testWidgets('Open ChatGPT and copy actions use explicit user taps',
      (tester) async {
    final attempt = _AttemptHarness();
    var openCalls = 0;
    final copied = <String>[];
    await _openDialogHost(
      tester,
      attempt: attempt,
      onOpenChatGpt: () async {
        openCalls += 1;
      },
      copyText: (value) async {
        copied.add(value);
      },
    );

    expect(
      find.text(_attemptAuthUrl),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('openai-device-copy-code')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('openai-device-copy-link')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('openai-device-open-chatgpt')));
    await tester.pump();

    expect(
        copied,
        equals(<String>[
          'ABCD-EFGH',
          _attemptAuthUrl,
        ]));
    expect(openCalls, equals(1));

    await tester.tap(find.byKey(const Key('openai-device-cancel')));
    await tester.pumpAndSettle();
  });
}

const _credentials = OpenAiCodexOAuthCredentials(
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  expiresAtMs: 4102444800000,
  accountId: 'acct_123',
);

const _attemptAuthUrl = 'https://auth.openai.com/codex/device';

class _AttemptHarness {
  _AttemptHarness() {
    attempt = OpenAiCodexOAuthLoginAttempt(
      authUrl: _attemptAuthUrl,
      userCode: 'ABCD-EFGH',
      expiresAt: DateTime.utc(2026, 8, 4, 1, 15),
      waitForCredentials: () {
        waitCalls += 1;
        return _completion.future;
      },
      close: () async {
        closeCalls += 1;
      },
    );
  }

  final Completer<OpenAiCodexOAuthCredentials> _completion =
      Completer<OpenAiCodexOAuthCredentials>();
  late final OpenAiCodexOAuthLoginAttempt attempt;
  var waitCalls = 0;
  var closeCalls = 0;

  void complete(OpenAiCodexOAuthCredentials credentials) {
    _completion.complete(credentials);
  }
}

Future<void> _openDialogHost(
  WidgetTester tester, {
  required _AttemptHarness attempt,
  void Function(OpenAiCodexOAuthCredentials?)? onResult,
  Future<void> Function()? onOpenChatGpt,
  OpenAiCodexCopyText? copyText,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => _DialogHostRoute(
                      attempt: attempt.attempt,
                      onResult: onResult,
                      onOpenChatGpt: onOpenChatGpt,
                      copyText: copyText,
                    ),
                  ),
                );
              },
              child: const Text('Open OAuth host'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open OAuth host'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start OAuth'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _DialogHostRoute extends StatelessWidget {
  const _DialogHostRoute({
    required this.attempt,
    this.onResult,
    this.onOpenChatGpt,
    this.copyText,
  });

  final OpenAiCodexOAuthLoginAttempt attempt;
  final void Function(OpenAiCodexOAuthCredentials?)? onResult;
  final Future<void> Function()? onOpenChatGpt;
  final OpenAiCodexCopyText? copyText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OAuth host route')),
      body: ElevatedButton(
        onPressed: () async {
          final result = await showOpenAiCodexDeviceLoginDialog(
            context: context,
            attempt: attempt,
            onOpenChatGpt: onOpenChatGpt ?? () async {},
            copyText: copyText ?? (_) async {},
          );
          onResult?.call(result);
        },
        child: const Text('Start OAuth'),
      ),
    );
  }
}
