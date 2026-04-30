import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tutor1on1/ui/widgets/action_indicators.dart';

void main() {
  testWidgets('PendingCountBadge shows a red count when positive',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PendingCountBadge(
              count: 3,
              badgeKey: const Key('pending_badge'),
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('Requests'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('pending_badge')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    final text = tester.widget<Text>(find.text('3'));
    expect(text.style?.color, Colors.red);
  });

  testWidgets('AttentionIconButton highlights marketplace action',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              AttentionIconButton(
                icon: Icons.store,
                tooltip: 'Marketplace',
                highlighted: true,
                highlightKey: const Key('marketplace_attention'),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('marketplace_attention')), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.store));
    expect(icon.color, Colors.red);
  });
}
