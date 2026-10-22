import '../models/ManagerFixturePlayerPerformance.dart';

void _mirror<T extends PerformanceTimeDetails>(
  List<T> target,
  bool Function(T) test,
  Iterable<PerformanceTimeDetails> sources,
  T Function(PerformanceTimeDetails) create,
  void Function(T, PerformanceTimeDetails) update,
) {
  final used = <String>{};
  for (final source in sources) {
    final existing = target
        .where((item) => test(item) && !used.contains(item.id))
        .firstOrNull;
    if (existing == null) {
      final created = create(source);
      target.add(created);
      used.add(created.id);
    } else {
      update(existing, source);
      used.add(existing.id);
    }
  }
  target.removeWhere((item) => test(item) && !used.contains(item.id));
}

void syncGoalsAndAssists(
  ManagerFixturePlayerPerformance edited,
  Iterable<ManagerFixturePlayerPerformance> performances,
  String editedName,
) {
  final me = edited.playerInstanceId;
  for (final other in performances) {
    final id = other.playerInstanceId;
    if (id == me) continue;
    _mirror<PerformanceAssistDetails>(
      other.assistDetails,
      (assist) => assist.goalscorerId == me,
      edited.goalDetails.where((goal) => goal.assistantId == id),
      (goal) => PerformanceAssistDetails(
        goalscorerId: me,
        goalscorerName: editedName,
        minute: goal.minute,
        addedMinute: goal.addedMinute,
      ),
      (assist, goal) => assist
        ..goalscorerName = editedName
        ..minute = goal.minute
        ..addedMinute = goal.addedMinute,
    );
    _mirror<PerformanceGoalDetails>(
      other.goalDetails,
      (goal) => goal.assistantId == me,
      edited.assistDetails.where((assist) => assist.goalscorerId == id),
      (assist) => PerformanceGoalDetails(
        assistantId: me,
        assistantName: editedName,
        minute: assist.minute,
        addedMinute: assist.addedMinute,
      ),
      (goal, assist) => goal
        ..assistantName = editedName
        ..minute = assist.minute
        ..addedMinute = assist.addedMinute,
    );
    other
      ..assistsCount = other.assistDetails.length
      ..goalsCount = other.goalDetails.length;
  }
}

void syncSubstitutions(
  ManagerFixturePlayerPerformance edited,
  List<ManagerFixturePlayerPerformance> performances,
  String editedName,
  ManagerFixturePlayerPerformance Function(String playerInstanceId)
  createPerformance,
) {
  final me = edited.playerInstanceId;
  for (final sub in edited.substitutionDetails) {
    final partnerId = sub.anotherPlayerId;
    if (partnerId == null || partnerId == me) continue;
    if (!performances.any((item) => item.playerInstanceId == partnerId)) {
      performances.add(createPerformance(partnerId));
    }
  }
  SubstitutionType? opposite(SubstitutionType? type) => switch (type) {
    SubstitutionType.inGame => SubstitutionType.outGame,
    SubstitutionType.outGame => SubstitutionType.inGame,
    null => null,
  };
  for (final other in performances) {
    final id = other.playerInstanceId;
    if (id == me) continue;
    for (final sub in edited.substitutionDetails.where(
      (s) => s.anotherPlayerId == id,
    )) {
      final paired = other.substitutionDetails.any(
        (s) => s.anotherPlayerId == me && s.type == opposite(sub.type),
      );
      if (paired) continue;
      final unpaired = other.substitutionDetails
          .where(
            (s) =>
                s.inferred &&
                s.anotherPlayerId == null &&
                s.type == opposite(sub.type),
          )
          .toList();
      if (unpaired.length == 1) unpaired.single.anotherPlayerId = me;
    }
    _mirror<PerformanceSubstitutionDetails>(
      other.substitutionDetails,
      (item) => item.anotherPlayerId == me,
      edited.substitutionDetails.where((sub) => sub.anotherPlayerId == id),
      (source) {
        final sub = source as PerformanceSubstitutionDetails;
        return PerformanceSubstitutionDetails(
          inferred: sub.inferred,
          type: opposite(sub.type),
          anotherPlayerId: me,
          anotherPlayerName: editedName,
          minute: sub.minute,
          addedMinute: sub.addedMinute,
        );
      },
      (item, source) {
        final sub = source as PerformanceSubstitutionDetails;
        item
          ..inferred = sub.inferred
          ..type = opposite(sub.type)
          ..anotherPlayerName = editedName
          ..minute = sub.minute
          ..addedMinute = sub.addedMinute;
      },
    );
  }
}

void removePerformanceAndRelatedLinks(
  String playerInstanceId,
  Iterable<ManagerFixturePlayerPerformance> performances,
) {
  for (final other in performances) {
    if (other.playerInstanceId == playerInstanceId) continue;
    other.goalDetails.removeWhere(
      (goal) => goal.assistantId == playerInstanceId,
    );
    other.assistDetails.removeWhere(
      (assist) => assist.goalscorerId == playerInstanceId,
    );
    other.substitutionDetails.removeWhere(
      (sub) => sub.anotherPlayerId == playerInstanceId,
    );
    other
      ..goalsCount = other.goalDetails.length
      ..assistsCount = other.assistDetails.length;
  }
}

int calculateManagerFixtureAutoFilledTeamScore(
  Iterable<ManagerFixturePlayerPerformance> performances,
) {
  final goals = <String, int>{};
  final assists = <String, int>{};
  for (final performance in performances) {
    for (final goal in performance.goalDetails) {
      final key =
          '${performance.playerInstanceId}|${goal.assistantId}|'
          '${goal.minute}|${goal.addedMinute}';
      goals[key] = (goals[key] ?? 0) + 1;
    }
    for (final assist in performance.assistDetails) {
      final key =
          '${assist.goalscorerId}|${performance.playerInstanceId}|'
          '${assist.minute}|${assist.addedMinute}';
      assists[key] = (assists[key] ?? 0) + 1;
    }
  }
  var score = 0;
  for (final key in {...goals.keys, ...assists.keys}) {
    final goalCount = goals[key] ?? 0;
    final assistCount = assists[key] ?? 0;
    score += goalCount > assistCount ? goalCount : assistCount;
  }
  return score;
}
