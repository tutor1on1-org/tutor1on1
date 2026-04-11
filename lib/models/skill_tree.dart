class SkillTreeParseResult {
  SkillTreeParseResult({
    required this.root,
    required this.nodes,
    required this.unparsedLines,
  });

  final SkillNode root;
  final Map<String, SkillNode> nodes;
  final List<String> unparsedLines;
}

enum SkillNodeType { branch, leaf }

class SkillNode {
  SkillNode({
    required this.id,
    required this.title,
    required this.type,
    required this.rawLine,
    this.grade,
    this.yearStart,
    this.yearEnd,
    this.parentId,
    this.isPlaceholder = false,
  });

  final String id;
  String title;
  final SkillNodeType type;
  final String rawLine;
  final String? grade;
  final int? yearStart;
  final int? yearEnd;
  String? parentId;
  final bool isPlaceholder;
  final List<SkillNode> children = [];
}

int compareSkillNodeIds(String left, String right) {
  final leftParts = left.split('.');
  final rightParts = right.split('.');
  var index = 0;
  while (index < leftParts.length && index < rightParts.length) {
    final leftNumber = int.tryParse(leftParts[index]);
    final rightNumber = int.tryParse(rightParts[index]);
    final partCompare = leftNumber != null && rightNumber != null
        ? leftNumber.compareTo(rightNumber)
        : leftParts[index].compareTo(rightParts[index]);
    if (partCompare != 0) {
      return partCompare;
    }
    index += 1;
  }
  final lengthCompare = leftParts.length.compareTo(rightParts.length);
  if (lengthCompare != 0) {
    return lengthCompare;
  }
  return left.compareTo(right);
}

class SkillTreeParser {
  SkillTreeParseResult parse(String content) {
    final lines = content.split(RegExp(r'\r\n|\n|\r'));
    if (lines.isNotEmpty && lines.first.startsWith('\uFEFF')) {
      lines[0] = lines.first.substring(1);
    }
    final nodes = <String, SkillNode>{};
    final unparsed = <String>[];
    final idPattern = RegExp(r'^(\d+(?:\.\d+)*)\s*(.+)$');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final match = idPattern.firstMatch(trimmed);
      if (match == null) {
        unparsed.add(trimmed);
        continue;
      }
      final id = match.group(1)!;
      var rest = match.group(2)!.trim();
      if (rest.startsWith('.')) {
        rest = rest.substring(1).trimLeft();
      }
      final isLeaf = _startsWithParen(rest);
      final grade = _extractGrade(trimmed);
      final yearRange = _extractYearRange(trimmed);
      final title =
          isLeaf ? _extractLeafTitle(rest) : _extractBranchTitle(rest, grade);
      nodes[id] = SkillNode(
        id: id,
        title: title.isEmpty ? rest : title,
        type: isLeaf ? SkillNodeType.leaf : SkillNodeType.branch,
        rawLine: trimmed,
        grade: grade,
        yearStart: yearRange?.$1,
        yearEnd: yearRange?.$2,
      );
    }

    final root = SkillNode(
      id: 'math',
      title: 'math',
      type: SkillNodeType.branch,
      rawLine: '',
    );

    SkillNode ensureNode(String id) {
      final existing = nodes[id];
      if (existing != null) {
        return existing;
      }
      final placeholder = SkillNode(
        id: id,
        title: id,
        type: SkillNodeType.branch,
        rawLine: '',
        isPlaceholder: true,
      );
      nodes[id] = placeholder;
      return placeholder;
    }

    for (final node in nodes.values.toList()) {
      final parentId = _parentId(node.id);
      node.parentId = parentId;
      if (parentId == null) {
        root.children.add(node);
      } else {
        final parent = ensureNode(parentId);
        parent.children.add(node);
      }
    }
    _sortChildren(root);

    return SkillTreeParseResult(
      root: root,
      nodes: nodes,
      unparsedLines: unparsed,
    );
  }

  void _sortChildren(SkillNode node) {
    node.children.sort(
      (left, right) => compareSkillNodeIds(left.id, right.id),
    );
    for (final child in node.children) {
      _sortChildren(child);
    }
  }

  String? _parentId(String id) {
    final index = id.lastIndexOf('.');
    if (index == -1) {
      return null;
    }
    return id.substring(0, index);
  }

  String? _extractGrade(String line) {
    final match = RegExp(r'Y\d+(?:-\d+)?').firstMatch(line);
    return match?.group(0);
  }

  (int, int)? _extractYearRange(String line) {
    final match = RegExp(r'Y(\d+)(?:-(\d+))?').firstMatch(line);
    if (match == null) {
      return null;
    }
    final start = int.tryParse(match.group(1)!);
    if (start == null) {
      return null;
    }
    final endRaw = match.group(2);
    final end = endRaw == null ? start : int.tryParse(endRaw) ?? start;
    return (start, end);
  }

  String _extractBranchTitle(String rest, String? grade) {
    var title = rest.trim();
    title = title.replaceAll(
      RegExp(r'[:\uFF1A]\s*Y\d+(?:-\d+)?\s*$'),
      '',
    );
    title = title.replaceAll(
      RegExp(r'[\(\uFF08]\s*Y\d+(?:-\d+)?\s*[\)\uFF09]\s*$'),
      '',
    );
    title = title.trim();
    if (title.isEmpty && grade != null) {
      return rest.replaceAll(grade, '').trim();
    }
    return title;
  }

  String _extractLeafTitle(String rest) {
    var inner = rest.trim();
    if (_startsWithParen(inner)) {
      inner = inner.substring(1);
    }
    if (inner.endsWith(')') || inner.endsWith('\uFF09')) {
      inner = inner.substring(0, inner.length - 1);
    }
    final parts = inner.split(RegExp(r'[,\uFF0C]'));
    final first = parts.isNotEmpty ? parts.first.trim() : inner.trim();
    return first.isEmpty ? inner.trim() : first;
  }

  bool _startsWithParen(String text) {
    return text.startsWith('(') || text.startsWith('\uFF08');
  }
}
