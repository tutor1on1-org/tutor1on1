import 'dart:convert';

import 'llm_models.dart';
import 'llm_providers.dart';

class LlmPreparedResponse {
  const LlmPreparedResponse({
    required this.responseText,
    this.reasoningText,
    this.reasoningTokens,
  });

  final String responseText;
  final String? reasoningText;
  final int? reasoningTokens;
}

class LlmReasoningSupport {
  static List<String> effortOptionsForProvider(LlmProvider provider) {
    if (!provider.supportsReasoning) {
      return const <String>[ReasoningEffort.medium];
    }
    return ReasoningEffort.values;
  }

  static String normalizeEffort(String? value) {
    return ReasoningEffort.normalize(value);
  }

  static void applyRequestFields({
    required Map<String, dynamic> bodyMap,
    required LlmProvider provider,
    required String model,
    required String reasoningEffort,
    required int maxTokens,
  }) {
    final normalizedEffort = normalizeEffort(reasoningEffort);
    switch (provider.reasoningControlStyle) {
      case ReasoningControlStyle.unsupported:
        return;
      case ReasoningControlStyle.openAiEffort:
        bodyMap['reasoning_effort'] = normalizedEffort;
        return;
      case ReasoningControlStyle.openRouterReasoning:
        bodyMap['reasoning'] = <String, dynamic>{
          'effort': normalizedEffort,
        };
        return;
      case ReasoningControlStyle.deepSeekThinking:
        bodyMap['thinking'] = <String, dynamic>{
          'type':
              normalizedEffort == ReasoningEffort.none ? 'disabled' : 'enabled',
        };
        return;
      case ReasoningControlStyle.siliconFlowThinkingBudget:
        if (normalizedEffort == ReasoningEffort.none) {
          bodyMap['enable_thinking'] = false;
          bodyMap.remove('thinking_budget');
          return;
        }
        bodyMap['enable_thinking'] = true;
        bodyMap['thinking_budget'] = _siliconFlowBudgetForEffort(
          effort: normalizedEffort,
          maxTokens: maxTokens,
        );
        return;
      case ReasoningControlStyle.anthropicThinking:
        if (normalizedEffort == ReasoningEffort.none) {
          return;
        }
        bodyMap['thinking'] = <String, dynamic>{
          'type': 'enabled',
          'budget_tokens': _anthropicBudgetForEffort(
            effort: normalizedEffort,
            maxTokens: maxTokens,
          ),
        };
        return;
    }
  }

  static LlmPreparedResponse extractResponse({
    required Map<String, dynamic> payload,
    required LlmProvider provider,
  }) {
    final responseText = switch (provider.apiFormat) {
      LlmApiFormat.anthropicMessages => _extractAnthropicText(payload),
      LlmApiFormat.openAiChatCompletions =>
        _extractOpenAiCompatibleText(payload),
    };
    final reasoningText = switch (provider.apiFormat) {
      LlmApiFormat.anthropicMessages => _extractAnthropicReasoning(payload),
      LlmApiFormat.openAiChatCompletions =>
        _extractOpenAiCompatibleReasoning(payload),
    };
    final normalizedReasoning = _normalizeJoinedText(reasoningText);
    return LlmPreparedResponse(
      responseText: _normalizeJoinedText(responseText) ?? '',
      reasoningText: normalizedReasoning,
      reasoningTokens: _extractReasoningTokens(payload),
    );
  }

  static LlmPreparedResponse extractAnthropicEvent(
    Map<String, dynamic> payload,
  ) {
    final contentBlock = payload['content_block'];
    if (contentBlock is Map<String, dynamic>) {
      final type = (contentBlock['type'] as String?)?.trim().toLowerCase();
      if (type == 'text') {
        return LlmPreparedResponse(
          responseText: (contentBlock['text'] as String?) ?? '',
        );
      }
      if (type == 'thinking') {
        return LlmPreparedResponse(
          responseText: '',
          reasoningText: (contentBlock['thinking'] as String?) ?? '',
        );
      }
    }
    final delta = payload['delta'];
    if (delta is Map<String, dynamic>) {
      final type = (delta['type'] as String?)?.trim().toLowerCase();
      if (type == 'text_delta') {
        return LlmPreparedResponse(
          responseText: (delta['text'] as String?) ?? '',
        );
      }
      if (type == 'thinking_delta') {
        return LlmPreparedResponse(
          responseText: '',
          reasoningText: (delta['thinking'] as String?) ?? '',
        );
      }
    }
    return const LlmPreparedResponse(responseText: '');
  }

  static String? encodeReasoningLog({
    required LlmProvider provider,
    required String model,
    required String reasoningEffort,
    String? reasoningText,
    int? reasoningTokens,
  }) {
    final rawReasoningText = reasoningText;
    return jsonEncode(<String, dynamic>{
      'provider_id': provider.id,
      'model': model,
      'reasoning_effort': normalizeEffort(reasoningEffort),
      'reasoning_text':
          (rawReasoningText ?? '').trim().isEmpty ? null : rawReasoningText,
      'reasoning_tokens': reasoningTokens,
    });
  }

  static int _anthropicBudgetForEffort({
    required String effort,
    required int maxTokens,
  }) {
    final requested = switch (effort) {
      ReasoningEffort.low => 2048,
      ReasoningEffort.high => 16384,
      _ => 8192,
    };
    if (maxTokens <= 0) {
      return requested;
    }
    return requested > maxTokens ? maxTokens : requested;
  }

  static int _siliconFlowBudgetForEffort({
    required String effort,
    required int maxTokens,
  }) {
    final requested = switch (effort) {
      ReasoningEffort.low => 2048,
      ReasoningEffort.high => 6144,
      _ => 4096,
    };
    if (maxTokens <= 0) {
      return requested;
    }
    return requested > maxTokens ? maxTokens : requested;
  }

  static String? _extractOpenAiCompatibleText(Map<String, dynamic> payload) {
    final outputText = payload['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) {
      return outputText;
    }
    final output = payload['output'];
    if (output is List) {
      final buffer = StringBuffer();
      for (final item in output) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final type = (item['type'] as String?)?.trim().toLowerCase();
        if (type == 'reasoning') {
          continue;
        }
        buffer.write(_extractFinalTextValue(item));
      }
      final result = _normalizeJoinedText(buffer.toString());
      if (result != null) {
        return result;
      }
    }
    final choices = payload['choices'];
    if (choices is List) {
      final buffer = StringBuffer();
      for (final choice in choices) {
        if (choice is! Map<String, dynamic>) {
          continue;
        }
        final message = choice['message'] ?? choice['delta'] ?? choice;
        if (message is! Map<String, dynamic>) {
          continue;
        }
        final content = message['content'];
        if (content != null) {
          buffer.write(_extractFinalTextValue(content));
        }
        final text = message['text'];
        if (text is String) {
          buffer.write(text);
        }
        final directText = choice['text'];
        if (directText is String) {
          buffer.write(directText);
        }
      }
      return _normalizeJoinedText(buffer.toString());
    }
    return null;
  }

  static String? _extractOpenAiCompatibleReasoning(
    Map<String, dynamic> payload,
  ) {
    final output = payload['output'];
    final buffer = StringBuffer();
    if (output is List) {
      for (final item in output) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final type = (item['type'] as String?)?.trim().toLowerCase();
        if (type != 'reasoning') {
          continue;
        }
        appendReasoningFragment(buffer, _extractReasoningValue(item));
      }
    }
    final choices = payload['choices'];
    if (choices is List) {
      for (final choice in choices) {
        if (choice is! Map<String, dynamic>) {
          continue;
        }
        final message = choice['message'] ?? choice['delta'] ?? choice;
        if (message is! Map<String, dynamic>) {
          continue;
        }
        if (_appendPreferredOpenAiReasoning(buffer, message)) {
          continue;
        }
        if (_appendPreferredOpenAiReasoning(buffer, choice)) {
          continue;
        }
        final reasoningContent = message['reasoning_content'];
        if (reasoningContent is String) {
          appendReasoningFragment(buffer, reasoningContent);
        }
      }
    }
    return _normalizeJoinedText(buffer.toString());
  }

  static String? _extractAnthropicText(Map<String, dynamic> payload) {
    final content = payload['content'];
    if (content is! List) {
      return null;
    }
    final buffer = StringBuffer();
    for (final block in content) {
      if (block is! Map<String, dynamic>) {
        continue;
      }
      final type = (block['type'] as String?)?.trim().toLowerCase();
      if (type == 'text') {
        final text = block['text'];
        if (text is String) {
          buffer.write(text);
        }
      }
    }
    return _normalizeJoinedText(buffer.toString());
  }

  static String? _extractAnthropicReasoning(Map<String, dynamic> payload) {
    final content = payload['content'];
    if (content is! List) {
      return null;
    }
    final buffer = StringBuffer();
    for (final block in content) {
      if (block is! Map<String, dynamic>) {
        continue;
      }
      final type = (block['type'] as String?)?.trim().toLowerCase();
      if (type == 'thinking') {
        final text = block['thinking'] ?? block['text'];
        if (text is String) {
          appendReasoningFragment(buffer, text);
        }
      }
    }
    return _normalizeJoinedText(buffer.toString());
  }

  static String _extractFinalTextValue(dynamic value) {
    if (value is String) {
      return value;
    }
    if (value is List) {
      final fragments = <String>[];
      for (final item in value) {
        final fragment = _extractFinalTextValue(item);
        if (fragment.isNotEmpty) {
          fragments.add(fragment);
        }
      }
      return _joinJsonAwareFragments(fragments);
    }
    if (value is Map<String, dynamic>) {
      final type = (value['type'] as String?)?.trim().toLowerCase();
      if ((type?.startsWith('reasoning') ?? false) ||
          (type?.startsWith('thinking') ?? false)) {
        return '';
      }
      if (value['output_text'] is String) {
        return value['output_text'] as String;
      }
      if (value['text'] is String) {
        return value['text'] as String;
      }
      if (value['content'] != null) {
        return _extractFinalTextValue(value['content']);
      }
    }
    return '';
  }

  static String _extractReasoningValue(dynamic value) {
    if (value is String) {
      return value;
    }
    if (value is List) {
      final buffer = StringBuffer();
      for (final item in value) {
        appendReasoningFragment(buffer, _extractReasoningValue(item));
      }
      return buffer.toString();
    }
    if (value is Map<String, dynamic>) {
      final type = (value['type'] as String?)?.trim().toLowerCase();
      if ((type?.startsWith('reasoning') ?? false) ||
          (type?.startsWith('thinking') ?? false)) {
        final reasoningText = value['thinking'] ?? value['summary'];
        if (reasoningText != null) {
          return _extractReasoningValue(reasoningText);
        }
      }
      if (value['text'] != null) {
        return _extractReasoningValue(value['text']);
      }
      if (value['summary'] != null) {
        return _extractReasoningValue(value['summary']);
      }
      if (value['thinking'] != null) {
        return _extractReasoningValue(value['thinking']);
      }
      if (value['content'] != null) {
        return _extractReasoningValue(value['content']);
      }
    }
    return '';
  }

  static int? _extractReasoningTokens(Map<String, dynamic> payload) {
    final usage = payload['usage'];
    if (usage is! Map<String, dynamic>) {
      return null;
    }
    final direct = usage['reasoning_tokens'];
    if (direct is num) {
      return direct.toInt();
    }
    final outputTokensDetails = usage['output_tokens_details'];
    if (outputTokensDetails is Map<String, dynamic>) {
      final reasoningTokens = outputTokensDetails['reasoning_tokens'];
      if (reasoningTokens is num) {
        return reasoningTokens.toInt();
      }
    }
    final completionTokensDetails = usage['completion_tokens_details'];
    if (completionTokensDetails is Map<String, dynamic>) {
      final reasoningTokens = completionTokensDetails['reasoning_tokens'];
      if (reasoningTokens is num) {
        return reasoningTokens.toInt();
      }
    }
    return null;
  }

  static bool _appendPreferredOpenAiReasoning(
    StringBuffer buffer,
    Map<String, dynamic> source,
  ) {
    final reasoningDetails = source['reasoning_details'];
    if (reasoningDetails != null) {
      final extracted = _extractReasoningValue(reasoningDetails);
      if (extracted.isNotEmpty) {
        appendReasoningFragment(buffer, extracted);
        return true;
      }
    }
    final reasoning = source['reasoning'];
    if (reasoning != null) {
      final extracted = _extractReasoningValue(reasoning);
      if (extracted.isNotEmpty) {
        appendReasoningFragment(buffer, extracted);
        return true;
      }
    }
    return false;
  }

  static String? _normalizeJoinedText(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static void appendReasoningFragment(
    StringBuffer buffer,
    String fragment,
  ) {
    if (fragment.isEmpty) {
      return;
    }
    final current = buffer.toString();
    if (current.isEmpty) {
      buffer.write(fragment);
      return;
    }
    buffer.write(_normalizeNaturalLanguageFragmentSeam(current, fragment));
  }

  static void appendJsonAwareFragment(
    StringBuffer buffer,
    String fragment,
  ) {
    appendJsonAwareFragmentAndReturnDelta(buffer, fragment);
  }

  static String appendJsonAwareFragmentAndReturnDelta(
    StringBuffer buffer,
    String fragment,
  ) {
    if (fragment.isEmpty) {
      return '';
    }
    final current = buffer.toString();
    final normalized = _normalizeJsonFragmentSeam(current, fragment);
    buffer.write(normalized);
    return normalized;
  }

  static String _joinJsonAwareFragments(List<String> fragments) {
    final cleaned = fragments.where((fragment) => fragment.isNotEmpty).toList();
    if (cleaned.isEmpty) {
      return '';
    }
    if (cleaned.length == 1) {
      return cleaned.first;
    }
    final buffer = StringBuffer(cleaned.first);
    for (final fragment in cleaned.skip(1)) {
      appendJsonAwareFragment(buffer, fragment);
    }
    return buffer.toString();
  }

  static String _normalizeNaturalLanguageFragmentSeam(
    String current,
    String next,
  ) {
    if (current.isEmpty || next.isEmpty) {
      return next;
    }
    final trailingWhitespace = _trailingInlineWhitespaceCount(current);
    final leadingWhitespace = _leadingInlineWhitespaceCount(next);
    if (trailingWhitespace > 0 && leadingWhitespace > 0) {
      final overlap = trailingWhitespace < leadingWhitespace
          ? trailingWhitespace
          : leadingWhitespace;
      return next.substring(overlap);
    }
    final previousChar = current[current.length - 1];
    final nextChar = next[0];
    if (_isWhitespace(previousChar) || _isWhitespace(nextChar)) {
      return next;
    }
    if (_isWordLike(previousChar) && _isWordLike(nextChar)) {
      return ' $next';
    }
    return next;
  }

  static String _normalizeJsonFragmentSeam(String current, String next) {
    if (current.isEmpty || next.isEmpty) {
      return next;
    }
    final trailingWhitespace = _trailingInlineWhitespaceCount(current);
    final leadingWhitespace = _leadingInlineWhitespaceCount(next);
    if (trailingWhitespace > 0 && leadingWhitespace > 0) {
      final overlap = trailingWhitespace < leadingWhitespace
          ? trailingWhitespace
          : leadingWhitespace;
      return next.substring(overlap);
    }
    return next;
  }

  static int _leadingInlineWhitespaceCount(String value) {
    var count = 0;
    while (count < value.length && _isInlineWhitespace(value[count])) {
      count += 1;
    }
    return count;
  }

  static int _trailingInlineWhitespaceCount(String value) {
    var count = 0;
    while (count < value.length &&
        _isInlineWhitespace(value[value.length - 1 - count])) {
      count += 1;
    }
    return count;
  }

  static bool _isWhitespace(String value) => value.trim().isEmpty;

  static bool _isInlineWhitespace(String value) =>
      value == ' ' || value == '\t';

  static bool _isWordLike(String value) =>
      RegExp(r'[A-Za-z0-9]').hasMatch(value);
}
