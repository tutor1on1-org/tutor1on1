import 'dart:convert';

import 'package:http/http.dart' as http;

import '../llm/llm_providers.dart';

class ApiModelInfo {
  const ApiModelInfo({
    required this.id,
    this.type,
    this.subType,
  });

  final String id;
  final String? type;
  final String? subType;
}

class ModelListResult {
  const ModelListResult({
    required this.models,
    this.statusCode,
    this.error,
  });

  final List<ApiModelInfo> models;
  final int? statusCode;
  final String? error;

  bool get isSuccess => error == null;
}

class ApiModelLists {
  const ApiModelLists({
    required this.textModels,
    required this.ttsModels,
    required this.sttModels,
  });

  final List<String> textModels;
  final List<String> ttsModels;
  final List<String> sttModels;
}

class ModelListService {
  static Future<ModelListResult> fetchModels({
    required LlmProvider provider,
    required String baseUrl,
    required String apiKey,
  }) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    final url = Uri.parse('$normalized/models');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      provider.authHeader: '${provider.authPrefix}${apiKey.trim()}',
      ...provider.extraHeaders,
    };
    try {
      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ModelListResult(
          models: const [],
          statusCode: response.statusCode,
          error: response.body.isNotEmpty
              ? response.body
              : 'HTTP ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      final items = _extractModelList(decoded);
      final models = <ApiModelInfo>[];
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final id =
              (item['id'] ?? item['name'] ?? item['model'])?.toString().trim();
          if (id == null || id.isEmpty) {
            continue;
          }
          final type = item['type']?.toString();
          final subType =
              item['sub_type']?.toString() ?? item['subType']?.toString();
          models.add(ApiModelInfo(id: id, type: type, subType: subType));
        } else if (item is String && item.trim().isNotEmpty) {
          models.add(ApiModelInfo(id: item.trim()));
        }
      }
      return ModelListResult(models: models, statusCode: response.statusCode);
    } catch (error) {
      return ModelListResult(
        models: const [],
        error: error.toString(),
      );
    }
  }

  static ApiModelLists splitModels({
    required List<ApiModelInfo> models,
    required String baseUrl,
    required String providerId,
  }) {
    final normalized = _normalizeBaseUrl(baseUrl).toLowerCase();
    final isOpenAi =
        providerId == 'openai' || normalized.contains('openai.com');
    final isSilicon =
        providerId == 'siliconflow' || normalized.contains('siliconflow');
    final text = <String>{};
    final tts = <String>{};
    final stt = <String>{};
    for (final model in models) {
      final id = model.id.trim();
      if (id.isEmpty) {
        continue;
      }
      if (isOpenAi || isSilicon) {
        final kind = _inferAudioKind(
          model: model,
          isOpenAi: isOpenAi,
          isSilicon: isSilicon,
        );
        if (kind == _AudioKind.tts) {
          tts.add(id);
          continue;
        }
        if (kind == _AudioKind.stt) {
          stt.add(id);
          continue;
        }
      }
      text.add(id);
    }
    final textList = text.toList()..sort();
    final ttsList = tts.toList()..sort();
    final sttList = stt.toList()..sort();
    return ApiModelLists(
      textModels: textList,
      ttsModels: ttsList,
      sttModels: sttList,
    );
  }

  static List<dynamic> _extractModelList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is List) {
        return data;
      }
      final models = decoded['models'];
      if (models is List) {
        return models;
      }
    }
    return const [];
  }

  static _AudioKind? _inferAudioKind({
    required ApiModelInfo model,
    required bool isOpenAi,
    required bool isSilicon,
  }) {
    final id = model.id.toLowerCase();
    final type = (model.type ?? '').toLowerCase();
    final subType = (model.subType ?? '').toLowerCase();
    if (isSilicon) {
      if (subType.contains('speech-recognition') ||
          subType.contains('asr') ||
          subType.contains('transcription')) {
        return _AudioKind.stt;
      }
      if (subType.contains('speech-synthesis') ||
          subType.contains('tts') ||
          subType.contains('text-to-speech')) {
        return _AudioKind.tts;
      }
      if (id.contains('sensevoice') || id.contains('telespeech')) {
        return _AudioKind.stt;
      }
      if (id.contains('cosyvoice') || id.contains('tts')) {
        return _AudioKind.tts;
      }
    }
    if (isOpenAi) {
      if (id.contains('transcribe') || id.contains('whisper')) {
        return _AudioKind.stt;
      }
      if (id.contains('tts')) {
        return _AudioKind.tts;
      }
    }
    if (type.contains('speech') || type.contains('audio')) {
      if (subType.contains('recognition') || subType.contains('asr')) {
        return _AudioKind.stt;
      }
      if (subType.contains('synthesis') || subType.contains('tts')) {
        return _AudioKind.tts;
      }
    }
    if (id.contains('asr')) {
      return _AudioKind.stt;
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

enum _AudioKind { tts, stt }
