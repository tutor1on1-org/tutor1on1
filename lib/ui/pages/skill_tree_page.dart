import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';
import 'package:graphview/GraphView.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../db/app_database.dart';
import '../../models/skill_tree.dart';
import '../progress_display.dart';
import '../../services/app_services.dart';
import '../../state/auth_controller.dart';
import '../app_close_button.dart';
import '../tutor_session_page.dart';
import '../widgets/pan_scroll_view.dart';

class SkillTreePage extends StatefulWidget {
  const SkillTreePage({
    super.key,
    required this.courseVersionId,
    required this.isTeacherView,
    this.teacherStudentId,
  });

  final int courseVersionId;
  final bool isTeacherView;
  final int? teacherStudentId;

  @override
  State<SkillTreePage> createState() => _SkillTreePageState();
}

class _SkillTreePageState extends State<SkillTreePage> {
  static const int _newSessionChoice = -1;

  final TextEditingController _searchController = TextEditingController();
  late final BuchheimWalkerConfiguration _graphConfig;
  late final BuchheimWalkerAlgorithm _graphAlgorithm;
  late final AppDatabase _db;
  Timer? _saveDebounce;
  final int _baseSiblingSeparation = 30;
  final int _baseLevelSeparation = 60;
  final int _baseSubtreeSeparation = 30;
  final Map<Node, SkillNode> _graphNodeData = {};
  SkillTreeParseResult? _parseResult;
  String? _rawContent;
  String? _error;
  bool _loading = true;
  bool _showRaw = false;
  String _searchQuery = '';
  String? _selectedId;
  final Set<String> _expanded = {'math'};
  int _levelLimit = 2;
  int _maxDepth = 1;
  int? _minYear;
  int? _maxYear;
  int? _yearFilter;
  Graph? _graph;
  int _graphRevision = 0;
  bool _restoringState = false;
  bool _persistViewState = false;
  int? _currentUserId;
  final Map<String, double> _nodeProgress = {};
  int? _teacherStudentId;
  final Map<String, Set<String>> _collapsedDescendants = {};

  @override
  void initState() {
    super.initState();
    _db = context.read<AppDatabase>();
    final auth = context.read<AuthController>();
    final currentUser = auth.currentUser;
    _currentUserId = currentUser?.id;
    _persistViewState = currentUser != null;
    _graphConfig = BuchheimWalkerConfiguration()
      ..siblingSeparation = _baseSiblingSeparation
      ..levelSeparation = _baseLevelSeparation
      ..subtreeSeparation = _baseSubtreeSeparation
      ..orientation = BuchheimWalkerConfiguration.ORIENTATION_TOP_BOTTOM;
    _graphAlgorithm =
        BuchheimWalkerAlgorithm(_graphConfig, TreeEdgeRenderer(_graphConfig));
    _loadTree();
    if (widget.isTeacherView) {
      _loadTeacherAssignment();
    }
    _searchController.addListener(() {
      final query = _searchController.text.trim();
      if (_restoringState) {
        _searchQuery = query;
        return;
      }
      setState(() => _searchQuery = query);
      _scheduleViewStateSave();
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _saveViewState();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_currentUserId == null) {
      final auth = context.read<AuthController>();
      final currentUser = auth.currentUser;
      _currentUserId = currentUser?.id;
      _persistViewState = currentUser != null;
    }
  }

  Future<void> _loadTeacherAssignment() async {
    final auth = context.read<AuthController>();
    final currentUser = auth.currentUser;
    if (widget.teacherStudentId != null) {
      if (currentUser != null && currentUser.role == 'teacher') {
        final services = context.read<AppServices>();
        await services.sessionSyncService.materializeTeacherArtifactsForView(
          currentUser: currentUser,
          localStudentId: widget.teacherStudentId!,
          courseVersionId: widget.courseVersionId,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _teacherStudentId = widget.teacherStudentId;
      });
      return;
    }
    final assignments =
        await _db.getAssignmentsForCourse(widget.courseVersionId);
    final selectedStudentId =
        assignments.isNotEmpty ? assignments.first.studentId : null;
    if (selectedStudentId != null &&
        currentUser != null &&
        currentUser.role == 'teacher') {
      final services = context.read<AppServices>();
      await services.sessionSyncService.materializeTeacherArtifactsForView(
        currentUser: currentUser,
        localStudentId: selectedStudentId,
        courseVersionId: widget.courseVersionId,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _teacherStudentId = selectedStudentId;
    });
  }

  Future<void> _loadTree() async {
    final course = await _db.getCourseVersionById(widget.courseVersionId);
    if (course == null) {
      setState(() {
        _error = 'Course not found.';
        _loading = false;
      });
      return;
    }
    if (course.sourcePath == null || course.sourcePath!.trim().isEmpty) {
      setState(() {
        _error = 'Course not loaded. Load the folder first.';
        _loading = false;
      });
      return;
    }
    final content = course.textbookText;

    try {
      final parser = SkillTreeParser();
      final result = parser.parse(content);
      final subject = course.subject.trim();
      if (subject.isNotEmpty) {
        result.root.title = subject;
      }
      final maxDepth = _calculateMaxDepth(result);
      final yearRange = _calculateYearRange(result);
      var levelLimit = maxDepth < 2 ? maxDepth : 2;
      var yearFilter = null as int?;
      var showRaw = false;
      var searchQuery = '';
      String? selectedId;
      var expanded = _expandedForLevel(levelLimit);
      final viewState = await _loadViewState();
      if (viewState != null) {
        final savedLevel = _readInt(viewState['levelLimit']);
        if (savedLevel != null) {
          levelLimit = savedLevel;
        }
        final savedYear = _readInt(viewState['yearFilter']);
        if (savedYear != null) {
          yearFilter = savedYear;
        }
        final savedExpanded = _readStringList(viewState['expanded']);
        if (savedExpanded.isNotEmpty) {
          expanded = savedExpanded.toSet();
        }
        final savedSelected = viewState['selectedId'];
        if (savedSelected is String && savedSelected.trim().isNotEmpty) {
          selectedId = savedSelected.trim();
        }
        final savedSearch = viewState['searchQuery'];
        if (savedSearch is String) {
          searchQuery = savedSearch;
        }
        final savedShowRaw = viewState['showRaw'];
        if (savedShowRaw is bool) {
          showRaw = savedShowRaw;
        }
      }

      if (levelLimit < 1) {
        levelLimit = 1;
      } else if (levelLimit > maxDepth) {
        levelLimit = maxDepth;
      }
      if (yearRange == null ||
          yearFilter == null ||
          yearFilter < yearRange.$1 ||
          yearFilter > yearRange.$2) {
        yearFilter = null;
      }

      final validIds = <String>{'math', ...result.nodes.keys};
      expanded = expanded.where(validIds.contains).toSet();
      expanded.add('math');
      if (selectedId != null && !validIds.contains(selectedId)) {
        selectedId = null;
      }

      _restoringState = true;
      _searchController.text = searchQuery;
      setState(() {
        _rawContent = content;
        _parseResult = result;
        _maxDepth = maxDepth;
        _levelLimit = levelLimit;
        _minYear = yearRange?.$1;
        _maxYear = yearRange?.$2;
        _yearFilter = yearFilter;
        _showRaw = showRaw;
        _searchQuery = searchQuery;
        _selectedId = selectedId;
        _expanded
          ..clear()
          ..addAll(expanded);
        _graph = _buildGraphForLevel(_levelLimit);
        _graphRevision++;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _restoringState = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to parse contents.txt: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthController>();
    final currentUser = auth.currentUser;
    final isStudent = currentUser?.role == 'student';
    final isTeacher = currentUser?.role == 'teacher';
    final db = context.read<AppDatabase>();
    final targetStudentId = isStudent ? currentUser?.id : _teacherStudentId;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.skillTreeTitle),
          actions: buildAppBarActionsWithClose(context),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_parseResult == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.skillTreeTitle),
          actions: buildAppBarActionsWithClose(context),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(_error ?? l10n.noNodesYet),
        ),
      );
    }
    if (_parseResult!.nodes.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.skillTreeTitle),
          actions: buildAppBarActionsWithClose(context),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(_rawContent ?? l10n.noNodesYet),
        ),
      );
    }

    final nodes = _parseResult!.nodes;
    final matches = _searchQuery.isEmpty
        ? <SkillNode>[]
        : nodes.values
            .where((node) => !node.isPlaceholder)
            .where(
              (node) =>
                  node.id.contains(_searchQuery) ||
                  node.title.toLowerCase().contains(_searchQuery.toLowerCase()),
            )
            .toList()
      ..sort((a, b) => compareSkillNodeIds(a.id, b.id));

    final selectedNode = _selectedId == null
        ? null
        : (nodes[_selectedId!] ??
            (_selectedId == 'math' ? _parseResult!.root : null));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.skillTreeTitle),
        actions: buildAppBarActionsWithClose(context),
      ),
      body: StreamBuilder<List<ProgressEntry>>(
        stream: targetStudentId == null
            ? const Stream.empty()
            : db.watchProgressForCourse(
                targetStudentId, widget.courseVersionId),
        builder: (context, snapshot) {
          final progress = snapshot.data ?? [];
          final litPercentMap = {
            for (final entry in progress)
              entry.kpKey: _resolveLitPercent(entry),
          };
          final litMap = {
            for (final entry in progress) entry.kpKey: entry.lit,
          };
          _nodeProgress
            ..clear()
            ..addAll(_calculateNodeProgress(_parseResult!.root, litPercentMap));
          final graph = _graph ?? (Graph()..isTree = true);

          return LayoutBuilder(
            builder: (context, constraints) {
              final bottomItems = <Widget>[];
              if (_parseResult!.unparsedLines.isNotEmpty) {
                bottomItems.add(
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.unparsedLinesLabel(
                              _parseResult!.unparsedLines.length,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _showRaw = !_showRaw);
                            _scheduleViewStateSave();
                          },
                          child: Text(
                            _showRaw ? l10n.hideRawButton : l10n.showRawButton,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                if (_showRaw) {
                  bottomItems.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        height: 120,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _parseResult!.unparsedLines.join('\n'),
                          ),
                        ),
                      ),
                    ),
                  );
                }
              }

              if (selectedNode != null) {
                bottomItems.add(
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                          _detailNodesForSelection(selectedNode).map((node) {
                        final text = _nodeDisplayText(node);
                        final isActive = node.id == _selectedId;
                        final studentId = targetStudentId;
                        final showTeacherControls = widget.isTeacherView &&
                            isActive &&
                            studentId != null;
                        final isLit = _isNodeFullyLit(node, litMap);
                        final background = _nodeColor(node.id, isLit: isLit);
                        final idLabel =
                            node.id == _parseResult!.root.id ? '' : node.id;
                        return InkWell(
                          onTap: () => _handleNodeTap(
                            node,
                            isStudent,
                            isTeacher,
                            db,
                            currentUser?.id,
                            targetStudentId,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: background,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isActive
                                      ? Colors.orange
                                      : Colors.transparent,
                                  width: isActive ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      idLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(text),
                                  ),
                                  if (showTeacherControls)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: isLit
                                                ? Colors.green
                                                : Colors.grey,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            minimumSize: const Size(0, 32),
                                          ),
                                          onPressed: () => _toggleNodeLit(
                                            node: node,
                                            litMap: litMap,
                                            db: db,
                                            studentId: studentId,
                                            includeAll: !_isLeafNode(node),
                                          ),
                                          child: const Text('lit'),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            minimumSize: const Size(0, 32),
                                          ),
                                          onPressed: () => _toggleNodeLit(
                                            node: node,
                                            litMap: litMap,
                                            db: db,
                                            studentId: studentId,
                                            includeAll: true,
                                          ),
                                          child: const Text('all'),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              }

              final showBottom = bottomItems.isNotEmpty;
              final maxBottomHeight =
                  math.min(260.0, constraints.maxHeight * 0.35);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: l10n.searchNodeLabel,
                        hintText: l10n.searchNodeHint,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<int>(
                            initialValue: _levelLimit,
                            decoration: InputDecoration(
                              labelText: l10n.levelFilterLabel,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
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
                                _expanded
                                  ..clear()
                                  ..addAll(_expandedForLevel(value));
                                _graph = _buildGraphForLevel(_levelLimit);
                                _graphRevision++;
                              });
                              _scheduleViewStateSave();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<int?>(
                            initialValue: _yearFilter,
                            decoration: InputDecoration(
                              labelText: l10n.yearFilterLabel,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: [
                              DropdownMenuItem<int?>(
                                value: null,
                                child: Text(l10n.yearFilterAll),
                              ),
                              ..._yearOptions().map(
                                (year) => DropdownMenuItem<int?>(
                                  value: year,
                                  child: Text('Y$year'),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _yearFilter = value;
                                _graph = _buildGraphForLevel(_levelLimit);
                                _graphRevision++;
                              });
                              _scheduleViewStateSave();
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
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Text(l10n.noSearchResults),
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: matches
                                  .take(12)
                                  .map(
                                    (node) => ActionChip(
                                      label: Text(node.id),
                                      onPressed: () => _selectNode(node),
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: PanScrollView(
                      padding: const EdgeInsets.all(200),
                      child: GraphView(
                        key: ValueKey('graph_${_graphRevision}'),
                        graph: graph,
                        algorithm: _graphAlgorithm,
                        animated: false,
                        builder: (Node node) {
                          final data = _graphNodeData[node];
                          if (data == null) {
                            return const SizedBox.shrink();
                          }
                          return _buildNodeWidget(data, litPercentMap, litMap);
                        },
                      ),
                    ),
                  ),
                  if (showBottom)
                    SizedBox(
                      height: maxBottomHeight,
                      child: PanScrollView(
                        horizontal: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: bottomItems,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Graph _buildGraphForLevel(int levelLimit) {
    final graph = Graph()..isTree = true;
    final nodes = <String, Node>{};
    _graphNodeData.clear();

    Node graphNode(SkillNode node) {
      return nodes.putIfAbsent(
        node.id,
        () {
          final graphNode = Node.Id(node.id);
          _graphNodeData[graphNode] = node;
          return graphNode;
        },
      );
    }

    void walk(SkillNode parent) {
      final parentNode = graphNode(parent);
      if (!graph.nodes.contains(parentNode)) {
        graph.addNode(parentNode);
      }
      for (final child in parent.children) {
        if (!_isNodeVisible(child)) {
          continue;
        }
        if (!graph.nodes.contains(graphNode(child))) {
          graph.addNode(graphNode(child));
        }
        graph.addEdge(parentNode, graphNode(child));
        if (child.children.isNotEmpty) {
          walk(child);
        }
      }
    }

    walk(_parseResult!.root);
    return graph;
  }

  SkillNode? _nodeById(String id) {
    if (id == 'math') {
      return _parseResult?.root;
    }
    return _parseResult?.nodes[id];
  }

  Widget _buildNodeWidget(
    SkillNode node,
    Map<String, int> litPercentMap,
    Map<String, bool> litMap,
  ) {
    final isSelected = _selectedId == node.id;
    final size = _nodeSizeFor(node);
    final isLit = _isNodeFullyLit(node, litMap);
    final baseColor = _nodeColor(node.id, isLit: isLit);
    final content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? Colors.orange : Colors.transparent,
          width: 2,
        ),
      ),
    );
    return GestureDetector(
      onTap: () => _selectNode(node),
      child: content,
    );
  }

  Future<void> _handleNodeTap(
    SkillNode node,
    bool isStudent,
    bool isTeacher,
    AppDatabase db,
    int? userId,
    int? targetStudentId,
  ) async {
    _selectNode(node);
    if (!isStudent && !isTeacher) {
      return;
    }
    final studentId = isStudent ? userId : targetStudentId;
    if (studentId == null) {
      if (isTeacher) {
        await _showLeafError(
          AppLocalizations.of(context)!.noAssignedStudentMessage,
        );
      }
      return;
    }
    final courseVersion = await db.getCourseVersionById(widget.courseVersionId);
    final courseNode = await db.getCourseNodeByKey(
      widget.courseVersionId,
      node.id,
    );
    if (!mounted) {
      return;
    }
    if (courseVersion == null || courseNode == null) {
      await _showLeafError(
        'Unable to open session for ${node.id}. Course data is missing.',
      );
      return;
    }
    final sessions = await db.getSessionsForNode(
      studentId: studentId,
      courseVersionId: widget.courseVersionId,
      kpKey: node.id,
    );
    if (!mounted) {
      return;
    }
    int? selectedId;
    if (sessions.isEmpty) {
      if (isTeacher) {
        await _showLeafError(
          AppLocalizations.of(context)!.noSessionsYet,
        );
        return;
      }
      selectedId = _newSessionChoice;
    } else {
      selectedId = await _showSessionPicker(
        sessions,
        allowNew: isStudent,
      );
    }
    if (selectedId == null) {
      return;
    }
    final sessionId = selectedId == _newSessionChoice
        ? await context.read<AppServices>().sessionService.startSession(
              studentId: studentId,
              courseVersionId: widget.courseVersionId,
              kpKey: node.id,
            )
        : selectedId;
    if (!mounted) {
      return;
    }
    await _openSession(
      sessionId: sessionId,
      courseVersion: courseVersion,
      node: courseNode,
      readOnly: isTeacher,
    );
  }

  void _selectNode(SkillNode node) {
    setState(() {
      _selectedId = node.id;
      _expandToNode(node.id);
      _toggleNodeExpansion(node);
      _graph = _buildGraphForLevel(_levelLimit);
      _graphRevision++;
    });
    _scheduleViewStateSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {}
    });
  }

  void _expandToNode(String id) {
    var current = id;
    while (true) {
      final node = _nodeById(current);
      if (node == null) {
        break;
      }
      if (node.parentId == null) {
        break;
      }
      final parent = _nodeById(node.parentId!);
      if (parent != null) {
        _restoreNodeExpansion(parent);
      } else {
        _expanded.add(node.parentId!);
      }
      current = node.parentId!;
    }
  }

  List<SkillNode> _detailNodesForSelection(SkillNode node) {
    final path = _pathToNode(node);
    final result = <SkillNode>[...path];
    final parent = node.parentId == null ? node : _nodeById(node.parentId!);
    if (parent != null) {
      for (final sibling in parent.children) {
        if (!result.contains(sibling)) {
          result.add(sibling);
        }
      }
    }
    if (node.children.isNotEmpty && _expanded.contains(node.id)) {
      for (final child in node.children) {
        if (!result.contains(child)) {
          result.add(child);
        }
      }
    }
    result.sort((a, b) => compareSkillNodeIds(a.id, b.id));
    return result;
  }

  void _toggleNodeExpansion(SkillNode node) {
    if (_isLeafNode(node)) {
      return;
    }
    if (_expanded.contains(node.id)) {
      _collapseNode(node);
    } else {
      _restoreNodeExpansion(node);
    }
  }

  void _collapseNode(SkillNode node) {
    final descendantIds = _collectBranchDescendantIds(node);
    final expandedDescendants = descendantIds.where(_expanded.contains).toSet();
    _collapsedDescendants[node.id] = expandedDescendants;
    _expanded.remove(node.id);
    _expanded.removeAll(expandedDescendants);
  }

  void _restoreNodeExpansion(SkillNode node) {
    _expanded.add(node.id);
    final saved = _collapsedDescendants.remove(node.id);
    if (saved == null || saved.isEmpty) {
      return;
    }
    final valid = saved
        .where(
            (id) => id == 'math' || _parseResult?.nodes.containsKey(id) == true)
        .toSet();
    _expanded.addAll(valid);
  }

  Set<String> _collectBranchDescendantIds(SkillNode node) {
    final ids = <String>{};
    void walk(SkillNode current) {
      for (final child in current.children) {
        if (child.children.isNotEmpty) {
          ids.add(child.id);
          walk(child);
        }
      }
    }

    walk(node);
    return ids;
  }

  Future<void> _openSession({
    required int sessionId,
    required CourseVersion courseVersion,
    required CourseNode node,
    bool readOnly = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatSessionPage(
          sessionId: sessionId,
          courseVersion: courseVersion,
          node: node,
          readOnly: readOnly,
        ),
      ),
    );
  }

  Future<int?> _showSessionPicker(
    List<ChatSession> sessions, {
    required bool allowNew,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return showModalBottomSheet<int>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (allowNew) ...[
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(l10n.startNewSession),
                  onTap: () async {
                    if (sessions.isNotEmpty &&
                        !await _confirmNewSession(sessions.length)) {
                      return;
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop(_newSessionChoice);
                    }
                  },
                ),
                const Divider(height: 1),
              ],
              ...sessions.map((session) {
                final title = (session.title ?? '').trim().isNotEmpty
                    ? session.title!.trim()
                    : l10n.sessionLabel(session.id);
                return ListTile(
                  title: Text(title),
                  onTap: () => Navigator.of(context).pop(session.id),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirmNewSession(int existingCount) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newSessionConfirmTitle),
        content: Text(l10n.newSessionConfirmBody(existingCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.startNewSession),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _showLeafError(String message) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(l10n.requestFailedTitle),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }

  void _scheduleViewStateSave() {
    if (_currentUserId == null) {
      final auth = context.read<AuthController>();
      _currentUserId = auth.currentUser?.id;
      _persistViewState = auth.currentUser != null;
    }
    if (!_persistViewState || _currentUserId == null || _restoringState) {
      return;
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _saveViewState);
  }

  Future<void> _saveViewState() async {
    if (_currentUserId == null) {
      final auth = context.read<AuthController>();
      _currentUserId = auth.currentUser?.id;
      _persistViewState = auth.currentUser != null;
    }
    if (!_persistViewState ||
        _currentUserId == null ||
        _restoringState ||
        _parseResult == null) {
      return;
    }
    final payload = <String, dynamic>{
      'version': 1,
      'levelLimit': _levelLimit,
      'yearFilter': _yearFilter,
      'expanded': _expanded.toList(),
      'selectedId': _selectedId,
      'searchQuery': _searchQuery,
      'showRaw': _showRaw,
    };
    final viewStateJson = jsonEncode(payload);
    await _db.upsertTreeViewState(
      studentId: _currentUserId!,
      courseVersionId: widget.courseVersionId,
      viewStateJson: viewStateJson,
    );
  }

  Future<Map<String, dynamic>?> _loadViewState() async {
    if (_currentUserId == null) {
      final auth = context.read<AuthController>();
      _currentUserId = auth.currentUser?.id;
      _persistViewState = auth.currentUser != null;
    }
    if (!_persistViewState || _currentUserId == null) {
      return null;
    }
    final entry = await _db.getProgress(
      studentId: _currentUserId!,
      courseVersionId: widget.courseVersionId,
      kpKey: kTreeViewStateKpKey,
    );
    final raw = entry?.summaryText;
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  List<String> _readStringList(Object? value) {
    if (value is List) {
      return value
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
    }
    return const [];
  }

  bool _isLeafNode(SkillNode node) {
    if (node.isPlaceholder) {
      return false;
    }
    return node.children.isEmpty;
  }

  bool _isNodeFullyLit(SkillNode node, Map<String, bool> litMap) {
    if (_isLeafNode(node)) {
      return litMap[node.id] ?? false;
    }
    final leaves = _collectLeafNodes(node);
    if (leaves.isEmpty) {
      return false;
    }
    return leaves.every((leaf) => litMap[leaf.id] ?? false);
  }

  List<SkillNode> _collectLeafNodes(SkillNode node) {
    final leaves = <SkillNode>[];
    void walk(SkillNode current) {
      if (_isLeafNode(current)) {
        leaves.add(current);
        return;
      }
      for (final child in current.children) {
        walk(child);
      }
    }

    walk(node);
    return leaves;
  }

  Future<void> _toggleNodeLit({
    required SkillNode node,
    required Map<String, bool> litMap,
    required AppDatabase db,
    required int studentId,
    required bool includeAll,
  }) async {
    final leaves = includeAll
        ? _collectLeafNodes(node)
        : (_isLeafNode(node) ? [node] : const <SkillNode>[]);
    if (leaves.isEmpty) {
      return;
    }
    final allLit = leaves.every((leaf) => litMap[leaf.id] ?? false);
    final nextLit = !allLit;
    await db.transaction(() async {
      for (final leaf in leaves) {
        await db.setProgressLit(
          studentId: studentId,
          courseVersionId: widget.courseVersionId,
          kpKey: leaf.id,
          lit: nextLit,
          litPercent: nextLit ? 100 : 0,
        );
      }
    });
  }

  int _nodeDepth(SkillNode node) {
    if (node.id == 'math') {
      return 0;
    }
    return node.id.split('.').length;
  }

  double _nodeSizeFor(SkillNode node) {
    if (node.id == 'math') {
      return 30;
    }
    final depth = _nodeDepth(node);
    final size = 30 - ((depth - 1) * 5);
    if (size < 5) {
      return 5;
    }
    return size.toDouble();
  }

  Map<String, double> _calculateNodeProgress(
    SkillNode root,
    Map<String, int> litPercentMap,
  ) {
    final progress = <String, double>{};
    (int, int) walk(SkillNode node) {
      if (_isLeafNode(node)) {
        final percent = (litPercentMap[node.id] ?? 0).clamp(0, 100);
        progress[node.id] = percent / 100;
        return (percent, 1);
      }
      var sumPercent = 0;
      var total = 0;
      for (final child in node.children) {
        final (childSum, childTotal) = walk(child);
        sumPercent += childSum;
        total += childTotal;
      }
      final ratio = total == 0 ? 0.0 : sumPercent / (total * 100);
      progress[node.id] = ratio;
      return (sumPercent, total);
    }

    walk(root);
    return progress;
  }

  int _resolveLitPercent(ProgressEntry entry) {
    return resolveProgressDisplayPercent(
      lit: entry.lit,
      easyPassedCount: entry.easyPassedCount,
      mediumPassedCount: entry.mediumPassedCount,
      hardPassedCount: entry.hardPassedCount,
    );
  }

  Color _nodeColor(String nodeId, {required bool isLit}) {
    final ratio = _nodeProgress[nodeId] ?? 0.0;
    return resolveProgressDisplayColor(ratio: ratio, isLit: isLit);
  }

  List<SkillNode> _pathToNode(SkillNode node) {
    final result = <SkillNode>[];
    if (_parseResult == null) {
      return result;
    }
    final nodes = _parseResult!.nodes;
    var current = node;
    final visited = <String>{};
    while (true) {
      result.add(current);
      final parentId = current.parentId;
      if (parentId == null || visited.contains(parentId)) {
        break;
      }
      visited.add(parentId);
      final parent = nodes[parentId];
      if (parent == null) {
        break;
      }
      current = parent;
    }
    final ordered = result.reversed.toList();
    if (ordered.isEmpty || ordered.first.id != _parseResult!.root.id) {
      ordered.insert(0, _parseResult!.root);
    }
    return ordered;
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

  bool _matchesYear(SkillNode node) {
    final year = _yearFilter;
    if (year == null) {
      return true;
    }
    final start = node.yearStart;
    final end = node.yearEnd;
    if (start == null || end == null) {
      return false;
    }
    return year >= start && year <= end;
  }

  bool _hasMatchingDescendant(SkillNode node) {
    for (final child in node.children) {
      if (_matchesYear(child)) {
        return true;
      }
      if (child.children.isNotEmpty && _hasMatchingDescendant(child)) {
        return true;
      }
    }
    return false;
  }

  bool _isWithinExpandedPath(SkillNode node) {
    var current = node.parentId;
    while (current != null) {
      if (current != 'math' && !_expanded.contains(current)) {
        return false;
      }
      current = _nodeById(current)?.parentId;
    }
    return true;
  }

  bool _isNodeVisible(SkillNode node) {
    if (node.id == 'math') {
      return true;
    }
    if (!_passesFilters(node)) {
      return false;
    }
    return _isWithinExpandedPath(node);
  }

  bool _passesFilters(SkillNode node) {
    final depth = _nodeDepth(node);
    if (_yearFilter == null) {
      if (depth <= _levelLimit) {
        return true;
      }
      return _isWithinExpandedPath(node);
    }
    if (_matchesYear(node)) {
      return true;
    }
    if (node.children.isNotEmpty && _hasMatchingDescendant(node)) {
      return true;
    }
    return false;
  }

  Set<String> _expandedForLevel(int level) {
    if (_parseResult == null) {
      return {'math'};
    }
    final expanded = <String>{'math'};
    for (final node in _parseResult!.nodes.values) {
      if (node.children.isEmpty) {
        continue;
      }
      if (_nodeDepth(node) < level) {
        expanded.add(node.id);
      }
    }
    return expanded;
  }

  List<int> _yearOptions() {
    final minYear = _minYear;
    final maxYear = _maxYear;
    if (minYear == null || maxYear == null) {
      return const [];
    }
    return List.generate(maxYear - minYear + 1, (index) => minYear + index);
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

  (int, int)? _calculateYearRange(SkillTreeParseResult result) {
    int? minYear;
    int? maxYear;
    for (final node in result.nodes.values) {
      final start = node.yearStart;
      final end = node.yearEnd;
      if (start == null || end == null) {
        continue;
      }
      minYear = minYear == null ? start : (start < minYear ? start : minYear);
      maxYear = maxYear == null ? end : (end > maxYear ? end : maxYear);
    }
    if (minYear == null || maxYear == null) {
      return null;
    }
    return (minYear, maxYear);
  }
}
