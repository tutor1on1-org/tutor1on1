import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/ui/widgets/math_markdown_view.dart';

void main() {
  testWidgets('renders a GitHub-flavored markdown table as a table',
      (tester) async {
    const markdown = '''
| 情況 | 需要甚麼授權 |
|---|---|
| 賣出證券、就賣出作交收 | 客戶口頭或書面指示都可以 |
| 從帳戶提取客戶證券／證券抵押品 | 必須有書面指示 |
| 處理已登記在客戶名下的證券／抵押品 | 必須有書面指示 |
| 其他預先授權安排 | 常設授權 |
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            child: MathMarkdownView(
              content: markdown,
              textStyle: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('情況'), findsOneWidget);
    expect(find.text('需要甚麼授權'), findsOneWidget);
    expect(find.text('必須有書面指示'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: MathMarkdownView(
              content: markdown,
              textStyle: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DataTable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
