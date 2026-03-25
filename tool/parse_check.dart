import 'dart:io';
import 'package:tutor1on1/models/skill_tree.dart';

void main() {
  final file = File('assets/teachers/dennis/MATH/contents.txt');
  final content = file.readAsStringSync();
  final parser = SkillTreeParser();
  final result = parser.parse(content);
  print('lines=${content.split(RegExp(r"\r?\n")).where((l) => l.trim().isNotEmpty).length}');
  print('nodes=${result.nodes.length}, rootChildren=${result.root.children.length}');
  var leafCount = 0;
  var branchCount = 0;
  for (final node in result.nodes.values) {
    if (node.type == SkillNodeType.leaf) {
      leafCount++;
    } else {
      branchCount++;
    }
  }
  print('branches=$branchCount, leaves=$leafCount');
}
