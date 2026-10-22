import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void mockBackupStorage({
  Map<String, Object> preferences = const {},
  Map<String, String> secure = const {},
}) {
  SharedPreferences.setMockInitialValues(preferences);
  FlutterSecureStorage.setMockInitialValues(Map<String, String>.of(secure));
}
