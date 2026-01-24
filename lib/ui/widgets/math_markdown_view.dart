import 'package:flutter/material.dart';

import 'markdown_math.dart';

class MathMarkdownView extends StatefulWidget {
  const MathMarkdownView({
    super.key,
    required this.content,
    required this.textStyle,
  });

  final String content;
  final TextStyle textStyle;

  @override
  State<MathMarkdownView> createState() => _MathMarkdownViewState();
}

class _MathMarkdownViewState extends State<MathMarkdownView>
    with AutomaticKeepAliveClientMixin {
  late List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _spans = _buildSpans(widget.content);
  }

  @override
  void didUpdateWidget(MathMarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _spans = _buildSpans(widget.content);
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SelectableText.rich(
      TextSpan(
        style: widget.textStyle,
        children: _spans,
      ),
    );
  }

  List<InlineSpan> _buildSpans(String content) {
    return buildInlineSpans(
      content: content,
      baseStyle: widget.textStyle,
      codeStyle: widget.textStyle.copyWith(
        fontFamily: 'Cascadia Mono',
        fontFamilyFallback: const ['Consolas', 'Courier New', 'monospace'],
        fontSize: (widget.textStyle.fontSize ?? 14) - 1,
      ),
    );
  }
}
