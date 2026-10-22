import 'FcScoreApi.dart';
import 'FcScoreModels.dart';

enum FcStageKind { table, groups, knockout }

String fcStageLabel(String name) {
  final key = fcNormalize(name);
  const names = {
    'league': 'Liga',
    'groupstage': 'Fase de grupos',
    'grupos': 'Fase de grupos',
    'roundof16': 'Oitavas de final',
    'quarterfinals': 'Quartas de final',
    'semifinals': 'Semifinal',
    'semifinal': 'Semifinal',
    'final': 'Final',
    'qualround': 'Fase preliminar',
    'qualificationround': 'Fase preliminar',
    'playoffs': 'Playoffs',
    'round1': '1ª fase',
    'round2': '2ª fase',
    'round3': '3ª fase',
    'round4': '4ª fase',
  };
  return names[key] ?? name;
}

bool _configuration(FcJson stage) {
  final name = fcNormalize(fcName(stage['name'], ''));
  return [
    'setup',
    'draw',
    'seeding',
    'configuracao',
    'sorteio',
  ].any(name.contains);
}

FcJson _fixture(FcJson row) => row['data'] is Map ? fcObject(row['data']) : row;
Set<String> _pair(FcJson f) => {
  fcId(fcObject(fcObject(f['home'])['team'])['id']),
  fcId(fcObject(fcObject(f['away'])['team'])['id']),
};
bool _played(FcJson f) =>
    (f['played'] == true || f['played'] == 1) &&
    fcInt(fcObject(f['home'])['goals']) != null &&
    fcInt(fcObject(f['away'])['goals']) != null;

class FcKnockoutTie {
  FcKnockoutTie(this.teams, this.rows, this.games);
  final List<String> teams;
  final List<FcJson> rows, games;
  List<FcJson> get played => games.where(_played).toList();
  int? score(String team) {
    final source = rows
        .where((r) => fcId(fcObject(r['team'])['id']) == team)
        .firstOrNull;
    if ((fcInt(source?['played']) ?? 0) > played.length) {
      return fcInt(source?['goalsFor']);
    }
    if (played.isEmpty) return null;
    return played.fold<int>(
      0,
      (total, game) =>
          total +
          (fcInt(
                fcObject(
                  game[fcId(fcObject(fcObject(game['home'])['team'])['id']) ==
                          team
                      ? 'home'
                      : 'away'],
                )['goals'],
              ) ??
              0),
    );
  }

  int? penalties(String team) {
    final last = played.lastOrNull;
    if (last == null) return null;
    final side = fcId(fcObject(fcObject(last['home'])['team'])['id']) == team
        ? 'home'
        : 'away';
    return fcInt(fcObject(last[side])['penalties']);
  }
}

class FcCompetitionStage {
  FcCompetitionStage(
    this.id,
    this.name,
    this.kind,
    this.groups,
    this.games,
    this.ties,
  );
  final String id, name;
  final FcStageKind kind;
  final List<FcJson> groups, games;
  final List<FcKnockoutTie> ties;
  bool get played =>
      games.any(_played) ||
      groups.any(
        (g) => fcList(g['rows']).any((r) => (fcInt(r['played']) ?? 0) > 0),
      );
}

List<FcCompetitionStage> fcCompetitionStages(
  FcJson data,
  List<FcJson> fixtures,
) {
  final raw = fcList(data['stages']);
  final games = fixtures.map(_fixture).toList();
  final result = <FcCompetitionStage>[];
  for (final (index, stage) in raw.indexed) {
    if (_configuration(stage)) continue;
    final name = fcName(stage['name'], fcId(stage['code']));
    final keys = {
      fcNormalize(name),
      fcNormalize(fcStageLabel(name)),
      fcNormalize(fcId(stage['code'])),
    };
    final matches =
        games
            .where(
              (f) =>
                  keys.contains(fcNormalize(fcId(f['stage']))) ||
                  keys.contains(fcNormalize(fcStageLabel(fcId(f['stage'])))) ||
                  (raw.length == 1 && fcId(f['stage']).isEmpty),
            )
            .toList()
          ..sort(
            (a, b) => '${a['date']} ${a['time']}'.compareTo(
              '${b['date']} ${b['time']}',
            ),
          );
    final groups = fcList(stage['groups'])
        .where((g) => fcList(g['rows']).isNotEmpty)
        .toList();
    final knownLeague = ['league', 'liga'].contains(fcNormalize(name));
    final groupName =
        fcNormalize(name).contains('group') ||
        fcNormalize(name).contains('grupo');
    final codeOnly = RegExp(r'^[SQ]\d+$', caseSensitive: false).hasMatch(name);
    if (codeOnly &&
        matches.isEmpty &&
        groups.every(
          (g) => fcList(g['rows']).every((r) => (fcInt(r['played']) ?? 0) == 0),
        )) {
      continue;
    }
    final bracketName = [
      'round',
      'final',
      'playoff',
      'qual',
      'oitavas',
      'quartas',
      'fasepreliminar',
    ].any(fcNormalize(name).contains);
    final knockout =
        !knownLeague &&
        (bracketName ||
            (groups.isNotEmpty &&
                groups.every((g) => fcList(g['rows']).length == 2)));
    final ties = <String, FcKnockoutTie>{};
    if (knockout) {
      void add(List<String> ids, List<FcJson> rows) {
        final pair = ids.toSet()..remove('');
        if (pair.length != 2) return;
        final key = (pair.toList()..sort()).join(':');
        final legs = matches.where((f) => _pair(f).containsAll(pair)).toList();
        final ordered = legs.isEmpty
            ? ids
            : [
                fcId(fcObject(fcObject(legs.first['home'])['team'])['id']),
                fcId(fcObject(fcObject(legs.first['away'])['team'])['id']),
              ];
        ties.putIfAbsent(key, () => FcKnockoutTie(ordered, rows, legs));
      }

      for (final g in groups) {
        final rows = fcList(g['rows']);
        if (rows.length == 2) {
          add(rows.map((r) => fcId(fcObject(r['team'])['id'])).toList(), rows);
        }
      }
      for (final f in matches) {
        add(_pair(f).toList(), []);
      }
    }
    result.add(
      FcCompetitionStage(
        fcId(stage['id']).isEmpty ? 'stage:$index' : fcId(stage['id']),
        knockout && groupName
            ? 'Mata-mata'
            : codeOnly
            ? 'Fase ${index + 1}'
            : fcStageLabel(name),
        knockout
            ? FcStageKind.knockout
            : groupName || groups.length > 1
            ? FcStageKind.groups
            : FcStageKind.table,
        groups,
        matches,
        ties.values.toList(),
      ),
    );
  }
  return result;
}
