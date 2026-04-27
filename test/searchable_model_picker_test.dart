import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/ui/widgets/searchable_model_picker.dart';

void main() {
  testWidgets('filters and selects models from the search dialog',
      (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableModelPicker(
            label: 'Text model',
            options: const <String>[
              'deepseek-ai/DeepSeek-V3.2',
              'deepseek-ai/DeepSeek-V4-Flash',
              'Qwen/Qwen3-32B',
            ],
            value: 'deepseek-ai/DeepSeek-V3.2',
            emptyMessage: 'No models',
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('deepseek-ai/DeepSeek-V3.2'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'V4');
    await tester.pumpAndSettle();

    expect(find.text('deepseek-ai/DeepSeek-V4-Flash'), findsOneWidget);
    expect(find.text('Qwen/Qwen3-32B'), findsNothing);

    await tester.tap(find.text('deepseek-ai/DeepSeek-V4-Flash'));
    await tester.pumpAndSettle();

    expect(selected, equals('deepseek-ai/DeepSeek-V4-Flash'));
  });
}
