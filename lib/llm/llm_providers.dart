enum MaxTokensParam {
  maxTokens,
  maxCompletionTokens,
  auto,
}

enum LlmApiFormat {
  openAiChatCompletions,
  openAiCodexResponses,
  anthropicMessages,
}

enum LlmAuthMode {
  apiKey,
  openAiCodexOAuth,
}

enum ReasoningControlStyle {
  unsupported,
  openAiEffort,
  openRouterReasoning,
  anthropicThinking,
  deepSeekThinking,
  siliconFlowThinkingBudget,
}

class LlmProvider {
  const LlmProvider({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.models,
    required this.maxTokensParam,
    this.supportsTts = false,
    this.supportsStt = false,
    this.noTemperatureModelPrefixes = const [],
    this.authHeader = 'Authorization',
    this.authPrefix = 'Bearer ',
    this.chatPath = '/chat/completions',
    this.apiFormat = LlmApiFormat.openAiChatCompletions,
    this.authMode = LlmAuthMode.apiKey,
    this.reasoningControlStyle = ReasoningControlStyle.unsupported,
    this.supportsStructuredOutputs = false,
    this.extraHeaders = const <String, String>{},
  });

  final String id;
  final String label;
  final String baseUrl;
  final List<String> models;
  final MaxTokensParam maxTokensParam;
  final bool supportsTts;
  final bool supportsStt;
  final List<String> noTemperatureModelPrefixes;
  final String authHeader;
  final String authPrefix;
  final String chatPath;
  final LlmApiFormat apiFormat;
  final LlmAuthMode authMode;
  final ReasoningControlStyle reasoningControlStyle;
  final bool supportsStructuredOutputs;
  final Map<String, String> extraHeaders;

  String maxTokensField(String model) {
    switch (maxTokensParam) {
      case MaxTokensParam.maxCompletionTokens:
        return 'max_completion_tokens';
      case MaxTokensParam.auto:
        return _usesMaxCompletionTokens(model)
            ? 'max_completion_tokens'
            : 'max_tokens';
      case MaxTokensParam.maxTokens:
        return 'max_tokens';
    }
  }

  bool _usesMaxCompletionTokens(String model) {
    final value = model.toLowerCase();
    return value.startsWith('gpt-5');
  }

  bool supportsTemperature(String model) {
    final value = model.toLowerCase();
    for (final prefix in noTemperatureModelPrefixes) {
      if (value.startsWith(prefix.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  bool get supportsReasoning =>
      reasoningControlStyle != ReasoningControlStyle.unsupported;

  bool get usesOpenAiCodexOAuth => authMode == LlmAuthMode.openAiCodexOAuth;
}

class LlmProviders {
  static List<LlmProvider> defaultProviders({
    String? envBaseUrl,
    String? envModel,
  }) {
    final providers = <LlmProvider>[
      const LlmProvider(
        id: 'openai',
        label: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        models: [
          'gpt-5.2-2025-12-11',
          'gpt-4.1',
          'gpt-4o-mini',
        ],
        maxTokensParam: MaxTokensParam.auto,
        supportsTts: true,
        supportsStt: true,
        noTemperatureModelPrefixes: ['gpt-'],
        reasoningControlStyle: ReasoningControlStyle.openAiEffort,
        supportsStructuredOutputs: true,
      ),
      const LlmProvider(
        id: 'openai-codex',
        label: 'OpenAI Codex (ChatGPT OAuth)',
        baseUrl: 'https://chatgpt.com/backend-api',
        models: [
          'gpt-5.5',
          'gpt-5.4',
          'gpt-5.4-mini',
        ],
        maxTokensParam: MaxTokensParam.maxTokens,
        authMode: LlmAuthMode.openAiCodexOAuth,
        chatPath: '/codex/responses',
        apiFormat: LlmApiFormat.openAiCodexResponses,
        noTemperatureModelPrefixes: ['gpt-'],
        reasoningControlStyle: ReasoningControlStyle.openAiEffort,
        supportsStructuredOutputs: true,
      ),
      const LlmProvider(
        id: 'openrouter',
        label: 'OpenRouter',
        baseUrl: 'https://openrouter.ai/api/v1',
        models: [
          'openai/gpt-5.2',
          'anthropic/claude-sonnet-4',
          'google/gemini-2.5-flash',
        ],
        maxTokensParam: MaxTokensParam.maxTokens,
        reasoningControlStyle: ReasoningControlStyle.openRouterReasoning,
        supportsStructuredOutputs: true,
        extraHeaders: <String, String>{
          'HTTP-Referer': 'https://www.tutor1on1.org',
          'X-OpenRouter-Title': 'Tutor1on1',
        },
      ),
      const LlmProvider(
        id: 'anthropic',
        label: 'Anthropic',
        baseUrl: 'https://api.anthropic.com/v1',
        models: [
          'claude-sonnet-4-6',
          'claude-haiku-4-5',
          'claude-opus-4-6',
        ],
        maxTokensParam: MaxTokensParam.maxTokens,
        authHeader: 'x-api-key',
        authPrefix: '',
        chatPath: '/messages',
        apiFormat: LlmApiFormat.anthropicMessages,
        reasoningControlStyle: ReasoningControlStyle.anthropicThinking,
        extraHeaders: <String, String>{
          'anthropic-version': '2023-06-01',
        },
      ),
      const LlmProvider(
        id: 'gemini',
        label: 'Google Gemini',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
        models: [
          'gemini-2.5-pro',
          'gemini-2.5-flash',
          'gemini-2.5-flash-lite',
        ],
        maxTokensParam: MaxTokensParam.maxTokens,
        authHeader: 'Authorization',
        authPrefix: 'Bearer ',
        reasoningControlStyle: ReasoningControlStyle.openAiEffort,
        supportsStructuredOutputs: true,
      ),
      const LlmProvider(
        id: 'grok',
        label: 'Grok',
        baseUrl: 'https://api.x.ai/v1',
        models: [
          'grok-4',
          'grok-4-fast-reasoning',
          'grok-4-fast-non-reasoning',
        ],
        maxTokensParam: MaxTokensParam.maxTokens,
        supportsStructuredOutputs: true,
      ),
      const LlmProvider(
        id: 'siliconflow',
        label: 'SiliconFlow',
        baseUrl: 'https://api.siliconflow.cn/v1',
        models: [
          'deepseek-ai/DeepSeek-V3.2',
        ],
        maxTokensParam: MaxTokensParam.maxTokens,
        supportsTts: true,
        supportsStt: true,
        reasoningControlStyle: ReasoningControlStyle.siliconFlowThinkingBudget,
      ),
      const LlmProvider(
        id: 'deepseek',
        label: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        models: [
          'deepseek-chat',
          'deepseek-reasoner',
        ],
        maxTokensParam: MaxTokensParam.maxTokens,
        reasoningControlStyle: ReasoningControlStyle.deepSeekThinking,
      ),
    ];

    final trimmedEnvBaseUrl = envBaseUrl?.trim() ?? '';
    if (trimmedEnvBaseUrl.isNotEmpty) {
      providers.insert(
        0,
        LlmProvider(
          id: 'env',
          label: 'Env (OPENAI_BASE_URL)',
          baseUrl: trimmedEnvBaseUrl,
          models: [
            if ((envModel ?? '').trim().isNotEmpty) envModel!.trim(),
          ],
          maxTokensParam: MaxTokensParam.maxTokens,
        ),
      );
    }

    return providers;
  }

  static LlmProvider? findById(
    List<LlmProvider> providers,
    String? id,
  ) {
    if (id == null || id.trim().isEmpty) {
      return null;
    }
    final match = providers.where((provider) => provider.id == id).toList();
    if (match.isNotEmpty) {
      return match.first;
    }
    return null;
  }

  static LlmProvider? findByBaseUrl(
    List<LlmProvider> providers,
    String baseUrl,
  ) {
    final normalized = _normalizeBaseUrl(baseUrl);
    for (final provider in providers) {
      if (_normalizeBaseUrl(provider.baseUrl) == normalized) {
        return provider;
      }
    }
    return null;
  }

  static String _normalizeBaseUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
