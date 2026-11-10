import 'Components/SelectionSearchField.dart';
import 'GameCatalog.dart';

typedef TeamChoice = ({CatalogItem league, CatalogItem team});

const continentalLeagueIds = {'1003', '1014', '42'};

String clubNameKey(String text) =>
    selectionSearchKey(text).replaceAll(RegExp('[^a-z0-9]'), '');

class _Entry {
  _Entry(this.choice, this.index)
    : key = clubNameKey(choice.team.label),
      women =
          choice.league.isWoman ||
          choice.team.isWoman ||
          choice.league.id.endsWith('-w'),
      identity = choice.team.isCustom
          ? null
          : choice.team.clubIdentity ?? choice.team.id,
      secondary =
          continentalLeagueIds.contains(choice.league.id) ||
          choice.team.isSupplementalClub;
  final TeamChoice choice;
  final int index;
  final String key;
  final String? identity;
  final bool women, secondary;

  bool sameClub(_Entry other) {
    if (women != other.women || key.isEmpty || other.key.isEmpty) return false;
    if (key == other.key) {
      return identity == null ||
          other.identity == null ||
          identity == other.identity;
    }
    if (identity == null || identity != other.identity) return false;
    if (!secondary && !other.secondary) return false;
    final shorter = key.length <= other.key.length;
    final short = shorter ? key : other.key;
    final long = shorter ? other.key : key;
    if (short.length < 4) return false;
    if (long.contains(short)) return true;
    var prefix = 0;
    while (prefix < short.length && short[prefix] == long[prefix]) {
      prefix++;
    }
    return prefix >= 6;
  }
}

List<TeamChoice> uniqueClubs(
  Iterable<TeamChoice> choices, {
  String? selectedTeamId,
  String? selectedLeagueId,
  String? preferredLeagueId,
  Set<String> preferredTeamIds = const {},
}) {
  final entries = [
    for (final (index, choice) in choices.indexed) _Entry(choice, index),
  ];
  int rank(_Entry e) {
    final team = e.choice.team, league = e.choice.league;
    if (team.id == selectedTeamId &&
        (selectedLeagueId == null || league.id == selectedLeagueId)) {
      return 0;
    }
    if (preferredTeamIds.contains(team.id)) return 1;
    if (preferredLeagueId != null && league.id == preferredLeagueId) return 2;
    if (team.isCustom) return 5;
    return continentalLeagueIds.contains(league.id) ? 4 : 3;
  }

  final ordered = [...entries]
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.index.compareTo(b.index);
    });
  final byKey = <String, List<_Entry>>{}, byIdentity = <String, List<_Entry>>{};
  final kept = <int>{};
  for (final entry in ordered) {
    final rivals = [
      ...?byKey[entry.key],
      if (entry.identity != null) ...?byIdentity[entry.identity],
    ];
    if (rivals.any(entry.sameClub)) continue;
    kept.add(entry.index);
    (byKey[entry.key] ??= []).add(entry);
    if (entry.identity != null) {
      (byIdentity[entry.identity!] ??= []).add(entry);
    }
  }
  return [
    for (final entry in entries)
      if (kept.contains(entry.index)) entry.choice,
  ];
}

List<TeamChoice> searchTeams(
  Iterable<TeamChoice> choices,
  String query, {
  String? preferredLeagueId,
  Set<String> preferredTeamIds = const {},
}) {
  final text = selectionSearchKey(query);
  final tokens = text
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return choices.toList();
  final compact = clubNameKey(query);
  final scored = <(int, int, TeamChoice)>[];
  for (final (index, choice) in choices.indexed) {
    final team = selectionSearchKey(choice.team.label);
    final league = selectionSearchKey(choice.league.label);
    final teamKey = clubNameKey(choice.team.label);
    bool inTeam(String token) =>
        team.contains(token) || teamKey.contains(clubNameKey(token));
    if (!tokens.every((token) => inTeam(token) || league.contains(token))) {
      continue;
    }
    final words = team.split(RegExp(r'[^a-z0-9]+'));
    final score = teamKey == compact
        ? 0
        : teamKey.startsWith(compact) && compact.isNotEmpty
        ? 1
        : tokens.every((token) => words.any((word) => word.startsWith(token)))
        ? 2
        : tokens.every(inTeam)
        ? 3
        : 4;
    scored.add((score, index, choice));
  }
  int preference(TeamChoice choice) => preferredTeamIds.contains(choice.team.id)
      ? 0
      : choice.league.id == preferredLeagueId
      ? 1
      : 2;
  scored.sort((a, b) {
    final byScore = a.$1.compareTo(b.$1);
    if (byScore != 0) return byScore;
    final byPreference = preference(a.$3).compareTo(preference(b.$3));
    if (byPreference != 0) return byPreference;
    final byName = selectionSearchKey(a.$3.team.label)
        .compareTo(selectionSearchKey(b.$3.team.label));
    return byName != 0 ? byName : a.$2.compareTo(b.$2);
  });
  return [for (final entry in scored) entry.$3];
}
