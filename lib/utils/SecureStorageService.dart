import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  static Future<String?> readOpenRouterApiKey() =>
      _storage.read(key: 'openrouter_api_key');
  static Future<void> writeOpenRouterApiKey(String value) =>
      _storage.write(key: 'openrouter_api_key', value: value.trim());
  static Future<void> deleteOpenRouterApiKey() =>
      _storage.delete(key: 'openrouter_api_key');
  static Future<String?> readOpenRouterModel() =>
      _storage.read(key: 'openrouter_model');
  static Future<void> writeOpenRouterModel(String value) =>
      _storage.write(key: 'openrouter_model', value: value.trim());
  static Future<void> deleteOpenRouterModel() =>
      _storage.delete(key: 'openrouter_model');
}
