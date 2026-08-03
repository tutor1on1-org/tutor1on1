import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutor1on1/ui/app_close_button.dart';

class _BootstrapLoadingShell extends StatelessWidget {
  const _BootstrapLoadingShell({this.closeEnabled = true});

  final bool closeEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: buildAppBarActionsWithClose(
            context,
            closeEnabled: closeEnabled,
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

void main() {
  testWidgets(
    'builds startup loading shell before localizations are mounted',
    (tester) async {
      await tester.pumpWidget(const _BootstrapLoadingShell());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('does not add a native close control in Chrome', (tester) async {
    await tester.pumpWidget(const _BootstrapLoadingShell(closeEnabled: false));

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });
}
