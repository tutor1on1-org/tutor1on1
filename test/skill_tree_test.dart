import 'package:flutter_test/flutter_test.dart';

import 'package:tutor1on1/models/skill_tree.dart';

void main() {
  test('parser orders dotted numeric node ids naturally', () {
    final result = SkillTreeParser().parse('''
1 Unit
1.1 (First, Y1)
1.10 (Tenth, Y1)
1.11 (Eleventh, Y1)
1.2 (Second, Y1)
''');

    expect(
      result.root.children.map((node) => node.id),
      <String>['1'],
    );
    expect(
      result.nodes['1']!.children.map((node) => node.id),
      <String>['1.1', '1.2', '1.10', '1.11'],
    );
  });

  test('compareSkillNodeIds keeps parents before descendants', () {
    final ids = <String>['1.10', '1.1.1', '1.2', '1', '1.1'];

    ids.sort(compareSkillNodeIds);

    expect(ids, <String>['1', '1.1', '1.1.1', '1.2', '1.10']);
  });
}
