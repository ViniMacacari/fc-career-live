import 'FcScoreApi.dart';

class FcScoreUpdateOptions {
  const FcScoreUpdateOptions({
    this.competitions = true,
    this.calendar = true,
    this.squads = true,
    this.ownSquad = false,
    this.overalls = true,
  });
  final bool competitions, calendar, squads, ownSquad, overalls;
  bool get hasSelection => competitions || calendar || squads || ownSquad;
  FcJson toMap() => {
    'competitions': competitions,
    'calendar': calendar,
    'squads': squads,
    'ownSquad': ownSquad,
    'overalls': overalls,
  };
  factory FcScoreUpdateOptions.fromMap(FcJson map) => FcScoreUpdateOptions(
    competitions: map['competitions'] != false,
    calendar: map['calendar'] != false,
    squads: map['squads'] != false,
    ownSquad: map['ownSquad'] == true,
    overalls: map['overalls'] != false,
  );
}
