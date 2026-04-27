import 'package:flutter/material.dart';

class SearchableModelPicker extends StatelessWidget {
  const SearchableModelPicker({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.emptyMessage,
    required this.onChanged,
    this.allowEmpty = false,
    this.emptyLabel = 'None',
    this.enabled = true,
  });

  final String label;
  final List<String> options;
  final String value;
  final String emptyMessage;
  final void Function(String? value) onChanged;
  final bool allowEmpty;
  final String emptyLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(emptyMessage),
      );
    }
    final selected = _selectedValue();
    return InkWell(
      onTap: enabled ? () => _openPicker(context, selected) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.search),
          enabled: enabled,
        ),
        child: Text(
          selected.isEmpty ? emptyLabel : selected,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _selectedValue() {
    final trimmed = value.trim();
    if (options.contains(trimmed)) {
      return trimmed;
    }
    if (allowEmpty && trimmed.isEmpty) {
      return '';
    }
    return options.first;
  }

  Future<void> _openPicker(BuildContext context, String selected) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _SearchableModelDialog(
        label: label,
        options: options,
        selected: selected,
        allowEmpty: allowEmpty,
        emptyLabel: emptyLabel,
        emptyMessage: emptyMessage,
      ),
    );
    if (result != null) {
      onChanged(result);
    }
  }
}

class _SearchableModelDialog extends StatefulWidget {
  const _SearchableModelDialog({
    required this.label,
    required this.options,
    required this.selected,
    required this.allowEmpty,
    required this.emptyLabel,
    required this.emptyMessage,
  });

  final String label;
  final List<String> options;
  final String selected;
  final bool allowEmpty;
  final String emptyLabel;
  final String emptyMessage;

  @override
  State<_SearchableModelDialog> createState() => _SearchableModelDialogState();
}

class _SearchableModelDialogState extends State<_SearchableModelDialog> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.options
        .where((model) => model.toLowerCase().contains(query))
        .toList();
    final items = <String>[
      if (widget.allowEmpty && widget.emptyLabel.toLowerCase().contains(query))
        '',
      ...filtered,
    ];
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: material.searchFieldLabel,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: items.isEmpty
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(widget.emptyMessage),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final model = items[index];
                        final selected = model == widget.selected;
                        return ListTile(
                          dense: true,
                          title: Text(
                            model.isEmpty ? widget.emptyLabel : model,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selected ? const Icon(Icons.check) : null,
                          onTap: () => Navigator.of(context).pop(model),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
