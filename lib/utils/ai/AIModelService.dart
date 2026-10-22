import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../SecureStorageService.dart';
import '../AppBrand.dart';

class AIConfiguration {
  const AIConfiguration({
    this.model = '',
    this.language = 'Português brasileiro',
    this.instructions = '',
    this.maxTokens = 6000,
  });
  final String model, language, instructions;
  final int maxTokens;
  static Future<AIConfiguration> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AIConfiguration(
      model: await SecureStorageService.readOpenRouterModel() ?? '',
      language:
          prefs.getString('twitter_ai_language') ?? 'Português brasileiro',
      instructions: prefs.getString('twitter_ai_instructions') ?? '',
      maxTokens: (prefs.getInt('twitter_ai_max_tokens') ?? 6000).clamp(
        512,
        24000,
      ),
    );
  }

  Future<void> save() async {
    await SecureStorageService.writeOpenRouterModel(model);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('twitter_ai_language', language);
    await prefs.setString('twitter_ai_instructions', instructions);
    await prefs.setInt('twitter_ai_max_tokens', maxTokens.clamp(512, 24000));
  }
}

class AIResponse {
  const AIResponse(this.text, this.promptTokens, this.completionTokens);
  final String text;
  final int promptTokens, completionTokens;
}

class AIModelService {
  static Future<bool> isReady() async =>
      (await SecureStorageService.readOpenRouterApiKey())?.trim().isNotEmpty ==
          true &&
      (await AIConfiguration.load()).model.trim().isNotEmpty;

  static Future<List<Map<String, dynamic>>> models() async {
    final client = http.Client();
    try {
      final key = await SecureStorageService.readOpenRouterApiKey();
      final response = await client
          .get(
            Uri.parse('https://openrouter.ai/api/v1/models'),
            headers: {
              if (key?.isNotEmpty == true) 'Authorization': 'Bearer $key',
            },
          )
          .timeout(const Duration(seconds: 30));
      final body = _decodeResponse(response);
      return (body['data'] as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where(
            (m) =>
                (m['architecture']?['output_modalities'] as List? ?? ['text'])
                    .contains('text'),
          )
          .toList();
    } on TimeoutException {
      throw const FormatException('A lista de modelos demorou para responder.');
    } on SocketException {
      throw const FormatException('Sem conexão com o OpenRouter.');
    } on http.ClientException catch (error) {
      throw FormatException(
        'Falha na conexão com o OpenRouter: ${error.message}',
      );
    } finally {
      client.close();
    }
  }

  static Future<AIResponse> complete(
    String system,
    String content, {
    int? maxTokens,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final key = await SecureStorageService.readOpenRouterApiKey();
    final config = await AIConfiguration.load();
    if (key == null || key.trim().isEmpty || config.model.isEmpty) {
      throw const FormatException(
        'Configure a chave e o modelo em Configurações > Inteligência artificial.',
      );
    }
    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
              'X-OpenRouter-Title': AppBrand.name,
            },
            body: jsonEncode({
              'model': config.model,
              'stream': false,
              'max_tokens': maxTokens ?? config.maxTokens,
              'temperature': 0.85,
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': content},
              ],
            }),
          )
          .timeout(timeout);
      final body = _decodeResponse(response);
      final choice = (body['choices'] as List?)?.firstOrNull;
      if (choice is! Map || choice['message']?['content'] is! String) {
        throw const FormatException(
          'O modelo não retornou texto. Selecione outro modelo.',
        );
      }
      if (choice['finish_reason'] == 'length') {
        throw const FormatException(
          'Resposta cortada pelo limite de tokens. Aumente o limite ou reduza posts/respostas.',
        );
      }
      final text = (choice['message']['content'] as String).trim();
      if (text.isEmpty) {
        throw const FormatException('O modelo retornou uma resposta vazia.');
      }
      final usage = body['usage'] as Map? ?? {};
      return AIResponse(
        text,
        (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
        (usage['completion_tokens'] as num?)?.toInt() ?? 0,
      );
    } on TimeoutException {
      throw const FormatException(
        'A IA excedeu o tempo de espera. O aplicativo não enviou outra solicitação automaticamente.',
      );
    } on SocketException {
      throw const FormatException(
        'Sem conexão com o OpenRouter. Tente novamente quando a conexão voltar.',
      );
    } on http.ClientException catch (error) {
      throw FormatException(
        'Falha na conexão com o OpenRouter: ${error.message}',
      );
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> body;
    try {
      body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw FormatException(
        'Resposta inválida do OpenRouter (HTTP ${response.statusCode}).',
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['error'] != null) {
      final message = switch (response.statusCode) {
        401 || 403 => 'Chave de API inválida ou sem permissão.',
        402 => 'Saldo insuficiente no OpenRouter para o modelo escolhido.',
        429 => 'Limite de requisições do modelo atingido. Tente mais tarde.',
        408 || 504 => 'O provedor do modelo excedeu o tempo de espera. Tente novamente mais tarde ou escolha outro modelo.',
        _ =>
          body['error'] is Map
              ? body['error']['message']?.toString()
              : 'Falha no OpenRouter (HTTP ${response.statusCode}).',
      };
      throw FormatException(
        (message ?? 'Falha no OpenRouter.').replaceAll(
          RegExp(r'sk-[A-Za-z0-9_-]+'),
          '[chave]',
        ),
      );
    }
    return body;
  }
}
