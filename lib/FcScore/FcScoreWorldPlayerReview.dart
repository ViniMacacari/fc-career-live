import 'FcScoreApi.dart';
import 'FcScoreModels.dart';
import 'FcScoreWorldData.dart';
import 'FcScorePlayerCreation.dart';

class FcWorldReviewPlayer {
  FcWorldReviewPlayer(this.remote);
  final FcJson remote;
  final Set<String> teams = {};
  final Set<String> teamIds = {};
  String get id => fcId(remote['id']);
  String get name => fcPlayerName(remote);
  bool get hasName => fcName(remote['name'], '').trim().isNotEmpty;
  bool get hasOverall {
    final value = fcInt(remote['overall']);
    return value != null && value >= 1 && value <= 99;
  }

  bool get canCreate => hasName && hasOverall;
}

enum FcWorldPlayerIssueKind { duplicate, missingLink, missingData }

class FcWorldPlayerIssue {
  const FcWorldPlayerIssue(this.kind, this.players, {this.localId});
  final FcWorldPlayerIssueKind kind;
  final List<FcWorldReviewPlayer> players;
  final String? localId;
}

class FcWorldPlayerReview {
  FcWorldPlayerReview(
    FcScoreWorldData data,
    List<Map<String, Object?>> local, {
    this.protectedPlayerIds = const {},
  }) : local = {for (final p in local) fcId(p['id']): p} {
    for (final team in data.teams) {
      for (final player in fcList(team['roster'])) {
        final id = fcId(player['id']);
        if (id.isEmpty) continue;
        final item = players.putIfAbsent(id, () => FcWorldReviewPlayer(player));
        item.teams.add(fcName(team['name']));
        item.teamIds.add(fcId(team['id']));
      }
    }
  }

  final Map<String, FcWorldReviewPlayer> players = {};
  final Map<String, Map<String, Object?>> local;
  final Set<String> protectedPlayerIds;

  bool isProtected(String playerId) => protectedPlayerIds.contains(playerId);

  List<FcWorldPlayerIssue> issues(Map<String, String> mapping) {
    final result = <FcWorldPlayerIssue>[];
    final byLocal = <String, List<FcWorldReviewPlayer>>{};
    for (final player in players.values) {
      final choice = mapping[player.id];
      if (isProtected(player.id)) {
        if (!fcIsPlayerCreation(choice) && local.containsKey(choice)) {
          (byLocal[choice!] ??= []).add(player);
        }
        continue;
      }
      if (fcIsPlayerCreation(choice)) {
        if (!_canCreate(player, choice)) {
          result.add(
            FcWorldPlayerIssue(FcWorldPlayerIssueKind.missingData, [player]),
          );
        }
      } else {
        (byLocal[choice!] ??= []).add(player);
      }
    }
    for (final group in byLocal.entries) {
      if (group.value.every((p) => isProtected(p.id))) continue;
      if (!local.containsKey(group.key)) {
        result.add(
          FcWorldPlayerIssue(
            FcWorldPlayerIssueKind.missingLink,
            group.value,
            localId: group.key,
          ),
        );
      } else if (group.value.length > 1) {
        result.add(
          FcWorldPlayerIssue(
            FcWorldPlayerIssueKind.duplicate,
            group.value,
            localId: group.key,
          ),
        );
      }
    }
    return result;
  }

  bool valid(FcWorldReviewPlayer player, Map<String, String> mapping) {
    if (isProtected(player.id)) return true;
    final choice = mapping[player.id];
    if (fcIsPlayerCreation(choice)) {
      return _canCreate(player, choice);
    }
    return local.containsKey(choice) &&
        !players.keys.any((id) => id != player.id && mapping[id] == choice);
  }

  bool _canCreate(FcWorldReviewPlayer player, String? choice) {
    try {
      return FcWorldReviewPlayer(fcPlayerWithChoice(player.remote, choice))
          .canCreate;
    } on FcScoreException {
      return false;
    }
  }

  Set<String> occupiedByOthers(String playerId, Map<String, String> mapping) =>
      {
        for (final id in players.keys)
          if (id != playerId)
            if (!fcIsPlayerCreation(mapping[id])) mapping[id]!,
      };
}

class FcWorldPlayerMappingException extends FcScoreException {
  FcWorldPlayerMappingException(this.review)
    : super('Há vínculos de jogadores que precisam de correção.');
  final FcWorldPlayerReview review;
}
