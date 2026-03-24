const String kTreeViewStateKpKey = '__view_state__';
const String kDefaultAuthBaseUrl = 'https://api.tutor1on1.org';
const String kAuthBaseUrl = String.fromEnvironment(
  'AUTH_BASE_URL',
  defaultValue: kDefaultAuthBaseUrl,
);
const bool kAuthAllowInsecureTls = bool.fromEnvironment(
  'AUTH_ALLOW_INSECURE_TLS',
  defaultValue: false,
);
