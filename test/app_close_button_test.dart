import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutor1on1/ui/app_close_button.dart';

class _BootstrapLoadingShell extends StatelessWidget {
  const _BootstrapLoadingShell();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: buildAppBarActionsWithClose(context),
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
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
