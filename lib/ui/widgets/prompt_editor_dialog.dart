import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/prompt_template_validator.dart';

List<String> buildPromptValidationMessages(
  AppLocalizations l10n,
  PromptValidationResult validation,
) {
  final missing = validation.missingVariables.join(', ');
  final unknown = validation.unknownVariables.join(', ');
  final invalid = validation.invalidVariables.join(', ');
  final messages = <String>[];
  if (validation.missingVariables.isNotEmpty) {
    messages.add(l10n.promptMissingVars(missing));
  }
  if (validation.unknownVariables.isNotEmpty) {
    messages.add(l10n.promptUnknownVars(unknown));
  }
  if (validation.invalidVariables.isNotEmpty) {
    messages.add(
      'Invalid variables: $invalid. Prompt variables must stay English-only, for example {{student_input}}.',
    );
  }
  return messages;
}

class PromptEditorDialog extends StatefulWidget {
  const PromptEditorDialog({
    super.key,
    required this.title,
    required this.promptName,
    required this.initialContent,
    required this.validator,
    required this.variableRows,
    required this.allVariableRows,
  });

  final String title;
  final String promptName;
  final String initialContent;
  final PromptTemplateValidator validator;
  final List<Widget> variableRows;
  final List<Widget> allVariableRows;

  @override
  State<PromptEditorDialog> createState() => _PromptEditorDialogState();
}

class _PromptEditorDialogState extends State<PromptEditorDialog> {
  late final TextEditingController _controller;
  List<String> _validationMessages = const <String>[];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context)!;
    final validation = widget.validator.validate(
      promptName: widget.promptName,
      content: _controller.text,
      allowMissingRequired: false,
    );
    if (!validation.isValid) {
      setState(() {
        _validationMessages = buildPromptValidationMessages(l10n, validation);
      });
      return;
    }
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                maxLines: 18,
                minLines: 8,
                decoration: InputDecoration(
                  labelText: l10n.promptTemplateLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_validationMessages.isNotEmpty) ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _validationMessages.join('\n'),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                l10n.promptRequiredVars(
                  widget.validator
                      .requiredVariables(widget.promptName)
                      .join(', '),
                ),
              ),
              Text(
                l10n.promptAllowedVars(
                  widget.validator
                      .allowedVariables(widget.promptName)
                      .join(', '),
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Prompt variables',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),
              ...widget.variableRows,
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'All supported variables',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),
              ...widget.allVariableRows,
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(l10n.saveButton),
        ),
      ],
    );
  }
}
