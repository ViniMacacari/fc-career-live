import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/BackgroundData.dart';

typedef FcJson = Map<String, dynamic>;
FcJson fcObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<FcJson> fcList(Object? value) =>
    value is List ? value.whereType<Map>().map(fcObject).toList() : <FcJson>[];
int? fcInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
double? fcNumber(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');
String fcId(Object? value) => value == null ? '' : '$value';
String fcName(Object? value, [String fallback = 'Não informado']) {
  if (value is String && value.trim().isNotEmpty) return value;
  final map = fcObject(value);
  final nested = map['displayName'] ?? map['name'];
  return nested == null ? fallback : fcName(nested, fallback);
}

class FcScoreException implements Exception {
  const FcScoreException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

Uri fcScoreAddress(String input, {int port = 38291}) {
  final text = input.trim();
  if (text.isEmpty) throw const FcScoreException('Informe o IP do computador.');
  final uri = Uri.tryParse(text.contains('://') ? text : 'http://$text');
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !['', '/', '/api', '/api/'].contains(uri.path)) {
    throw const FcScoreException('Use um IP ou endereço como 192.168.0.20.');
  }
  if (port < 1 ||
      port > 65535 ||
      (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
    throw const FcScoreException('A porta deve estar entre 1 e 65535.');
  }
  return uri.replace(port: uri.hasPort ? uri.port : port, path: '/api');
}

class FcScoreApi {
  FcScoreApi(
    this.address, {
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();
  final Uri address;
  final http.Client _client;
  final Duration timeout;
  void close() => _client.close();

  Future<Object?> request(
    String path, {
    Map<String, String>? query,
    FcJson? body,
  }) async {
    final uri = address.replace(
      path: '${address.path}/$path',
      queryParameters: query,
    );
    try {
      final response =
          await (body == null
                  ? _client.get(uri, headers: {'Accept': 'application/json'})
                  : _client.post(
                      uri,
                      headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json',
                      },
                      body: jsonEncode(body),
                    ))
              .timeout(timeout);
      Object? data;
      try {
        data = await BackgroundData.jsonBytes(response.bodyBytes);
      } catch (_) {
        throw const FcScoreException(
          'O computador respondeu com dados inválidos. Confira o endereço da API.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = fcObject(fcObject(data)['error']);
        final code = fcId(error['code']);
        final message = response.statusCode == 503
            ? (code.contains('PERFORMANCE')
                  ? 'A pasta de relatórios de partidas não está disponível no PC.'
                  : 'A pasta de saves não está disponível no PC.')
            : response.statusCode == 404
            ? 'O arquivo ou relatório não foi encontrado na API.'
            : response.statusCode == 422
            ? 'A API não conseguiu ler este arquivo.'
            : fcName(error['message'], 'Não foi possível consultar a API.');
        throw FcScoreException(message, status: response.statusCode);
      }
      return data;
    } on TimeoutException {
      throw const FcScoreException(
        'O PC demorou a responder. Confira a conexão e tente novamente.',
      );
    } on FcScoreException {
      rethrow;
    } catch (_) {
      throw const FcScoreException(
        'Não foi possível alcançar o PC. Confira o IP, a API aberta e a conexão de rede ou USB.',
      );
    }
  }

  Future<FcJson> object(String path, {Map<String, String>? query}) async {
    final value = await request(path, query: query);
    if (value is! Map) {
      throw const FcScoreException(
        'A resposta da API está em um formato inesperado.',
      );
    }
    return fcObject(value);
  }

  Future<List<FcJson>> list(String path) async {
    final value = await request(path);
    if (value is! List) {
      throw const FcScoreException(
        'A resposta da API está em um formato inesperado.',
      );
    }
    return fcList(value);
  }

  String careerPath(String saveId, [String suffix = '']) =>
      'careers/${Uri.encodeComponent(saveId)}${suffix.isEmpty ? '' : '/$suffix'}';
  Future<FcJson> connect() async {
    if ((await object('health'))['status'] != 'ok') {
      throw const FcScoreException(
        'Este endereço não é uma API FC Score disponível.',
      );
    }
    final meta = await object('meta');
    if (meta['gameVersion'] is! String) {
      throw const FcScoreException('A API não informou a versão do jogo.');
    }
    return meta;
  }

  Future<FcJson> report(String saveId, [String id = 'latest']) async {
    await request('set-file', body: {'saveId': saveId});
    final result = await object('matches/${Uri.encodeComponent(id)}');
    if (fcObject(result['activeSave'])['id'] != saveId) {
      throw const FcScoreException(
        'O save ativo mudou no PC. Selecione a carreira novamente antes de importar.',
      );
    }
    return result;
  }
}
