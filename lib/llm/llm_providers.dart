enum MaxTokensParam {
  maxTokens,
  maxCompletionTokens,
  auto,
}

enum LlmApiFormat {
  openAiChatCompletions,
  anthropicMessages,
}

enum ReasoningControlStyle {
  unsupported,
  openAiEffort,
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
    this.noTemperatureModelPrefixes = const [],
    this.authHeader = 'Authorization',
    this.authPrefix = 'Bearer ',
    this.chatPath = '/chat/completions',
    this.apiFormat = LlmApiFormat.openAiChatCompletions,
    this.reasoningControlStyle = ReasoningControlStyle.unsupported,
    this.extraHeaders = const <String, String>{},
  });

  final String id;
  final String label;
  final String baseUrl;
  final List<String> models;
  final MaxTokensParam maxTokensParam;
  final List<String> noTemperatureModelPrefixes;
  final String authHeader;
  final String authPrefix;
  final String chatPath;
  final LlmApiFormat apiFormat;
  final ReasoningControlStyle reasoningControlStyle;
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
        noTemperatureModelPrefixes: ['gpt-'],
        reasoningControlStyle: ReasoningControlStyle.openAiEffort,
      ),
      const LlmProvider(
        id: 'anthropic',
        label: 'Anthropic',
        baseUrl: 'https://api.anthropic.com/v1',
        models: [
          'claude-3-5-sonnet-20240620',
          'claude-3-5-haiku-20241022',
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
          'gemini-3-pro-preview',
          'gemini-3-flash-preview',
        ],
        maxTokensParam: MaxTokensParam.maxTokens,
        authHeader: 'Authorization',
        authPrefix: 'Bearer ',
        reasoningControlStyle: ReasoningControlStyle.openAiEffort,
      ),
      const LlmProvider(
        id: 'grok',
        label: 'Grok',
        baseUrl: 'https://api.x.ai/v1',
        models: [
          'grok-2',
          'grok-2-mini',
        ],
        maxTokensParam: MaxTokensParam.maxTokens,
      ),
      const LlmProvider(
        id: 'siliconflow',
        label: 'SiliconFlow',
        baseUrl: 'https://api.siliconflow.cn/v1',
        models: [
          'deepseek-ai/DeepSeek-V3.2',
        ],
        maxTokensParam: MaxTokensParam.maxTokens,
        reasoningControlStyle: ReasoningControlStyle.siliconFlowThinkingBudget,
      ),
      const LlmProvider(
        id: 'deepseek',
        label: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
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
