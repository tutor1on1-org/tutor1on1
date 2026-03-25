import 'package:flutter/material.dart';
import 'package:tutor1on1/l10n/app_language.dart';
import 'package:tutor1on1/l10n/app_localizations.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({
    super.key,
    required this.localeCode,
    required this.onChanged,
    this.width,
  });

  final String? localeCode;
  final ValueChanged<String?> onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selectedLocale = normalizeAppLanguageCode(localeCode);
    final field = DropdownButtonFormField<String>(
      key: ValueKey('language-selector-$selectedLocale'),
      initialValue: selectedLocale,
      decoration: InputDecoration(
        labelText: l10n.languageTitle,
        prefixIcon: const Icon(Icons.language),
      ),
      items: [
        DropdownMenuItem(
          value: '',
          child: Text(l10n.languageSystem),
        ),
        ...supportedAppLanguages.map(
          (language) => DropdownMenuItem(
            value: language.code,
            child: Text(language.label),
          ),
        ),
      ],
      onChanged: (value) => onChanged(
        (value ?? '').trim().isEmpty ? null : value,
      ),
    );
    if (width == null) {
      return field;
    }
    return SizedBox(
      width: width,
      child: field,
    );
  }
}
