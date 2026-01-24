import 'package:flutter/material.dart';

import 'math_markdown_view.dart';

@Deprecated('Use MathMarkdownView instead.')
class HtmlMessageView extends StatelessWidget {
  const HtmlMessageView({
    super.key,
    required this.content,
    required this.textStyle,
    this.cacheKey,
  });

  final String content;
  final TextStyle textStyle;
  final String? cacheKey;

  @override
  Widget build(BuildContext context) {
    return MathMarkdownView(
      content: content,
      textStyle: textStyle,
    );
  }
}
