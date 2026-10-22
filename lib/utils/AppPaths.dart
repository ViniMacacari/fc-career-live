import 'package:path_provider/path_provider.dart';

abstract class AppPaths {
  static String? _appDir;

  static String get appDir {
    final dir = _appDir;
    if (dir == null) {
      throw StateError('AppPaths.init() ainda não foi chamado.');
    }
    return dir;
  }

  static bool get isInitialized => _appDir != null;

  static Future<void> init() async {
    _appDir = (await getApplicationDocumentsDirectory()).path;
  }

  static String absolute(String relativePath) => '$appDir$relativePath';
}
