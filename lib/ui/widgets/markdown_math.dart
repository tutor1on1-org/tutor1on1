import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

enum InlineSegmentType { text, math }

class InlineSegment {
  InlineSegment.text(this.text)
      : type = InlineSegmentType.text,
        display = false,
        raw = text;

  InlineSegment.math({
    required this.text,
    required this.raw,
    required this.display,
  }) : type = InlineSegmentType.math;

  final InlineSegmentType type;
  final String text;
  final String raw;
  final bool display;
}

List<InlineSpan> buildInlineSpans({
  required String content,
  required TextStyle baseStyle,
  required TextStyle codeStyle,
}) {
  final segments = tokenizeInlineSegments(content);
  final spans = <InlineSpan>[];
  for (final segment in segments) {
    if (segment.type == InlineSegmentType.text) {
      spans.addAll(_parseTextSpans(segment.text, baseStyle, codeStyle));
      continue;
    }
    if (segment.text.trim().isEmpty) {
      spans.add(TextSpan(text: segment.raw, style: baseStyle));
      continue;
    }
    if (segment.display) {
      _ensureLineBreak(spans, baseStyle);
      spans.add(_buildMathSpan(segment, baseStyle, MathStyle.display));
      spans.add(TextSpan(text: '\n', style: baseStyle));
    } else {
      spans.add(_buildMathSpan(segment, baseStyle, MathStyle.text));
    }
  }
  return spans;
}

List<InlineSegment> tokenizeInlineSegments(String input) {
  final segments = <InlineSegment>[];
  var index = 0;

  while (index < input.length) {
    final match = _findNextDelimiter(input, index);
    if (match == null) {
      segments.add(InlineSegment.text(input.substring(index)));
      break;
    }

    if (match.start > index) {
      segments.add(InlineSegment.text(input.substring(index, match.start)));
    }

    final end = _findEndDelimiter(
      input,
      match,
      match.start + match.startToken.length,
    );
    if (end == null) {
      segments.add(InlineSegment.text(match.startToken));
      index = match.start + match.startToken.length;
      continue;
    }

    final content =
        input.substring(match.start + match.startToken.length, end);
    final raw = input.substring(match.start, end + match.endToken.length);
    segments.add(
      InlineSegment.math(
        text: content,
        raw: raw,
        display: match.display,
      ),
    );
    index = end + match.endToken.length;
  }

  return segments;
}

InlineSpan _buildMathSpan(
  InlineSegment segment,
  TextStyle baseStyle,
  MathStyle mathStyle,
) {
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: Math.tex(
      segment.text,
      textStyle: baseStyle,
      mathStyle: mathStyle,
      onErrorFallback: (_) => Text(segment.raw, style: baseStyle),
    ),
  );
}

void _ensureLineBreak(List<InlineSpan> spans, TextStyle baseStyle) {
  if (spans.isEmpty) {
    return;
  }
  final last = spans.last;
  if (last is TextSpan) {
    final text = last.text ?? '';
    if (text.endsWith('\n')) {
      return;
    }
  }
  spans.add(TextSpan(text: '\n', style: baseStyle));
}

List<InlineSpan> _parseTextSpans(
  String text,
  TextStyle baseStyle,
  TextStyle codeStyle,
) {
  final spans = <InlineSpan>[];
  var index = 0;

  while (index < text.length) {
    if (text.startsWith('**', index)) {
      final end = text.indexOf('**', index + 2);
      if (end != -1) {
        final inner = text.substring(index + 2, end);
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(fontWeight: FontWeight.w600),
        ));
        index = end + 2;
        continue;
      }
      spans.add(TextSpan(text: '**', style: baseStyle));
      index += 2;
      continue;
    }

    if (text[index] == '`') {
      final end = text.indexOf('`', index + 1);
      if (end != -1) {
        final inner = text.substring(index + 1, end);
        spans.add(TextSpan(text: inner, style: codeStyle));
        index = end + 1;
        continue;
      }
      spans.add(TextSpan(text: '`', style: baseStyle));
      index += 1;
      continue;
    }

    final next = _nextSpecialIndex(text, index);
    if (next == index) {
      spans.add(TextSpan(text: text[index], style: baseStyle));
      index += 1;
      continue;
    }
    spans.add(TextSpan(text: text.substring(index, next), style: baseStyle));
    index = next;
  }

  return spans;
}

int _nextSpecialIndex(String text, int from) {
  final nextBold = text.indexOf('**', from);
  final nextCode = text.indexOf('`', from);
  var next = text.length;
  if (nextBold != -1 && nextBold < next) {
    next = nextBold;
  }
  if (nextCode != -1 && nextCode < next) {
    next = nextCode;
  }
  return next;
}

class _DelimiterMatch {
  _DelimiterMatch({
    required this.start,
    required this.startToken,
    required this.endToken,
    required this.display,
  });

  final int start;
  final String startToken;
  final String endToken;
  final bool display;
}

_DelimiterMatch? _findNextDelimiter(String text, int from) {
  final pattern = RegExp(r'\\\(|\\\[|\$\$|\$');
  final match = pattern.firstMatch(text.substring(from));
  if (match == null) {
    return null;
  }
  final start = from + match.start;
  final token = match.group(0) ?? '';
  if (_isEscaped(text, start)) {
    return _findNextDelimiter(text, start + 1);
  }
  if (token == r'\(') {
    return _DelimiterMatch(
      start: start,
      startToken: r'\(',
      endToken: r'\)',
      display: false,
    );
  }
  if (token == r'\[') {
    return _DelimiterMatch(
      start: start,
      startToken: r'\[',
      endToken: r'\]',
      display: true,
    );
  }
  if (token == r'$$') {
    return _DelimiterMatch(
      start: start,
      startToken: r'$$',
      endToken: r'$$',
      display: true,
    );
  }
  return _DelimiterMatch(
    start: start,
    startToken: r'$',
    endToken: r'$',
    display: false,
  );
}

int? _findEndDelimiter(
  String text,
  _DelimiterMatch match,
  int from,
) {
  if (match.endToken == r'\)' || match.endToken == r'\]') {
    final index = text.indexOf(match.endToken, from);
    return index == -1 ? null : index;
  }
  var index = text.indexOf(match.endToken, from);
  while (index != -1) {
    if (!_isEscaped(text, index)) {
      if (match.endToken == r'$' &&
          index + 1 < text.length &&
          text[index + 1] == r'$') {
        index = text.indexOf(match.endToken, index + 2);
        continue;
      }
      return index;
    }
    index = text.indexOf(match.endToken, index + match.endToken.length);
  }
  return null;
}

bool _isEscaped(String text, int index) {
  if (index == 0) {
    return false;
  }
  return text[index - 1] == '\\';
}
