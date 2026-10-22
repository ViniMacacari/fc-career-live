import 'FcScoreApi.dart';
import 'FcScoreModels.dart';

const fcStatLabels = {
  'goals': 'Gols',
  'assists': 'Assistências',
  'averageRating': 'Nota média',
  'manOfTheMatch': 'Melhor em campo',
  'appearances': 'Jogos',
  'minutes': 'Minutos',
  'cleanSheets': 'Jogos sem sofrer gols (goleiros)',
  'saves': 'Defesas (goleiros)',
  'goalsConceded': 'Gols sofridos (goleiros)',
  'yellowCards': 'Cartões amarelos',
  'redCards': 'Cartões vermelhos',
};

void fcValidateStats(FcJson stats, {String? source}) {
  for (final key in fcStatLabels.keys) {
    if (stats[key] == null) continue;
    final number = key == 'averageRating'
        ? num.tryParse('${stats[key]}')
        : fcInt(stats[key]);
    if (number == null ||
        !number.isFinite ||
        number < 0 ||
        (key == 'averageRating' && number > 10)) {
      throw FcScoreException(
        '${source ?? 'Estatísticas da API'}: '
        '${fcStatLabels[key]} ($key) veio com o valor ${stats[key]}. '
        'Corrija esse dado no exportador e atualize. '
        '${key == 'averageRating' ? 'A nota deve ficar entre 0 e 10.' : 'Era esperado um inteiro não negativo.'}',
      );
    }
  }
}

List<FcJson>? fcCompetitionStats(FcJson competition, List<FcJson> teams) {
  if (competition['playerStatsComplete'] == true) {
    return fcList(competition['playerStats']);
  }
  final id = fcId(fcObject(competition['competition'])['id']);
  var available = false;
  final records = <FcJson>[];
  for (final team in teams) {
    for (final p in fcList(team['roster'])) {
      final season = fcObject(p['seasonStats']);
      if (season['competitions'] is! List) continue;
      available = true;
      for (final s in fcList(season['competitions'])) {
        if (fcId(fcObject(s['competition'])['id']) != id ||
            fcId(fcObject(s['team'])['id']) != fcId(team['id'])) {
          continue;
        }
        records.add({
          ...s,
          'player': {'id': p['id'], 'name': fcPlayerName(p)},
        });
      }
    }
  }
  return available ? records : null;
}

List<FcJson> fcRankStats(List<FcJson> records, String metric) {
  final goalkeepers = [
    'cleanSheets',
    'saves',
    'goalsConceded',
  ].contains(metric);
  final sorted = records.where((p) {
    final value = num.tryParse('${p[metric]}');
    return value != null &&
        (metric == 'goalsConceded' || value > 0) &&
        (fcInt(p['appearances']) ?? 0) > 0 &&
        (!goalkeepers || fcId(p['position']) == 'GK');
  }).toList();
  sorted.sort((a, b) {
    final comparison = num.parse('${b[metric]}')
        .compareTo(num.parse('${a[metric]}'));
    if (comparison != 0) {
      return metric == 'goalsConceded' ? -comparison : comparison;
    }
    final games = (fcInt(b['appearances']) ?? 0).compareTo(
      fcInt(a['appearances']) ?? 0,
    );
    return games != 0 ? games : fcName(a['name']).compareTo(fcName(b['name']));
  });
  return sorted;
}
