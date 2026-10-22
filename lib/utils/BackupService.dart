import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'SqlService.dart';
import 'BackupAppSettings.dart';
import 'GameCatalog.dart';

class OtherAppBackupException implements Exception {
  const OtherAppBackupException();
}

class RestoreReport {
  RestoreReport({required this.backupVersion, required this.fromOtherApp});

  final int backupVersion;
  final bool fromOtherApp;
  int tablesRestored = 0;
  int rowsRestored = 0;
  int skippedRows = 0;
  final List<String> skippedTables = [];
  final Map<String, Set<String>> skippedColumns = {};
  final List<String> restoredImageFolders = [];
  int preferencesRestored = 0;
  int secureSettingsRestored = 0;
  BackupAppSettings? _appSettings;

  @override
  String toString() =>
      'RestoreReport(version: $backupVersion, otherApp: $fromOtherApp, '
      'tables: $tablesRestored, rows: $rowsRestored, '
      'skippedRows: $skippedRows, skippedTables: $skippedTables, '
      'skippedColumns: $skippedColumns, images: $restoredImageFolders, '
      'preferences: $preferencesRestored, secureSettings: $secureSettingsRestored)';
}

class BackupService {
  BackupService({
    Future<Database> Function()? database,
    this.tableNames,
    this.imageFolders = defaultImageFolders,
  }) : _database = database ?? (() => SqlService.instance.database);

  static const String backupAesKey = 'qwertyuikjgnmspw';

  static const List<String> defaultImageFolders = [
    'faces',
    'holderFaces',
    'moments',
    'leagues',
    'teams',
    'tournaments',
    'trophies',
    'person_faces',
    'team_customizations',
    'twitter_faces',
  ];

  static const String appMarker = 'mc_ea_rebuild';

  final Future<Database> Function() _database;

  final List<String>? tableNames;
  final List<String> imageFolders;

  Future<String> generateBackup({bool includeImages = true}) async {
    final baseDir = await _backupBaseDirectory();
    final db = await _database();
    final settings = await BackupAppSettings.capture();
    final snapshot = await db.transaction((txn) async {
      final tables = tableNames ?? await _userTables(txn);
      final rows = <List<Map<String, Object?>>>[];
      for (final table in tables) {
        rows.add(await txn.query(table));
      }
      final version =
          Sqflite.firstIntValue(await txn.rawQuery('PRAGMA user_version')) ?? 0;
      return (tables: tables, rows: rows, version: version);
    });
    final payload = jsonEncode([
      snapshot.tables,
      snapshot.rows,
      snapshot.version,
      {
        'app': appMarker,
        'dbVersion': snapshot.version,
        ...settings.toMetadata(),
      },
    ]);

    final tempDir = Directory('$baseDir/temp_backup');
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    tempDir.createSync(recursive: true);
    await File('${tempDir.path}/backup.json')
        .writeAsString(payload, flush: true);

    if (includeImages) {
      final docs = (await getApplicationDocumentsDirectory()).path;
      for (final folder in imageFolders) {
        final source = Directory('$docs/$folder');
        if (source.existsSync()) {
          copyDirectory(source, Directory('${tempDir.path}/$folder'));
        }
      }
    }

    final backupsDir = Directory('$baseDir/backups');
    if (!backupsDir.existsSync()) backupsDir.createSync(recursive: true);
    final now = DateTime.now();
    final club = await _backupClubName(snapshot.tables, snapshot.rows);
    final zipPath = '${backupsDir.path}/${backupFileName(now, club)}';
    final encoder = ZipFileEncoder()..create(zipPath);
    await encoder.addDirectory(tempDir);
    await encoder.close();
    tempDir.deleteSync(recursive: true);
    return zipPath;
  }

  String encryptPayload(String plain) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypted = _encrypter().encrypt(plain, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  String decryptPayload(String payload) {
    if (!looksEncrypted(payload)) return payload;
    final parts = payload.split(':');
    final iv = enc.IV.fromBase64(parts[0]);
    return _encrypter().decrypt(enc.Encrypted.fromBase64(parts[1]), iv: iv);
  }

  static bool looksEncrypted(String content) {
    final text = content.trimLeft();
    return text.contains(':') && !text.startsWith('[') && !text.startsWith('{');
  }

  enc.Encrypter _encrypter() => enc.Encrypter(
    enc.AES(enc.Key.fromUtf8(backupAesKey), mode: enc.AESMode.cbc),
  );

  static String backupFileName(DateTime time, String club) {
    String two(int n) => '$n'.padLeft(2, '0');
    final stamp =
        '${time.year}-${two(time.month)}-${two(time.day)}_'
        '${two(time.hour)}-${two(time.minute)}-${two(time.second)}';
    final name = club
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return 'carreira_${stamp}_${name.isEmpty ? 'clube' : name}.zip';
  }

  Future<String> _backupClubName(
    List<String> tables,
    List<List<Map<String, Object?>>> data,
  ) async {
    List<Map<String, Object?>> rows(String table) {
      final index = tables.indexOf(table);
      return index < 0 ? const [] : data[index];
    }

    final active = rows('Settings').firstOrNull?['activePersonId'];
    final person =
        rows('Persons').where((p) => p['id'] == active).firstOrNull ??
        rows('Persons').firstOrNull;
    if (person == null) return 'clube';
    final teamId = '${person['teamId']}';
    final custom = rows('CustomClub')
        .where((c) => c['id'] == teamId)
        .firstOrNull;
    if (custom?['label'] case final String label when label.trim().isNotEmpty) {
      return label;
    }
    final customization = rows('ClubCustomizationModel')
        .where(
          (c) =>
              c['teamId'] == teamId &&
              c['fifaVersion'] == person['fifaVersion'],
        )
        .firstOrNull;
    if (customization?['clubName'] case final String label
        when label.trim().isNotEmpty) {
      return label;
    }
    try {
      final catalog = await GameCatalog.load();
      return catalog.teamLabel(
        '${person['fifaVersion']}',
        teamId,
        leagueId: person['leagueId'] as String?,
      );
    } catch (_) {
      return teamId;
    }
  }

  Future<RestoreReport> restoreBackup(
    String filePath, {
    bool allowOtherApps = true,
  }) {
    if (filePath.toLowerCase().endsWith('.zip')) {
      return _restoreZipBackup(filePath, allowOtherApps: allowOtherApps);
    }
    return _restoreTextBackup(filePath, allowOtherApps: allowOtherApps);
  }

  Future<RestoreReport> _restoreTextBackup(
    String filePath, {
    required bool allowOtherApps,
  }) => _restoreJsonBackup(
    File(filePath).readAsStringSync(),
    allowOtherApps: allowOtherApps,
  );

  Future<RestoreReport> _restoreZipBackup(
    String filePath, {
    required bool allowOtherApps,
  }) async {
    final docs = (await getApplicationDocumentsDirectory()).path;
    final restoreDir = Directory('$docs/restore_temp');
    if (restoreDir.existsSync()) restoreDir.deleteSync(recursive: true);
    restoreDir.createSync(recursive: true);
    try {
      final archive = ZipDecoder().decodeBytes(
        File(filePath).readAsBytesSync(),
      );
      final root = p.normalize(restoreDir.absolute.path);
      for (final file in archive) {
        final target = p.normalize(p.join(root, file.name));
        if (!p.isWithin(root, target)) continue;
        if (file.isFile) {
          final out = File(target);
          out.parent.createSync(recursive: true);
          out.writeAsBytesSync(file.readBytes() ?? Uint8List(0));
        } else {
          Directory(target).createSync(recursive: true);
        }
      }
      final json = File('${restoreDir.path}/temp_backup/backup.json');
      final report = await _restoreJsonBackup(
        json.readAsStringSync(),
        deferSharedPlayers: true,
        allowOtherApps: allowOtherApps,
      );

      final extracted = Directory('${restoreDir.path}/temp_backup');
      for (final entity in extracted.listSync()) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (!imageFolders.contains(name)) continue;
        final destination = Directory('$docs/$name');
        if (destination.existsSync()) destination.deleteSync(recursive: true);
        copyDirectory(entity, destination);
        report.restoredImageFolders.add(name);
      }
      await (await _database()).transaction(SqlService.seedSharedPlayers);
      await _restoreAppSettings(report);
      return report;
    } finally {
      if (restoreDir.existsSync()) restoreDir.deleteSync(recursive: true);
    }
  }

  Future<RestoreReport> restoreJsonBackup(String content) =>
      _restoreJsonBackup(content);

  Future<RestoreReport> _restoreJsonBackup(
    String content, {
    bool deferSharedPlayers = false,
    bool allowOtherApps = true,
  }) async {
    final text = content.trim();
    final decoded = jsonDecode(
      looksEncrypted(text) ? decryptPayload(text) : text,
    );
    if (decoded is! List || decoded.length < 3) {
      throw const FormatException('Backup inválido.');
    }
    final tables = (decoded[0] as List).map((t) => t as String).toList();
    final data = decoded[1] as List;
    final backupVersion = (decoded[2] as num).toInt();
    final marker = decoded.length > 3 ? decoded[3] : null;
    final fromThisApp = marker is Map && marker['app'] == appMarker;
    if (!fromThisApp && !allowOtherApps) throw const OtherAppBackupException();
    final report = RestoreReport(
      backupVersion: backupVersion,
      fromOtherApp: !fromThisApp,
    );
    report._appSettings = fromThisApp
        ? BackupAppSettings.fromMetadata(marker)
        : null;

    final db = await _database();
    final schema = await _schema(db);
    final batch = db.batch();
    for (final table in schema.keys) {
      batch.delete(table);
    }
    for (var i = 0; i < tables.length && i < data.length; i++) {
      final table = tables[i];
      final columns = schema[table];
      if (columns == null) {
        report.skippedTables.add(table);
        continue;
      }
      report.tablesRestored++;
      for (final rawRow in data[i] as List) {
        final row = <String, Object?>{};
        (rawRow as Map).forEach((key, value) {
          final column = key as String;
          if (columns.containsKey(column)) {
            row[column] = _sqlValue(value);
          } else {
            report.skippedColumns.putIfAbsent(table, () => {}).add(column);
          }
        });
        final missingRequired = columns.values.any(
          (c) => c.required && row[c.name] == null,
        );
        if (row.isEmpty || missingRequired) {
          report.skippedRows++;
          continue;
        }
        batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
        report.rowsRestored++;
      }
    }
    await batch.commit(noResult: true, continueOnError: false);

    if (!fromThisApp) {
      await _applyOtherAppMigrations(db, schema, backupVersion);
    }
    await _ensureSettingsRow(db, schema);
    if (!deferSharedPlayers) {
      await db.transaction(SqlService.seedSharedPlayers);
      await _restoreAppSettings(report);
    }
    return report;
  }

  Future<void> _applyOtherAppMigrations(
    Database db,
    Map<String, Map<String, _Column>> schema,
    int backupVersion,
  ) async {
    bool has(String table, String column) =>
        schema[table]?.containsKey(column) ?? false;
    if (backupVersion < 3 && has('CustomCreatedPlayer', 'firstSeasonAge')) {
      await db.rawUpdate('UPDATE CustomCreatedPlayer SET firstSeasonAge = ?', [
        0,
      ]);
    }
    if (backupVersion < 4 && has('TournamentResult', 'youParticipatedIn')) {
      await db.rawUpdate('UPDATE TournamentResult SET youParticipatedIn = ?', [
        1,
      ]);
    }
    if (backupVersion < 12) {
      if (has('Persons', 'promotedYoungPlayersCount')) {
        await db.rawUpdate('UPDATE Persons SET promotedYoungPlayersCount = ?', [
          0,
        ]);
      }
      if (has('GlobalAward', 'type') && has('GlobalAward', 'awardLeagueId')) {
        await db.rawUpdate(
          'UPDATE GlobalAward SET type = ? WHERE awardLeagueId IS NOT NULL',
          ['PlayerOfTheMonth'],
        );
      }
    }
    if (backupVersion < 15 && has('AcademyPlayer', 'isHistorical')) {
      await db.rawUpdate('UPDATE AcademyPlayer SET isHistorical = ?', [0]);
    }
    if (backupVersion < 17 &&
        has('Seasons', 'createdAt') &&
        has('Seasons', 'startDate')) {
      await db.rawUpdate(
        'UPDATE Seasons SET createdAt = startDate WHERE createdAt IS NULL',
      );
    }
  }

  Future<void> _ensureSettingsRow(
    Database db,
    Map<String, Map<String, _Column>> schema,
  ) async {
    if (!schema.containsKey('Settings')) return;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM Settings'),
    );
    if ((count ?? 0) == 0) {
      await db.rawInsert('INSERT INTO Settings DEFAULT VALUES');
    }
  }

  Future<void> _restoreAppSettings(RestoreReport report) async {
    final settings = report._appSettings;
    if (settings == null) return;
    await settings.restore();
    report.preferencesRestored = settings.preferences?.length ?? 0;
    report.secureSettingsRestored = settings.secureSettings?.length ?? 0;
  }

  Future<String> _backupBaseDirectory() async {
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) return external.path;
    } catch (_) {}
    return (await getApplicationDocumentsDirectory()).path;
  }

  static Future<List<String>> _userTables(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
      'ORDER BY name',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  static Future<Map<String, Map<String, _Column>>> _schema(Database db) async {
    final schema = <String, Map<String, _Column>>{};
    for (final table in await _userTables(db)) {
      final info = await db.rawQuery('PRAGMA table_info("$table")');
      schema[table] = {
        for (final c in info)
          c['name'] as String: _Column(
            c['name'] as String,
            required:
                c['notnull'] == 1 && c['dflt_value'] == null && c['pk'] == 0,
          ),
      };
    }
    return schema;
  }

  static Object? _sqlValue(Object? value) {
    if (value is bool) return value ? 1 : 0;
    if (value is List) {
      return value.every((e) => e is int)
          ? Uint8List.fromList(value.cast<int>())
          : jsonEncode(value);
    }
    if (value is Map) return jsonEncode(value);
    return value;
  }

  static void copyDirectory(Directory source, Directory destination) {
    if (!destination.existsSync()) destination.createSync(recursive: true);
    for (final entity in source.listSync()) {
      final target = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        entity.copySync(target);
      }
    }
  }
}

class _Column {
  const _Column(this.name, {required this.required});
  final String name;

  final bool required;
}
