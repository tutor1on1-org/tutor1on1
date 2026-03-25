const List<int> _legacyBrandCodeUnits = <int>[
  102,
  97,
  109,
  105,
  108,
  121,
  95,
  116,
  101,
  97,
  99,
  104,
  101,
  114,
];

String buildLegacyBrandToken() =>
    String.fromCharCodes(_legacyBrandCodeUnits);

String buildLegacyDatabaseFileName() => '${buildLegacyBrandToken()}.db';

String buildLegacyWindowsProductName() => buildLegacyBrandToken();

String buildLegacyPromptBundleSchema() =>
    '${buildLegacyBrandToken()}_prompt_bundle_v1';

String buildLegacyPromptMetadataEntryPath() =>
    '_${buildLegacyBrandToken()}/prompt_bundle.json';

String buildLegacyLogSaltPrefix() => '${buildLegacyBrandToken()}_log_v1';
