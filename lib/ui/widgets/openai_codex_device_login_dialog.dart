import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/openai_codex_oauth_service.dart';

typedef OpenAiCodexCopyText = Future<void> Function(String text);

Future<OpenAiCodexOAuthCredentials?> showOpenAiCodexDeviceLoginDialog({
  required BuildContext context,
  required OpenAiCodexOAuthLoginAttempt attempt,
  required Future<void> Function() onOpenChatGpt,
  OpenAiCodexCopyText copyText = _copyTextToClipboard,
}) async {
  final coordinator = _OpenAiCodexDeviceLoginCoordinator(attempt);
  try {
    coordinator.start();
    final result = await showDialog<_OpenAiCodexDeviceLoginDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        coordinator.attach(dialogContext);
        return OpenAiCodexDeviceLoginDialog(
          attempt: attempt,
          onCancel: () => coordinator.cancel(dialogContext),
          onOpenChatGpt: onOpenChatGpt,
          copyText: copyText,
        );
      },
    );
    if (result?.error case final error?) {
      Error.throwWithStackTrace(
        error,
        result?.stackTrace ?? StackTrace.current,
      );
    }
    return result?.credentials;
  } finally {
    await coordinator.finish();
  }
}

class OpenAiCodexDeviceLoginDialog extends StatelessWidget {
  const OpenAiCodexDeviceLoginDialog({
    required this.attempt,
    required this.onCancel,
    required this.onOpenChatGpt,
    required this.copyText,
    super.key,
  });

  final OpenAiCodexOAuthLoginAttempt attempt;
  final VoidCallback onCancel;
  final Future<void> Function() onOpenChatGpt;
  final OpenAiCodexCopyText copyText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ChatGPT OAuth'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open ChatGPT, sign in, and approve this one-time code. '
              'Tutor will finish the login automatically.',
            ),
            const SizedBox(height: 12),
            const Text('One-time code'),
            const SizedBox(height: 4),
            SelectableText(
              attempt.userCode,
              key: const Key('openai-device-user-code'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('openai-device-copy-code'),
                  onPressed: () => unawaited(copyText(attempt.userCode)),
                  child: const Text('Copy code'),
                ),
                OutlinedButton(
                  key: const Key('openai-device-copy-link'),
                  onPressed: () => unawaited(
                    copyText(attempt.authUrl),
                  ),
                  child: const Text('Copy link'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Verification page'),
            const SizedBox(height: 4),
            SelectableText(
              attempt.authUrl,
              key: const Key('openai-device-verification-url'),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Waiting for ChatGPT approval; the code expires within '
                    '15 minutes.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Continue only because you started this login from Tutor.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('openai-device-cancel'),
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('openai-device-open-chatgpt'),
          onPressed: () => unawaited(onOpenChatGpt()),
          child: const Text('Open ChatGPT'),
        ),
      ],
    );
  }
}

class _OpenAiCodexDeviceLoginCoordinator {
  _OpenAiCodexDeviceLoginCoordinator(this.attempt);

  final OpenAiCodexOAuthLoginAttempt attempt;

  BuildContext? _dialogContext;
  ModalRoute<dynamic>? _dialogRoute;
  _OpenAiCodexDeviceLoginDialogResult? _completion;
  Future<void>? _closeFuture;
  var _resolved = false;
  var _started = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    unawaited(
      attempt.waitForCredentials().then<void>(
        (credentials) {
          _completion =
              _OpenAiCodexDeviceLoginDialogResult.success(credentials);
          _popWithCompletionIfReady();
        },
        onError: (Object error, StackTrace stackTrace) {
          _completion = _OpenAiCodexDeviceLoginDialogResult.failure(
            error,
            stackTrace,
          );
          _popWithCompletionIfReady();
        },
      ),
    );
  }

  void attach(BuildContext context) {
    _dialogContext = context;
    _dialogRoute = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _popWithCompletionIfReady();
    });
  }

  void cancel(BuildContext context) {
    if (_resolved) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      return;
    }
    _resolved = true;
    unawaited(_close());
    Navigator.of(context).pop();
  }

  Future<void> finish() async {
    _resolved = true;
    _dialogContext = null;
    _dialogRoute = null;
    await _close();
  }

  Future<void> _close() {
    return _closeFuture ??= attempt.close();
  }

  void _popWithCompletionIfReady() {
    final context = _dialogContext;
    final route = _dialogRoute;
    final completion = _completion;
    if (_resolved || context == null || route == null || completion == null) {
      return;
    }
    if (!context.mounted || !route.isCurrent) {
      return;
    }
    _resolved = true;
    Navigator.of(context).pop(completion);
  }
}

class _OpenAiCodexDeviceLoginDialogResult {
  const _OpenAiCodexDeviceLoginDialogResult.success(this.credentials)
      : error = null,
        stackTrace = null;

  const _OpenAiCodexDeviceLoginDialogResult.failure(
    this.error,
    this.stackTrace,
  ) : credentials = null;

  final OpenAiCodexOAuthCredentials? credentials;
  final Object? error;
  final StackTrace? stackTrace;
}

Future<void> _copyTextToClipboard(String text) {
  return Clipboard.setData(ClipboardData(text: text));
}
