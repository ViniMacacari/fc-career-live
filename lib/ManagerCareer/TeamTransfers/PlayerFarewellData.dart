import 'dart:convert';

import '../../Common/FixtureResultTile.dart';
import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../models/TeamTransferItem.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../TeamPage/ViewPlayer/PlayerProfileData.dart';

class PlayerFarewellData {
  PlayerFarewellData.fromRecords({
    required this.person,
    required this.transfer,
    required this.player,
    required this.clubName,
    required this.destinationName,
    required List<Map<String, Object?>> matchRows,
    this.seasons = const [],
    this.recordsAvailable = true,
    this.teamNames = const {},
  }) {
    final seen = <String>{};
    matches =
        matchRows
            .where((row) {
              final date = DateTime.tryParse('${row['date'] ?? ''}');
              final id = row['fixtureId']?.toString();
              return row['personId'] == person.id &&
                  row['playerInstanceId'] == playerId &&
                  row['playerTeamId'] == clubId &&
                  date != null &&
                  !dateOnly(date).isAfter(dateOnly(agreementDate)) &&
                  id != null &&
                  seen.add(id);
            })
            .map(PlayerMatchData.new)
            .toList()
          ..sort((a, b) => a.date!.compareTo(b.date!));
    for (final match in matches) {
      match.performance.goalsCount ??= match.performance.goalDetails.length;
      match.performance.assistsCount ??= match.performance.assistDetails.length;
    }
    totals = PlayerTotals(matches);
  }

  final Person person;
  final Map<String, Object?> transfer, player;
  final String clubName, destinationName;
  final List<Season> seasons;
  final Map<String, String> teamNames;
  final bool recordsAvailable;
  late final List<PlayerMatchData> matches;
  late final PlayerTotals totals;
  String get playerId => '${transfer['playerInstanceId']}';
  String get name => player['name']?.toString() ?? 'Jogador';
  String get clubId => '${transfer['fromTeamId']}';
  String? get clubLeagueId => transfer['fromLeagueId']?.toString();
  String? get destinationId => transfer['toTeamId']?.toString();
  String? get destinationLeagueId => transfer['toLeagueId']?.toString();
  String? get realPlayerId => player['realPlayerId']?.toString();
  String? get photo => player['customAvatarFilePath']?.toString();
  bool get goalkeeper => player['positionId']?.toString() == '0';
  DateTime get agreementDate => DateTime.parse('${transfer['date']}');
  DateTime? get releaseDate => DateTime.tryParse(
    '${transfer['actualReleaseDate'] ?? transfer['releaseDate'] ?? ''}',
  );
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool isClubSale(Map<String, Object?> row, String clubId) =>
      row['fromTeamId'] == clubId &&
      row['toTeamId'] != clubId &&
      const {
        TeamTransferType.sell,
        TeamTransferType.sellFromLoan,
      }.contains(transferTypeFromRow(row));

  static Future<PlayerFarewellData?> load(
    Person person,
    String transferId, {
    SqlService? sql,
    GameCatalog? catalog,
  }) async {
    final service = sql ?? SqlService.instance;
    final db = await service.database;
    final rows = await db.query(
      'TeamTransferItem',
      where: 'personId = ? AND id IN (?, ?)',
      whereArgs: [person.id, transferId, '$transferId:exchange'],
    );
    final sale = rows.where((r) => isClubSale(r, person.teamId)).firstOrNull;
    if (sale == null) return null;
    return _loadMovement(person, sale, service: service, catalog: catalog);
  }

  static Future<PlayerFarewellData> loadDeparture(
    Person person,
    Map<String, Object?> departure, {
    SqlService? sql,
    GameCatalog? catalog,
  }) {
    final linked = departure['transferJson'] == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(
            jsonDecode(departure['transferJson'] as String) as Map,
          );
    return _loadMovement(
      person,
      {
        ...linked,
        'playerInstanceId': departure['playerId'],
        'fromTeamId': departure['teamId'],
        'fromLeagueId': departure['leagueId'],
        'date': departure['departureDate'],
        'actualReleaseDate': departure['departureDate'],
        'rosterDepartureRecord': true,
      },
      service: sql ?? SqlService.instance,
      catalog: catalog,
    );
  }

  static Future<PlayerFarewellData> _loadMovement(
    Person person,
    Map<String, Object?> sale, {
    required SqlService service,
    GameCatalog? catalog,
  }) async {
    final db = await service.database;
    final playerId = sale['playerInstanceId'] as String;
    final results = await Future.wait<Object?>([
      service.getCustomPlayerById(person.id, playerId),
      service.getSeasons(person.id),
      db.rawQuery(
        '''
        SELECT p.*, f.date, f.seasonId, f.playerTeamId, f.oppositeTeamId,
          f.playerTeamScore, f.oppositeTeamScore, f.extraTime,
          f.playerTeamPenaltiesScore, f.oppositeTeamPenaltiesScore,
          f.playerOfTheMatchId, f.isPotmFromMyTeam, f.tournamentId
        FROM ManagerFixturePlayerPerformances p
        JOIN ManagerFixtures f ON f.id = p.fixtureId AND f.personId = p.personId
        WHERE p.personId = ? AND p.playerInstanceId = ? AND f.playerTeamId = ?
          AND substr(f.date, 1, 10) <= ?
          AND p.rowid = (SELECT MAX(d.rowid)
            FROM ManagerFixturePlayerPerformances d
            WHERE d.personId = p.personId AND d.fixtureId = p.fixtureId
              AND d.playerInstanceId = p.playerInstanceId)
        ORDER BY f.date
      ''',
        [
          person.id,
          playerId,
          sale['fromTeamId'],
          '${sale['date']}'.substring(0, 10),
        ],
      ),
    ]);
    final labels = catalog ?? await GameCatalog.load();
    return PlayerFarewellData.fromRecords(
      person: person,
      transfer: sale,
      player: (results[0] as Map<String, Object?>?) ?? {'name': 'Jogador'},
      seasons: results[1] as List<Season>,
      matchRows: results[2] as List<Map<String, Object?>>,
      clubName: labels.teamLabel(person.fifaVersion, '${sale['fromTeamId']}'),
      destinationName: sale['toTeamId'] == null
          ? 'Saída do elenco'
          : labels.teamLabel(person.fifaVersion, '${sale['toTeamId']}'),
      teamNames: {
        for (final team in labels.teams(person.fifaVersion))
          team.id: team.label,
      },
    );
  }

  late final Map<FixtureResult, int> results = _results();
  Map<FixtureResult, int> _results() {
    final counts = {for (final value in FixtureResult.values) value: 0};
    for (final match in matches) {
      if (match.row['playerTeamScore'] == null ||
          match.row['oppositeTeamScore'] == null) {
        continue;
      }
      final result = fixtureResult(match.row);
      counts[result] = counts[result]! + 1;
    }
    return counts;
  }

  late final PlayerMatchData? highlight = _highlight();
  PlayerMatchData? _highlight() {
    final ranked =
        matches
            .where(
              (m) => m.performance.avgRating != null || m.goals + m.assists > 0,
            )
            .toList()
          ..sort((a, b) {
            final rating = (b.performance.avgRating ?? -1).compareTo(
              a.performance.avgRating ?? -1,
            );
            if (rating != 0) return rating;
            final impact = (b.goals + b.assists).compareTo(a.goals + a.assists);
            return impact != 0 ? impact : a.date!.compareTo(b.date!);
          });
    return ranked.firstOrNull;
  }

  late final ({String id, PlayerTotals totals})? bestSeason = _bestSeason();
  ({String id, PlayerTotals totals})? _bestSeason() {
    final grouped = <String, List<PlayerMatchData>>{};
    for (final match in matches) {
      (grouped[match.seasonId] ??= []).add(match);
    }
    final ranked =
        [
          for (final group in grouped.entries)
            (id: group.key, totals: PlayerTotals(group.value)),
        ]..sort((a, b) {
          final impact = goalkeeper
              ? b.totals.saves.compareTo(a.totals.saves)
              : (b.totals.goals + b.totals.assists).compareTo(
                  a.totals.goals + a.totals.assists,
                );
          if (impact != 0) return impact;
          final rating = (b.totals.rating ?? -1).compareTo(
            a.totals.rating ?? -1,
          );
          return rating != 0
              ? rating
              : b.totals.matches.compareTo(a.totals.matches);
        });
    return ranked.firstOrNull;
  }

  String seasonLabel(String id) {
    final season = seasons.where((s) => s.id == id).firstOrNull;
    if (season == null) return 'Temporada de destaque';
    return season.startDate.year == season.endDate.year
        ? '${season.startDate.year}'
        : '${season.startDate.year}/${season.endDate.year}';
  }

  String opponent(PlayerMatchData match) =>
      teamNames[match.row['oppositeTeamId']] ?? 'adversário';
  late final int hatTricks = matches.where((m) => m.goals >= 3).length;
  late final int penaltySaves = matches.fold(
    0,
    (n, m) => n + (m.performance.penaltySaves ?? 0),
  );
  late final bool hasSaves = matches.any((m) => m.performance.saves != null);

  String get retrospective {
    if (!recordsAvailable) {
      return 'A venda foi salva. Não foi possível carregar o retrospecto agora.';
    }
    if (matches.isEmpty) {
      return 'A passagem pelo $clubName fica na história. Ainda não há atuações registradas para este jogador.';
    }
    final impact = goalkeeper && hasSaves
        ? '${totals.saves} ${totals.saves == 1 ? 'defesa' : 'defesas'}'
        : '${totals.goals} ${totals.goals == 1 ? 'gol' : 'gols'} e ${totals.assists} ${totals.assists == 1 ? 'assistência' : 'assistências'}';
    return 'Em ${totals.matches} ${totals.matches == 1 ? 'partida' : 'partidas'} pelo $clubName, deixou a marca de $impact.';
  }
}
