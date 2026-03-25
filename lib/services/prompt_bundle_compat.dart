import 'legacy_brand_compat.dart';

const String kCurrentPromptBundleSchema = 'tutor1on1_prompt_bundle_v1';
final String kLegacyPromptBundleSchema = buildLegacyPromptBundleSchema();

const String kCurrentPromptMetadataEntryPath = '_tutor1on1/prompt_bundle.json';
final String kLegacyPromptMetadataEntryPath =
    buildLegacyPromptMetadataEntryPath();

bool isSupportedPromptBundleSchema(String value) {
  final normalized = value.trim();
  return normalized == kCurrentPromptBundleSchema ||
      normalized == kLegacyPromptBundleSchema;
}

bool isSupportedPromptMetadataEntryPath(String value) {
  final normalized = value.trim().replaceAll('\\', '/');
  return normalized == kCurrentPromptMetadataEntryPath ||
      normalized == kLegacyPromptMetadataEntryPath;
}
