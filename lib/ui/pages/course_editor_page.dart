import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:provider/provider.dart';

import '../../db/app_database.dart';
import '../../models/skill_tree.dart';
import '../app_close_button.dart';
import '../widgets/pan_scroll_view.dart';
import 'course_builder_conversation_page.dart';

class CourseEditorPage extends StatefulWidget {
  const CourseEditorPage({
    super.key,
    required this.courseVersionId,
  });

  final int courseVersionId;

  @override
  State<CourseEditorPage> createState() => _CourseEditorPageState();
}

class _CourseEditorPageState extends State<CourseEditorPage> {
  final TextEditingController _searchController = TextEditingController();
  late final BuchheimWalkerConfiguration _graphConfig;
  late final BuchheimWalkerAlgorithm _graphAlgorithm;
  final Map<Node, SkillNode> _graphNodeData = {};
  CourseVersion? _courseVersion;
  SkillTreeParseResult? _parseResult;
  Graph? _graph;
  String? _selectedId;
  String _searchQuery = '';
  int _levelLimit = 2;
  int _maxDepth = 1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _graphConfig = BuchheimWalkerConfiguration()
      ..siblingSeparation = 30
      ..levelSeparation = 60
      ..subtreeSeparation = 30
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_TOP_BOTTOM;
    _graphAlgorithm =
        BuchheimWalkerAlgorithm(_graphConfig, TreeEdgeRenderer(_graphConfig));
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = context.read<AppDatabase>();
    final course = await db.getCourseVersionById(widget.courseVersionId);
    if (course == null) {
      setState(() {
        _error = 'Course not found.';
        _loading = false;
      });
      return;
    }
    try {
      final parser = SkillTreeParser();
      final result = parser.parse(course.textbookText);
      final subject = course.subject.trim();
      if (subject.isNotEmpty) {
        result.root.title = subject;
      }
      final maxDepth = _calculateMaxDepth(result);
      final levelLimit = math.min(maxDepth, 2);
      setState(() {
        _courseVersion = course;
        _parseResult = result;
        _maxDepth = maxDepth;
        _levelLimit = levelLimit <= 0 ? 1 : levelLimit;
        _graph = _buildGraph();
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = 'Failed to parse course tree: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(actions: buildAppBarActionsWithClose(context)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final result = _parseResult;
    final course = _courseVersion;
    if (_error != null || result == null || course == null) {
      return Scaffold(
        appBar: AppBar(actions: buildAppBarActionsWithClose(context)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(_error ?? 'Course tree is empty.'),
        ),
      );
    }

    final selectedNode = _selectedId == null
        ? null
        : (result.nodes[_selectedId!] ??
            (_selectedId == result.root.id ? result.root : null));
    final listNodes = selectedNode == null
        ? result.root.children
        : _detailNodesForSelection(selectedNode);
    final matches = _searchQuery.isEmpty
        ? <SkillNode>[]
        : result.nodes.values
            .where((node) => !node.isPlaceholder)
            .where(
              (node) =>
                  node.id.contains(_searchQuery) ||
                  _nodeDisplayText(node)
                      .toLowerCase()
                      .contains(_searchQuery.toLowerCase()),
            )
            .toList()
      ..sort((a, b) => compareSkillNodeIds(a.id, b.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Course Editor - ${course.subject}'),
        actions: buildAppBarActionsWithClose(context),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search KP',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<int>(
                    initialValue: _levelLimit,
                    decoration: const InputDecoration(
                      labelText: 'Tree depth',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      _maxDepth,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text('${index + 1}'),
                      ),
                    ),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _levelLimit = value;
                        _graph = _buildGraph();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: matches.isEmpty
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No matching KP.'),
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: matches.take(12).map((node) {
                          return ActionChip(
                            label: Text(node.id),
                            onPressed: () => _selectNode(node),
                          );
                        }).toList(),
                      ),
                    ),
            ),
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: PanScrollView(
              padding: const EdgeInsets.all(180),
              child: GraphView(
                graph: _graph ?? (Graph()..isTree = true),
                algorithm: _graphAlgorithm,
                animated: false,
                builder: (node) {
                  final data = _graphNodeData[node];
                  if (data == null) {
                    return const SizedBox.shrink();
                  }
                  return _buildTreeNode(data);
                },
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 2,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: listNodes.length,
              itemBuilder: (context, index) {
                final node = listNodes[index];
                return _buildListNode(node);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeNode(SkillNode node) {
    final selected = node.id == _selectedId;
    final size = node.id == 'math'
        ? 30.0
        : math.max(8.0, 30.0 - ((_nodeDepth(node) - 1) * 5));
    return GestureDetector(
      onTap: () => _selectNode(node),
      onSecondaryTapDown: (details) => _showNodeMenu(
        node,
        details.globalPosition,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? Colors.orange : Colors.blueGrey.shade200,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? Colors.deepOrange : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildListNode(SkillNode node) {
    final selected = node.id == _selectedId;
    return GestureDetector(
      onSecondaryTapDown: (details) => _showNodeMenu(
        node,
        details.globalPosition,
      ),
      child: ListTile(
        selected: selected,
        selectedTileColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
        leading: SizedBox(
          width: 72,
          child: Text(
            node.id == _parseResult?.root.id ? '' : node.id,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        title: Text(_nodeDisplayText(node)),
        onTap: () => _selectNode(node),
        trailing: IconButton(
          key: Key('course_editor_node_menu_${node.id}'),
          tooltip: 'Menu',
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showNodeMenuAtCenter(node),
        ),
      ),
    );
  }

  Future<void> _showNodeMenuAtCenter(SkillNode node) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final center = overlay.size.center(Offset.zero);
    await _showNodeMenu(node, center);
  }

  Future<void> _showNodeMenu(SkillNode node, Offset position) async {
    if (node.id == _parseResult?.root.id || node.isPlaceholder) {
      return;
    }
    _selectNode(node);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'ai_edit_content',
          child: Text('AI edit content'),
        ),
        PopupMenuItem(
          enabled: false,
          child: Text('Edit title'),
        ),
        PopupMenuItem(
          enabled: false,
          child: Text('Add sub'),
        ),
        PopupMenuItem(
          enabled: false,
          child: Text('Add sibling'),
        ),
        PopupMenuItem(
          enabled: false,
          child: Text('Hide'),
        ),
      ],
    );
    if (choice == 'ai_edit_content') {
      await _openAiEditor(node);
    }
  }

  Future<void> _openAiEditor(SkillNode node) async {
    final course = _courseVersion;
    if (course == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseBuilderConversationPage(
          courseVersion: course,
          kpKey: node.id,
          kpTitle: _nodeDisplayText(node),
        ),
      ),
    );
  }

  void _selectNode(SkillNode node) {
    setState(() {
      _selectedId = node.id;
      _graph = _buildGraph();
    });
  }

  Graph _buildGraph() {
    final result = _parseResult;
    final graph = Graph()..isTree = true;
    if (result == null) {
      return graph;
    }
    final nodes = <String, Node>{};
    _graphNodeData.clear();

    Node graphNode(SkillNode node) {
      return nodes.putIfAbsent(node.id, () {
        final graphNode = Node.Id(node.id);
        _graphNodeData[graphNode] = node;
        return graphNode;
      });
    }

    void walk(SkillNode parent) {
      final parentNode = graphNode(parent);
      if (!graph.nodes.contains(parentNode)) {
        graph.addNode(parentNode);
      }
      for (final child in parent.children) {
        if (_nodeDepth(child) > _levelLimit) {
          continue;
        }
        final childNode = graphNode(child);
        if (!graph.nodes.contains(childNode)) {
          graph.addNode(childNode);
        }
        graph.addEdge(parentNode, childNode);
        walk(child);
      }
    }

    walk(result.root);
    return graph;
  }

  List<SkillNode> _detailNodesForSelection(SkillNode node) {
    final result = <SkillNode>[..._pathToNode(node)];
    final parent = node.parentId == null ? node : _nodeById(node.parentId!);
    if (parent != null) {
      for (final sibling in parent.children) {
        if (!result.contains(sibling)) {
          result.add(sibling);
        }
      }
    }
    if (node.children.isNotEmpty) {
      for (final child in node.children) {
        if (!result.contains(child)) {
          result.add(child);
        }
      }
    }
    result.sort((a, b) => compareSkillNodeIds(a.id, b.id));
    return result;
  }

  List<SkillNode> _pathToNode(SkillNode node) {
    final result = <SkillNode>[];
    final parseResult = _parseResult;
    if (parseResult == null) {
      return result;
    }
    var current = node;
    final visited = <String>{};
    while (true) {
      result.add(current);
      final parentId = current.parentId;
      if (parentId == null || visited.contains(parentId)) {
        break;
      }
      visited.add(parentId);
      final parent = parseResult.nodes[parentId];
      if (parent == null) {
        break;
      }
      current = parent;
    }
    final ordered = result.reversed.toList();
    if (ordered.isEmpty || ordered.first.id != parseResult.root.id) {
      ordered.insert(0, parseResult.root);
    }
    return ordered;
  }

  SkillNode? _nodeById(String id) {
    if (id == _parseResult?.root.id) {
      return _parseResult?.root;
    }
    return _parseResult?.nodes[id];
  }

  String _nodeDisplayText(SkillNode node) {
    final raw = node.rawLine.trim();
    if (raw.isEmpty) {
      return node.title.isNotEmpty ? node.title : node.id;
    }
    final cleaned = raw.replaceFirst(
      RegExp('^${RegExp.escape(node.id)}\\s*'),
      '',
    );
    return cleaned.trim().isEmpty ? node.title : cleaned.trim();
  }

  int _nodeDepth(SkillNode node) {
    if (node.id == 'math') {
      return 0;
    }
    return node.id.split('.').length;
  }

  int _calculateMaxDepth(SkillTreeParseResult result) {
    var maxDepth = 1;
    for (final node in result.nodes.values) {
      final depth = _nodeDepth(node);
      if (depth > maxDepth) {
        maxDepth = depth;
      }
    }
    return maxDepth;
  }
}
