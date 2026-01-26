import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

class TtsTextSanitizer {
  String sanitize(String input) => sanitizeForTts(input);

  String sanitizeForTts(String input) {
    if (input.trim().isEmpty) {
      return '';
    }
    final protected = _protectSegments(input);
    final plainText = _markdownToPlainText(protected.text);
    final restoredMath = _restoreMathSegments(
      plainText,
      protected.mathSegments,
    );
    final restored = _restoreCodeSegments(
      restoredMath,
      protected.codeSegments,
    );
    return _normalizeWhitespace(restored);
  }

  _ProtectedText _protectSegments(String input) {
    final buffer = StringBuffer();
    final mathSegments = <String>[];
    final codeSegments = <String>[];
    var index = 0;

    while (index < input.length) {
      if (!_isEscaped(input, index) && _matchesAt(input, index, '```')) {
        final end = _findClosingToken(input, index + 3, '```');
        if (end != -1) {
          final content = input.substring(index + 3, end);
          final placeholder = '@@C${codeSegments.length}@@';
          codeSegments.add(content);
          buffer.write(placeholder);
          index = end + 3;
          continue;
        }
        buffer.write('```');
        index += 3;
        continue;
      }

      if (!_isEscaped(input, index) && _matchesAt(input, index, '`')) {
        final end = _findClosingToken(input, index + 1, '`');
        if (end != -1) {
          final content = input.substring(index + 1, end);
          final placeholder = '@@C${codeSegments.length}@@';
          codeSegments.add(content);
          buffer.write(placeholder);
          index = end + 1;
          continue;
        }
        buffer.write('`');
        index += 1;
        continue;
      }

      if (!_isEscaped(input, index) && _matchesAt(input, index, r'$$')) {
        final end = _findClosingToken(input, index + 2, r'$$');
        if (end != -1) {
          final content = input.substring(index + 2, end);
          final placeholder = '@@M${mathSegments.length}@@';
          mathSegments.add(content);
          buffer.write(placeholder);
          index = end + 2;
          continue;
        }
        buffer.write(r'$$');
        index += 2;
        continue;
      }

      if (!_isEscaped(input, index) && _matchesAt(input, index, r'\[')) {
        final end = _findClosingToken(input, index + 2, r'\]',
            respectEscape: true);
        if (end != -1) {
          final content = input.substring(index + 2, end);
          final placeholder = '@@M${mathSegments.length}@@';
          mathSegments.add(content);
          buffer.write(placeholder);
          index = end + 2;
          continue;
        }
        buffer.write(r'\[');
        index += 2;
        continue;
      }

      if (!_isEscaped(input, index) && _matchesAt(input, index, r'\(')) {
        final end = _findClosingToken(input, index + 2, r'\)',
            respectEscape: true);
        if (end != -1) {
          final content = input.substring(index + 2, end);
          final placeholder = '@@M${mathSegments.length}@@';
          mathSegments.add(content);
          buffer.write(placeholder);
          index = end + 2;
          continue;
        }
        buffer.write(r'\(');
        index += 2;
        continue;
      }

      if (_matchesAt(input, index, r'$') && !_isEscaped(input, index)) {
        if (_matchesAt(input, index, r'$$')) {
          buffer.write(r'$');
          index += 1;
          continue;
        }
        final lineEnd = _lineEnd(input, index);
        final end = _findInlineDollarEnd(input, index + 1, lineEnd);
        if (end != -1) {
          final content = input.substring(index + 1, end);
          if (_shouldTreatInlineMath(content)) {
            final placeholder = '@@M${mathSegments.length}@@';
            mathSegments.add(content);
            buffer.write(placeholder);
            index = end + 1;
            continue;
          }
        }
        buffer.write(r'$');
        index += 1;
        continue;
      }

      buffer.write(input[index]);
      index += 1;
    }

    return _ProtectedText(
      text: buffer.toString(),
      mathSegments: mathSegments,
      codeSegments: codeSegments,
    );
  }

  String _markdownToPlainText(String input) {
    final doc = md.Document(
      encodeHtml: false,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    final lines = const LineSplitter().convert(input.replaceAll('\r', ''));
    final nodes = doc.parseLines(lines);
    final renderer = _MarkdownPlainTextRenderer();
    for (final node in nodes) {
      renderer.render(node);
    }
    return renderer.toString();
  }

  String _restoreMathSegments(String input, List<String> mathSegments) {
    if (mathSegments.isEmpty) {
      return input;
    }
    final buffer = StringBuffer();
    var cursor = 0;
    final regex = RegExp(r'@@M(\d+)@@');
    for (final match in regex.allMatches(input)) {
      buffer.write(input.substring(cursor, match.start));
      final rawIndex = int.tryParse(match.group(1) ?? '');
      if (rawIndex == null || rawIndex < 0 || rawIndex >= mathSegments.length) {
        buffer.write(match.group(0));
      } else {
        buffer.write(_sanitizeMath(mathSegments[rawIndex]));
      }
      cursor = match.end;
    }
    buffer.write(input.substring(cursor));
    return buffer.toString();
  }

  String _restoreCodeSegments(String input, List<String> codeSegments) {
    if (codeSegments.isEmpty) {
      return input;
    }
    final buffer = StringBuffer();
    var cursor = 0;
    final regex = RegExp(r'@@C(\d+)@@');
    for (final match in regex.allMatches(input)) {
      buffer.write(input.substring(cursor, match.start));
      final rawIndex = int.tryParse(match.group(1) ?? '');
      if (rawIndex == null ||
          rawIndex < 0 ||
          rawIndex >= codeSegments.length) {
        buffer.write(match.group(0));
      } else {
        buffer.write(codeSegments[rawIndex]);
      }
      cursor = match.end;
    }
    buffer.write(input.substring(cursor));
    return buffer.toString();
  }

  String _sanitizeMath(String input) {
    var text = input;
    text = text.replaceAll(RegExp(r'\\left|\\right'), '');
    text = _replaceFraction(text);
    text = _replaceRoot(text);
    text = _replacePowers(text);
    text = _replaceCommands(text);
    text = text.replaceAll('{', ' ').replaceAll('}', ' ');
    text = text.replaceAll('\\', ' ');
    return _normalizeWhitespace(text);
  }

  String _replaceFraction(String input) {
    var text = input;
    var index = text.indexOf(r'\frac');
    while (index != -1) {
      final first = _extractBraceContent(text, index + 5);
      if (first == null) {
        index = text.indexOf(r'\frac', index + 5);
        continue;
      }
      final second = _extractBraceContent(text, first.endIndex);
      if (second == null) {
        index = text.indexOf(r'\frac', index + 5);
        continue;
      }
      final replacement = '${first.content} over ${second.content}';
      text = text.replaceRange(index, second.endIndex, replacement);
      index = text.indexOf(r'\frac', index + replacement.length);
    }
    return text;
  }

  String _replaceRoot(String input) {
    var text = input;
    var index = text.indexOf(r'\sqrt');
    while (index != -1) {
      final content = _extractBraceContent(text, index + 5);
      if (content == null) {
        index = text.indexOf(r'\sqrt', index + 5);
        continue;
      }
      final replacement = 'square root of ${content.content}';
      text = text.replaceRange(index, content.endIndex, replacement);
      index = text.indexOf(r'\sqrt', index + replacement.length);
    }
    return text;
  }

  String _replacePowers(String input) {
    var text = input;
    text = text.replaceAllMapped(RegExp(r'\^2'), (_) => ' squared');
    text = text.replaceAllMapped(RegExp(r'\^3'), (_) => ' cubed');
    text = text.replaceAllMapped(RegExp(r'\^\{([^{}]+)\}'), (match) {
      final power = match.group(1) ?? '';
      return ' to the power of $power';
    });
    text = text.replaceAllMapped(RegExp(r'\^([0-9]+)'), (match) {
      final power = match.group(1) ?? '';
      return ' to the power of $power';
    });
    return text;
  }

  String _replaceCommands(String input) {
    var text = input;
    final replacements = <String, String>{
      r'\cdot': ' times ',
      r'\times': ' times ',
      r'\div': ' divided by ',
      r'\pm': ' plus or minus ',
      r'\mp': ' minus or plus ',
      r'\le': ' less than or equal to ',
      r'\ge': ' greater than or equal to ',
      r'\neq': ' not equal to ',
      r'\approx': ' approximately ',
      r'\infty': ' infinity ',
      r'\cup': ' union ',
      r'\cap': ' intersection ',
      r'\in': ' in ',
      r'\notin': ' not in ',
      r'\subset': ' subset of ',
      r'\supset': ' superset of ',
      r'\subseteq': ' subset or equal to ',
      r'\supseteq': ' superset or equal to ',
      r'\to': ' approaches ',
      r'\rightarrow': ' approaches ',
      r'\Rightarrow': ' implies ',
      r'\mathbb{R}': ' real numbers ',
      r'\mathbb{Z}': ' integers ',
      r'\mathbb{Q}': ' rationals ',
      r'\mathbb{N}': ' natural numbers ',
      r'\mathbb{C}': ' complex numbers ',
      r'\pi': ' pi ',
      r'\theta': ' theta ',
      r'\alpha': ' alpha ',
      r'\beta': ' beta ',
      r'\gamma': ' gamma ',
      r'\delta': ' delta ',
      r'\lambda': ' lambda ',
      r'\mu': ' mu ',
      r'\sigma': ' sigma ',
    };
    replacements.forEach((key, value) {
      text = text.replaceAll(key, value);
    });
    text = text.replaceAll('<', ' less than ');
    text = text.replaceAll('>', ' greater than ');
    text = text.replaceAll(RegExp(r'\\[a-zA-Z]+'), ' ');
    return text;
  }

  String _normalizeWhitespace(String input) {
    return input
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _matchesAt(String input, int index, String token) {
    if (index < 0 || index + token.length > input.length) {
      return false;
    }
    return input.startsWith(token, index);
  }

  int _lineEnd(String input, int index) {
    final end = input.indexOf('\n', index);
    return end == -1 ? input.length : end;
  }

  int _findClosingToken(
    String input,
    int from,
    String token, {
    bool respectEscape = false,
  }) {
    var index = from;
    while (index < input.length) {
      final found = input.indexOf(token, index);
      if (found == -1) {
        return -1;
      }
      if (respectEscape && _isEscaped(input, found)) {
        index = found + token.length;
        continue;
      }
      return found;
    }
    return -1;
  }

  int _findInlineDollarEnd(String input, int from, int lineEnd) {
    var index = from;
    while (index < lineEnd) {
      final found = input.indexOf(r'$', index);
      if (found == -1 || found >= lineEnd) {
        return -1;
      }
      if (_isEscaped(input, found)) {
        index = found + 1;
        continue;
      }
      return found;
    }
    return -1;
  }

  bool _shouldTreatInlineMath(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed.contains('\n')) {
      return false;
    }
    final hasSpace = RegExp(r'\s').hasMatch(trimmed);
    final hasCommand = trimmed.contains('\\');
    final hasOperator = RegExp(r'[=<>^+\-*/]').hasMatch(trimmed);
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(trimmed);
    final hasDigit = RegExp(r'\d').hasMatch(trimmed);
    if (hasSpace && !(hasCommand || hasOperator)) {
      return false;
    }
    if (hasCommand || hasOperator) {
      return true;
    }
    if (hasLetter && !hasSpace) {
      return true;
    }
    if (hasDigit && !hasSpace) {
      return true;
    }
    return false;
  }

  bool _isEscaped(String input, int index) {
    var backslashes = 0;
    var i = index - 1;
    while (i >= 0 && input[i] == '\\') {
      backslashes += 1;
      i -= 1;
    }
    return backslashes.isOdd;
  }

  _BraceContent? _extractBraceContent(String input, int startIndex) {
    var index = startIndex;
    while (index < input.length && input[index].trim().isEmpty) {
      index += 1;
    }
    if (index >= input.length || input[index] != '{') {
      return null;
    }
    index += 1;
    final contentStart = index;
    var depth = 0;
    while (index < input.length) {
      final char = input[index];
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        if (depth == 0) {
          final content = input.substring(contentStart, index);
          return _BraceContent(content: content, endIndex: index + 1);
        }
        depth -= 1;
      }
      index += 1;
    }
    return null;
  }
}

class _ProtectedText {
  _ProtectedText({
    required this.text,
    required this.mathSegments,
    required this.codeSegments,
  });

  final String text;
  final List<String> mathSegments;
  final List<String> codeSegments;
}

class _BraceContent {
  _BraceContent({
    required this.content,
    required this.endIndex,
  });

  final String content;
  final int endIndex;
}

class _MarkdownPlainTextRenderer {
  final StringBuffer _buffer = StringBuffer();
  bool _endsWithNewline = false;

  void render(md.Node node) {
    if (node is md.Text) {
      _write(node.text);
      return;
    }
    if (node is md.Element) {
      switch (node.tag) {
        case 'p':
        case 'blockquote':
        case 'h1':
        case 'h2':
        case 'h3':
        case 'h4':
        case 'h5':
        case 'h6':
          _renderChildren(node);
          _writeNewline();
          return;
        case 'br':
          _writeNewline();
          return;
        case 'ul':
        case 'ol':
          _renderChildren(node);
          _writeNewline();
          return;
        case 'li':
          _write('- ');
          _renderChildren(node);
          _writeNewline();
          return;
        case 'code':
          _write(node.textContent);
          return;
        case 'pre':
          _write(node.textContent);
          _writeNewline();
          return;
        case 'a':
          final text = node.textContent;
          if (text.isNotEmpty) {
            _write(text);
          } else {
            final href = node.attributes['href'] ?? '';
            _write(href);
          }
          return;
        case 'img':
          final alt = node.attributes['alt'] ?? '';
          if (alt.isNotEmpty) {
            _write(alt);
          }
          return;
        default:
          _renderChildren(node);
          return;
      }
    }
  }

  void _renderChildren(md.Element node) {
    final children = node.children;
    if (children == null) {
      return;
    }
    for (final child in children) {
      render(child);
    }
  }

  void _write(String text) {
    if (text.isEmpty) {
      return;
    }
    _buffer.write(text);
    _endsWithNewline = text.endsWith('\n');
  }

  void _writeNewline() {
    if (_endsWithNewline) {
      return;
    }
    _buffer.write('\n');
    _endsWithNewline = true;
  }

  @override
  String toString() => _buffer.toString();
}
