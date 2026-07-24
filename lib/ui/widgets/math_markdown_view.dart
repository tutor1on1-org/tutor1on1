import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

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
  late List<_MarkdownBlock> _blocks;
  late Map<_MarkdownBlock, List<InlineSpan>> _textSpans;

  @override
  void initState() {
    super.initState();
    _blocks = _buildBlocks(widget.content);
  }

  @override
  void didUpdateWidget(MathMarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.textStyle != widget.textStyle) {
      _blocks = _buildBlocks(widget.content);
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_blocks.length == 1 && _blocks.single.table == null) {
      return _buildText(_blocks.single);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in _blocks)
          if (block.table != null)
            _buildTable(context, block.table!)
          else if (block.text.isNotEmpty)
            _buildText(block),
      ],
    );
  }

  Widget _buildText(_MarkdownBlock block) {
    return SelectableText.rich(
      TextSpan(
        style: widget.textStyle,
        children: _textSpans[block],
      ),
    );
  }

  Widget _buildTable(BuildContext context, _MarkdownTable table) {
    final borderColor = Theme.of(context).dividerColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          border: TableBorder.all(color: borderColor),
          horizontalMargin: 12,
          columnSpacing: 20,
          dataRowMinHeight: 40,
          dataRowMaxHeight: double.infinity,
          columns: [
            for (final cell in table.headers)
              DataColumn(
                label: _buildTableCell(
                  cell,
                  widget.textStyle.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
          ],
          rows: [
            for (final row in table.rows)
              DataRow(
                cells: [
                  for (final cell in row)
                    DataCell(_buildTableCell(cell, widget.textStyle)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCell(_MarkdownTableCell cell, TextStyle style) {
    final alignment = switch (cell.alignment) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: SelectableText.rich(
        TextSpan(
          style: style,
          children: buildInlineSpans(
            content: cell.text,
            baseStyle: style,
            codeStyle: _codeStyle(style),
          ),
        ),
        textAlign: alignment,
      ),
    );
  }

  List<_MarkdownBlock> _buildBlocks(String content) {
    final blocks = _parseMarkdownBlocks(content);
    _textSpans = <_MarkdownBlock, List<InlineSpan>>{
      for (final block in blocks)
        if (block.table == null) block: _buildSpans(block.text),
    };
    return blocks;
  }

  List<InlineSpan> _buildSpans(String content) {
    return buildInlineSpans(
      content: content,
      baseStyle: widget.textStyle,
      codeStyle: _codeStyle(widget.textStyle),
    );
  }

  TextStyle _codeStyle(TextStyle style) {
    return style.copyWith(
      fontFamily: 'Cascadia Mono',
      fontFamilyFallback: const ['Consolas', 'Courier New', 'monospace'],
      fontSize: (style.fontSize ?? 14) - 1,
    );
  }
}

List<_MarkdownBlock> _parseMarkdownBlocks(String content) {
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final blocks = <_MarkdownBlock>[];
  var textStart = 0;
  var index = 0;
  while (index + 1 < lines.length) {
    if (!lines[index].contains('|')) {
      index++;
      continue;
    }
    final headerOnly = _parseMarkdownTable(lines.sublist(index, index + 2));
    if (headerOnly == null) {
      index++;
      continue;
    }
    var tableEnd = index + 2;
    while (tableEnd < lines.length &&
        lines[tableEnd].trim().isNotEmpty &&
        lines[tableEnd].contains('|')) {
      tableEnd++;
    }
    final table = _parseMarkdownTable(lines.sublist(index, tableEnd));
    if (table == null) {
      index++;
      continue;
    }
    if (textStart < index) {
      blocks.add(
        _MarkdownBlock.text(lines.sublist(textStart, index).join('\n')),
      );
    }
    blocks.add(_MarkdownBlock.table(table));
    textStart = tableEnd;
    index = tableEnd;
  }
  if (textStart < lines.length) {
    blocks.add(_MarkdownBlock.text(lines.sublist(textStart).join('\n')));
  }
  if (blocks.isEmpty) {
    blocks.add(_MarkdownBlock.text(normalized));
  }
  return blocks;
}

_MarkdownTable? _parseMarkdownTable(List<String> lines) {
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parseLines(lines);
  if (nodes.length != 1 ||
      nodes.single is! md.Element ||
      (nodes.single as md.Element).tag != 'table') {
    return null;
  }
  final table = nodes.single as md.Element;
  final head = _childElement(table, 'thead');
  final headerRow = head == null ? null : _childElement(head, 'tr');
  if (headerRow == null) {
    return null;
  }
  final headers = _parseTableRow(headerRow);
  if (headers.isEmpty) {
    return null;
  }
  final rows = <List<_MarkdownTableCell>>[];
  final body = _childElement(table, 'tbody');
  for (final node in body?.children ?? const <md.Node>[]) {
    if (node is md.Element && node.tag == 'tr') {
      rows.add(_parseTableRow(node));
    }
  }
  return _MarkdownTable(headers: headers, rows: rows);
}

md.Element? _childElement(md.Element parent, String tag) {
  for (final child in parent.children ?? const <md.Node>[]) {
    if (child is md.Element && child.tag == tag) {
      return child;
    }
  }
  return null;
}

List<_MarkdownTableCell> _parseTableRow(md.Element row) {
  return [
    for (final node in row.children ?? const <md.Node>[])
      if (node is md.Element && (node.tag == 'th' || node.tag == 'td'))
        _MarkdownTableCell(
          text: node.textContent.trim(),
          alignment: node.attributes['align'],
        ),
  ];
}

class _MarkdownBlock {
  const _MarkdownBlock.text(this.text) : table = null;

  const _MarkdownBlock.table(this.table) : text = '';

  final String text;
  final _MarkdownTable? table;
}

class _MarkdownTable {
  const _MarkdownTable({
    required this.headers,
    required this.rows,
  });

  final List<_MarkdownTableCell> headers;
  final List<List<_MarkdownTableCell>> rows;
}

class _MarkdownTableCell {
  const _MarkdownTableCell({
    required this.text,
    required this.alignment,
  });

  final String text;
  final String? alignment;
}
