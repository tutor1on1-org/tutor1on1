class TtsTextSanitizer {
  String sanitize(String input) {
    if (input.trim().isEmpty) {
      return '';
    }
    var text = _stripCodeBlocks(input);
    final segments = _tokenizeMathSegments(text);
    final buffer = StringBuffer();
    for (final segment in segments) {
      if (segment.isMath) {
        buffer.write(_sanitizeMath(segment.text));
      } else {
        buffer.write(_stripMarkdown(segment.text));
      }
    }
    return _normalizeWhitespace(buffer.toString());
  }

  String _stripCodeBlocks(String input) {
    return input.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  }

  String _stripMarkdown(String input) {
    var text = input;
    text = text.replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1');
    text = text.replaceAll(RegExp(r'\*(.+?)\*'), r'$1');
    text = text.replaceAll(RegExp(r'__(.+?)__'), r'$1');
    text = text.replaceAll(RegExp(r'_(.+?)_'), r'$1');
    text = text.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    text = text.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '');
    return text;
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
    final pattern = RegExp(r'\\frac\s*{([^{}]+)}\s*{([^{}]+)}');
    while (pattern.hasMatch(text)) {
      text = text.replaceAllMapped(pattern, (match) {
        final numerator = match.group(1) ?? '';
        final denominator = match.group(2) ?? '';
        return '$numerator over $denominator';
      });
    }
    return text;
  }

  String _replaceRoot(String input) {
    var text = input;
    final pattern = RegExp(r'\\sqrt\s*{([^{}]+)}');
    while (pattern.hasMatch(text)) {
      text = text.replaceAllMapped(pattern, (match) {
        final inner = match.group(1) ?? '';
        return 'square root of $inner';
      });
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
    text = text.replaceAll(RegExp(r'\\[a-zA-Z]+'), ' ');
    return text;
  }

  String _normalizeWhitespace(String input) {
    return input
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(' .', '.')
        .replaceAll(' ,', ',')
        .trim();
  }
}

class _MathSegment {
  _MathSegment({
    required this.text,
    required this.isMath,
  });

  final String text;
  final bool isMath;
}

List<_MathSegment> _tokenizeMathSegments(String input) {
  final segments = <_MathSegment>[];
  var index = 0;
  while (index < input.length) {
    final match = _findNextDelimiter(input, index);
    if (match == null) {
      segments.add(_MathSegment(text: input.substring(index), isMath: false));
      break;
    }
    if (match.start > index) {
      segments.add(
        _MathSegment(
          text: input.substring(index, match.start),
          isMath: false,
        ),
      );
    }
    final end = _findEndDelimiter(
      input,
      match,
      match.start + match.startToken.length,
    );
    if (end == null) {
      segments.add(
        _MathSegment(text: match.startToken, isMath: false),
      );
      index = match.start + match.startToken.length;
      continue;
    }
    final content =
        input.substring(match.start + match.startToken.length, end);
    segments.add(_MathSegment(text: content, isMath: true));
    index = end + match.endToken.length;
  }
  return segments;
}

class _DelimiterMatch {
  _DelimiterMatch({
    required this.start,
    required this.startToken,
    required this.endToken,
  });

  final int start;
  final String startToken;
  final String endToken;
}

_DelimiterMatch? _findNextDelimiter(String input, int start) {
  final candidates = <_DelimiterMatch>[];
  final dollar = input.indexOf(r'$', start);
  if (dollar != -1) {
    final isDouble = dollar + 1 < input.length && input[dollar + 1] == r'$';
    candidates.add(
      _DelimiterMatch(
        start: dollar,
        startToken: isDouble ? r'$$' : r'$',
        endToken: isDouble ? r'$$' : r'$',
      ),
    );
  }
  final inline = input.indexOf(r'\(', start);
  if (inline != -1) {
    candidates.add(
      _DelimiterMatch(start: inline, startToken: r'\(', endToken: r'\)'),
    );
  }
  final display = input.indexOf(r'\[', start);
  if (display != -1) {
    candidates.add(
      _DelimiterMatch(start: display, startToken: r'\[', endToken: r'\]'),
    );
  }
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort((a, b) => a.start.compareTo(b.start));
  return candidates.first;
}

int? _findEndDelimiter(String input, _DelimiterMatch match, int from) {
  final end = input.indexOf(match.endToken, from);
  return end == -1 ? null : end;
}
