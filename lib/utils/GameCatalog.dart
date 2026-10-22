import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/ClubCustomizationModel.dart';
import '../models/CustomClub.dart';
import '../models/CustomLeague.dart';
import 'databaseUtils.dart';
import 'BackgroundData.dart';
import 'CompetitionTrophies.dart';

class CatalogItem {
  const CatalogItem(
    this.id,
    this.label, {
    this.leagueId,
    this.assetPath,
    this.imageUrl,
    this.imagePath,
    this.isCustom = false,
    this.isWoman = false,
    this.fifaVersion,
    this.customizationId,
    this.clubIdentity,
  });
  final String id, label;
  final String? leagueId, assetPath;

  final String? imageUrl, imagePath;

  final bool isCustom;
  final bool isWoman;

  final String? fifaVersion;

  final String? customizationId;

  final String? clubIdentity;
  bool get isSupplementalClub =>
      !isCustom &&
      const {'100', '101', '102'}.contains(leagueId) &&
      const {'100', '101', '102'}.contains(id.split('-').first);

  factory CatalogItem.fromJson(Map<String, dynamic> row) => CatalogItem(
    row['id'].toString(),
    row['label'].toString(),
    leagueId: row['leagueId']?.toString(),
    assetPath: row['assetPath']?.toString(),
    imageUrl: row['imageUrl']?.toString(),
    clubIdentity: (row['clubIdentity'] ?? row['sofifaId'])?.toString(),
  );

  CatalogItem _customized(ClubCustomizationModel customization) => CatalogItem(
    id,
    customization.clubName,
    leagueId: leagueId,
    assetPath: assetPath,
    imageUrl: customization.imageUrl ?? imageUrl,
    imagePath: customization.imagePath ?? imagePath,
    isCustom: isCustom,
    isWoman: isWoman,
    fifaVersion: fifaVersion,
    customizationId: customization.id,
    clubIdentity: clubIdentity,
  );
}

class AwardCatalogItem extends CatalogItem {
  const AwardCatalogItem(
    super.id,
    super.label, {
    this.imageName,
    super.imagePath,
    super.imageUrl,
    super.assetPath,
  });
  final String? imageName;
  factory AwardCatalogItem.fromJson(Map<String, dynamic> row) =>
      AwardCatalogItem(
        row['id'].toString(),
        row['label'].toString(),
        imageName: row['imageName'] as String?,
      );
}

class CatalogLeague {
  const CatalogLeague(this.league, this.teams);
  final CatalogItem league;
  final List<CatalogItem> teams;
  String get id => league.id;
  String get label => league.label;
  bool get isCustom => league.isCustom;
  bool get isWoman => league.isWoman;
}

class GameCatalog {
  GameCatalog._(this._json);
  final Map<String, dynamic> _json;
  static GameCatalog? _cached;
  static Future<GameCatalog>? _loading;
  static Map<String, dynamic>? _tournamentJson;
  static List<AwardCatalogItem>? _awards;

  static const fifaVersions = ['FC27', 'FC26', 'FC25', 'FC24', 'FIFA23'];

  static final ValueNotifier<int> customDataRevision = ValueNotifier(0);

  static GameCatalog? get current => _cached;

  final Map<String, List<CatalogItem>> _baseTeams = {};
  final Map<String, List<CatalogItem>> _baseLeagues = {};
  final Map<String, Map<String, CatalogItem>> _baseTeamIndexes = {};
  final Map<String, _VersionIndex> _indexes = {};
  List<CustomLeague> _customLeagues = const [];
  List<CompetitionTrophy> _competitionTrophies = const [];
  List<CustomClub> _customClubs = const [];
  Map<String, ClubCustomizationModel> _customizations = const {};

  static Future<GameCatalog> load() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<GameCatalog> _load() async {
    final source = await rootBundle.loadString(
      'assets/game_catalog.json',
      cache: false,
    );
    final catalog = GameCatalog._(
      await BackgroundData.jsonString(source) as Map<String, dynamic>,
    );
    await catalog._loadCustomData();
    return _cached = catalog;
  }

  static Future<void> reloadCustomData() async {
    final catalog = _cached;
    if (catalog != null) await catalog._loadCustomData();
    customDataRevision.value++;
  }

  Future<void> _loadCustomData() async {
    try {
      final leagues = await CustomContentService.getCustomLeagues();
      final clubs = await CustomContentService.getCustomClubs();
      final customizations = await CustomContentService.getClubCustomizations();
      _competitionTrophies = await CompetitionTrophies.all();
      _customLeagues = List.unmodifiable(leagues);
      _customClubs = List.unmodifiable(clubs);
      _customizations = Map.unmodifiable({
        for (final item in customizations) item.id: item,
      });
    } catch (error) {
      debugPrint('Conteúdo personalizado indisponível: $error');
    }
    try {
      await CustomImageFiles.docsDir();
    } catch (error) {
      debugPrint('Diretório de documentos indisponível: $error');
    }
    _indexes.clear();
  }

  @visibleForTesting
  void debugSetCustomData({
    List<CustomLeague> leagues = const [],
    List<CustomClub> clubs = const [],
    List<ClubCustomizationModel> customizations = const [],
  }) {
    _customLeagues = List.unmodifiable(leagues);
    _customClubs = List.unmodifiable(clubs);
    _customizations = Map.unmodifiable({
      for (final item in customizations) item.id: item,
    });
    _indexes.clear();
  }

  List<CatalogItem> _items(Object? rows) => (rows as List<dynamic>? ?? [])
      .map((row) => CatalogItem.fromJson(row as Map<String, dynamic>))
      .toList();

  List<CatalogItem> _versionItems(
    Map<String, List<CatalogItem>> cache,
    String version,
    String key,
  ) => cache[version] ??= List.unmodifiable(
    key == 'teams'
        ? _teamItems((_json[version] as Map<String, dynamic>?)?[key])
        : _items((_json[version] as Map<String, dynamic>?)?[key]),
  );

  List<CatalogItem> _teamItems(Object? rows) {
    final items = _items(rows);
    final originals = <String, List<CatalogItem>>{};
    String name(CatalogItem item) => item.label.trim().toLowerCase();
    for (final item in items.where((t) => !t.isSupplementalClub)) {
      (originals[name(item)] ??= []).add(item);
    }
    return [
      for (final item in items)
        CatalogItem(
          item.id,
          item.label,
          leagueId: item.leagueId,
          assetPath: item.assetPath,
          imageUrl: item.imageUrl,
          imagePath: item.imagePath,
          clubIdentity:
              item.clubIdentity ??
              (item.isSupplementalClub && originals[name(item)]?.length == 1
                  ? (originals[name(item)]!.single.clubIdentity ??
                        originals[name(item)]!.single.id)
                  : item.id),
        ),
    ];
  }

  List<CatalogItem> get nationalities => _items(_json['nationalities']);
  List<CatalogItem> get positions => _items(_json['positions']);

  List<CatalogItem> catalogTeams(String version) =>
      List.of(_versionItems(_baseTeams, version, 'teams'));

  List<CatalogItem> catalogLeagues(String version) =>
      List.of(_versionItems(_baseLeagues, version, 'leagues'));

  List<CatalogItem> teams(String version) =>
      List.of(_index(version).teamsById.values);

  List<CatalogItem> leagues(String version) =>
      _index(version).leagues.map((entry) => entry.league).toList();

  List<CustomLeague> get customLeagues => _customLeagues;
  List<CustomClub> get customClubs => _customClubs;
  List<ClubCustomizationModel> get clubCustomizations =>
      List.unmodifiable(_customizations.values);

  List<ClubCustomizationModel> customizationsFor(String version) =>
      _customizations.values
          .where((item) => item.fifaVersion == version)
          .toList();

  ClubCustomizationModel? customization(
    String version,
    String? leagueId,
    String teamId,
  ) =>
      _customizations[ClubCustomizationModel.buildId(
        version,
        leagueId,
        teamId,
      )];

  List<CatalogLeague> getAllLeagues([String? version]) {
    if (version != null) return List.of(_index(version).leagues);
    final result = <String, CatalogLeague>{};
    for (final item in fifaVersions) {
      for (final entry in _index(item).leagues) {
        final previous = result[entry.id];
        final teams = <String, CatalogItem>{
          for (final team in previous?.teams ?? const <CatalogItem>[])
            team.id: team,
        };
        for (final team in entry.teams) {
          if (team.isCustom || teams[team.id]?.isCustom != true) {
            teams[team.id] = team;
          }
        }
        result[entry.id] = CatalogLeague(
          previous?.league ?? entry.league,
          teams.values.toList()..sort((a, b) => a.label.compareTo(b.label)),
        );
      }
    }
    return result.values.toList();
  }

  List<CatalogLeague> customLeagueEntries() => [
    for (final league in _customLeagues)
      CatalogLeague(_customLeagueItem(league), _teamsOf(league.id, const [])),
  ];

  List<CustomClub> customClubsOf(String leagueId) =>
      _customClubs.where((club) => club.leagueId == leagueId).toList();

  CustomLeague? customLeague(String id) =>
      _customLeagues.where((league) => league.id == id).firstOrNull;

  CustomClub? customClub(String id) =>
      _customClubs.where((club) => club.id == id).firstOrNull;

  CatalogItem? team(
    String version,
    String id, {
    String? leagueId,
    bool ignoreCustomizations = false,
  }) {
    if (ignoreCustomizations) {
      final base = _baseTeamIndex(version)[id];
      if (base != null) return base;
    } else {
      if (leagueId != null) {
        for (final league in _index(
          version,
        ).leagues.where((l) => l.id == leagueId)) {
          final exact = league.teams.where((t) => t.id == id).firstOrNull;
          if (exact != null) return exact;
        }
      }
      final indexed = _index(version).teamsById[id];
      if (indexed != null) return indexed;
    }
    final club = customClub(id);
    if (club != null) return _customClubItem(club);
    if (ignoreCustomizations) return null;
    final custom = customization(version, leagueId, id);
    if (custom != null) {
      return CatalogItem(
        id,
        custom.clubName,
        leagueId: leagueId,
        imageUrl: custom.imageUrl,
        imagePath: custom.imagePath,
        customizationId: custom.id,
      );
    }
    return leagueId == nationalLeagueId ? nationalTeam(id) : null;
  }

  static const nationalLeagueId = 'nat';

  CatalogItem? nationalTeam(String id) {
    final item = nationalities.where((entry) => entry.id == id).firstOrNull;
    return item == null
        ? null
        : CatalogItem(
            id,
            'countries.${item.label}'.tr(),
            leagueId: nationalLeagueId,
            imageUrl: item.imageUrl,
          );
  }

  String teamLabel(String version, String id, {String? leagueId}) =>
      team(version, id, leagueId: leagueId)?.label ?? id;

  ({String? imageUrl, String? imagePath}) teamLogo(
    String version,
    String teamId, {
    String? leagueId,
  }) {
    final item = team(version, teamId, leagueId: leagueId);
    return (imageUrl: item?.imageUrl, imagePath: item?.imagePath);
  }

  CatalogItem? league(String version, String id) {
    for (final entry in _index(version).leagues) {
      if (entry.id == id) return entry.league;
    }
    final custom = customLeague(id);
    return custom == null ? null : _customLeagueItem(custom);
  }

  String leagueLabel(String version, String id) =>
      league(version, id)?.label ?? id;

  Future<List<CatalogItem>> tournaments(String version) async {
    _tournamentJson ??= jsonDecode(
      await rootBundle.loadString('assets/game_tournaments.json'),
    ) as Map<String, dynamic>;
    return _items(_tournamentJson![version]);
  }

  Future<List<AwardCatalogItem>> awards() async {
    if (_awards == null) {
      final source = await rootBundle.loadString('assets/game_awards.json');
      _awards = (jsonDecode(source) as List<dynamic>)
          .map((row) => AwardCatalogItem.fromJson(row as Map<String, dynamic>))
          .toList();
    }
    final linked = _competitionTrophies;
    return [
      ..._awards!,
      for (final trophy in linked)
        AwardCatalogItem(
          trophy.awardId,
          trophy.name,
          imagePath: trophy.imagePath,
          imageUrl: trophy.imageUrl,
        ),
    ];
  }

  Map<String, CatalogItem> _baseTeamIndex(String version) =>
      _baseTeamIndexes[version] ??= {
        for (final item in _versionItems(_baseTeams, version, 'teams'))
          item.id: item,
      };

  _VersionIndex _index(String version) =>
      _indexes[version] ??= _buildIndex(version);

  _VersionIndex _buildIndex(String version) {
    final byLeague = <String, List<CatalogItem>>{};
    for (final team in _versionItems(_baseTeams, version, 'teams')) {
      final custom = customization(version, team.leagueId, team.id);
      (byLeague[team.leagueId ?? ''] ??= []).add(
        custom == null ? team : team._customized(custom),
      );
    }
    final leagues = <CatalogLeague>[
      for (final league in _versionItems(_baseLeagues, version, 'leagues'))
        CatalogLeague(
          league,
          _teamsOf(league.id, byLeague[league.id] ?? [], version: version),
        ),
      for (final league in _customLeagues)
        if (league.fifaVersions.contains(version) &&
            !_versionItems(
              _baseLeagues,
              version,
              'leagues',
            ).any((base) => base.id == league.id))
          CatalogLeague(
            _customLeagueItem(league),
            _teamsOf(league.id, const [], version: version),
          ),
    ];
    final teamsById = <String, CatalogItem>{};
    for (final entry in leagues) {
      for (final team in entry.teams) {
        teamsById.putIfAbsent(team.id, () => team);
      }
    }
    for (final teams in byLeague.values) {
      for (final team in teams) {
        teamsById.putIfAbsent(team.id, () => team);
      }
    }
    return _VersionIndex(List.unmodifiable(leagues), teamsById);
  }

  List<CatalogItem> _teamsOf(
    String leagueId,
    List<CatalogItem> catalog, {
    String? version,
  }) {
    final seen = <String>{};
    final teams = <CatalogItem>[
      for (final team in catalog)
        if (seen.add(team.id)) team,
      for (final club in _customClubs)
        if (club.leagueId == leagueId &&
            (version == null || club.fifaVersions.contains(version)) &&
            seen.add(club.id))
          _customClubItem(club),
    ];
    teams.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return List.unmodifiable(teams);
  }

  static CatalogItem _customLeagueItem(CustomLeague league) => CatalogItem(
    league.id,
    league.label,
    imageUrl: league.imageUrl,
    imagePath: league.imagePath,
    isCustom: true,
    isWoman: league.isWoman,
    fifaVersion: league.fifaVersion,
  );

  static CatalogItem _customClubItem(CustomClub club) => CatalogItem(
    club.id,
    club.label,
    leagueId: club.leagueId,
    imageUrl: club.imageUrl,
    imagePath: club.imagePath,
    isCustom: true,
    fifaVersion: club.fifaVersion,
  );
}

class _VersionIndex {
  const _VersionIndex(this.leagues, this.teamsById);
  final List<CatalogLeague> leagues;
  final Map<String, CatalogItem> teamsById;
}
