import 'dart:convert';

import 'MatchPerformanceStats.dart';

import 'package:uuid/uuid.dart';

enum GoalType {
  openplay,
  penalty,
  directfreekick,
  indirectfreekick,
  cornercick,
  counterattack,
  header,
  longshot,
  cross,
  deflected,
  solo,
  bicyclekick,
  volley,
  chip,
  rebound;

  static GoalType fromString(String value) => GoalType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => GoalType.bicyclekick,
  );
}

enum SubstitutionType { inGame, outGame }

int? _int(Object? value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  String() => int.tryParse(value),
  _ => null,
};

double? _double(Object? value) => switch (value) {
  num() => value.toDouble(),
  String() => double.tryParse(value),
  _ => null,
};

String _newId() => const Uuid().v1();

List<GoalType> decodeGoalTypes(Object? value) {
  if (value == null) return [];
  final decoded = value is String ? jsonDecode(value) : value;
  if (decoded is! List) return [];
  return decoded.map((item) => GoalType.fromString(item.toString())).toList();
}

String encodeGoalTypes(List<GoalType> types) =>
    jsonEncode(types.map((type) => type.name).toList());

List<Map<String, dynamic>> _decodeList(Object? value) {
  if (value == null) return const [];
  final decoded = value is String ? jsonDecode(value) : value;
  if (decoded is! List) return const [];
  return decoded.whereType<Map>().map(Map<String, dynamic>.from).toList();
}

String _encodeList(List<PerformanceTimeDetails> items) =>
    jsonEncode(items.map((item) => item.toMap()).toList());

class GoalShotLocation {
  const GoalShotLocation(this.x, this.y);
  final double x, y;

  static GoalShotLocation? fromValue(Object? value) {
    if (value == null) return null;
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! Map) return null;
    double read(String key) => (_double(decoded[key]) ?? 0).clamp(0, 1);
    return GoalShotLocation(read('x'), read('y'));
  }

  String toJsonString() => jsonEncode({'x': x, 'y': y});
}

class PerformanceTimeDetails {
  PerformanceTimeDetails({String? id, this.minute, this.addedMinute})
    : id = id ?? _newId();

  factory PerformanceTimeDetails.fromMap(Map<String, dynamic> map) =>
      PerformanceTimeDetails(
        id: map['id'] as String?,
        minute: _int(map['minute']),
        addedMinute: _int(map['addedMinute']),
      );

  final String id;
  int? minute, addedMinute;

  Map<String, Object?> toMap() => {
    'id': id,
    'minute': minute,
    'addedMinute': addedMinute,
  };
}

typedef PerformanceCardDetails = PerformanceTimeDetails;
typedef PerformanceOwnGoalDetails = PerformanceTimeDetails;
typedef PerformanceMissedPenaltyDetails = PerformanceTimeDetails;
typedef PerformanceInjuryDetails = PerformanceTimeDetails;

class PerformanceGoalDetails extends PerformanceTimeDetails {
  PerformanceGoalDetails({
    super.id,
    super.minute,
    super.addedMinute,
    this.assistantId,
    this.assistantName,
    List<GoalType>? type,
    this.goalLocation,
    this.fieldLocation,
  }) : type = type ?? [];

  factory PerformanceGoalDetails.fromMap(Map<String, dynamic> map) =>
      PerformanceGoalDetails(
        id: map['id'] as String?,
        assistantId: map['assistantId'] as String?,
        assistantName: map['assistantName'] as String?,
        type: decodeGoalTypes(map['type']),
        minute: _int(map['minute']),
        addedMinute: _int(map['addedMinute']),
        goalLocation: GoalShotLocation.fromValue(map['goalLocation']),
        fieldLocation: GoalShotLocation.fromValue(map['fieldLocation']),
      );

  String? assistantId, assistantName;
  List<GoalType> type;
  GoalShotLocation? goalLocation, fieldLocation;

  bool get isPenalty => type.contains(GoalType.penalty);

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'assistantId': assistantId,
    'assistantName': assistantName,
    'type': encodeGoalTypes(type),
    'minute': minute,
    'addedMinute': addedMinute,
    'goalLocation': goalLocation?.toJsonString(),
    'fieldLocation': fieldLocation?.toJsonString(),
  };
}

class PerformanceAssistDetails extends PerformanceTimeDetails {
  PerformanceAssistDetails({
    super.id,
    super.minute,
    super.addedMinute,
    this.goalscorerId,
    this.goalscorerName,
  });

  factory PerformanceAssistDetails.fromMap(Map<String, dynamic> map) =>
      PerformanceAssistDetails(
        id: map['id'] as String?,
        goalscorerId: map['goalscorerId'] as String?,
        minute: _int(map['minute']),
        goalscorerName: map['goalscorerName'] as String?,
        addedMinute: _int(map['addedMinute']),
      );

  String? goalscorerId, goalscorerName;

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'minute': minute,
    'addedMinute': addedMinute,
    'goalscorerName': goalscorerName,
    'goalscorerId': goalscorerId,
  };
}

class PerformanceSubstitutionDetails extends PerformanceTimeDetails {
  PerformanceSubstitutionDetails({
    super.id,
    super.minute,
    super.addedMinute,
    this.type,
    this.anotherPlayerId,
    this.anotherPlayerName,
    this.inferred = false,
  });

  factory PerformanceSubstitutionDetails.fromMap(Map<String, dynamic> map) =>
      PerformanceSubstitutionDetails(
        id: map['id'] as String?,
        anotherPlayerId: map['anotherPlayerId'] as String?,
        type: map['type'] == null
            ? null
            : map['type'] == 'inGame'
            ? SubstitutionType.inGame
            : SubstitutionType.outGame,
        minute: _int(map['minute']),
        anotherPlayerName: map['anotherPlayerName'] as String?,
        inferred: map['inferred'] == true,
        addedMinute: _int(map['addedMinute']),
      );

  SubstitutionType? type;
  String? anotherPlayerId, anotherPlayerName;
  bool inferred;

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'minute': minute,
    'addedMinute': addedMinute,
    'type': type?.name,
    'anotherPlayerName': anotherPlayerName,
    if (inferred) 'inferred': true,
    'anotherPlayerId': anotherPlayerId,
  };
}

class ManagerFixturePlayerPerformance {
  ManagerFixturePlayerPerformance({
    String? id,
    required this.personId,
    required this.fixtureId,
    required this.playerInstanceId,
    this.goalsCount,
    this.assistsCount,
    this.yellowCards,
    this.redCards,
    this.avgRating,
    this.shotsCount,
    this.shotAccuracy,
    this.passes,
    this.keyPasses,
    this.passAccuracy,
    this.tackles,
    this.tacklesAccuracy,
    this.dribbles,
    this.dribblesAccuracy,
    this.saves,
    this.penaltySaves,
    this.recordedMinutes,
    this.recordedStarted,
    this.apiStats = const {},
    List<PerformanceGoalDetails>? goalDetails,
    List<PerformanceAssistDetails>? assistDetails,
    List<PerformanceCardDetails>? yellowCardDetails,
    List<PerformanceCardDetails>? redCardDetails,
    List<PerformanceSubstitutionDetails>? substitutionDetails,
    List<PerformanceOwnGoalDetails>? ownGoalDetails,
    List<PerformanceMissedPenaltyDetails>? missedPenaltyDetails,
    List<PerformanceInjuryDetails>? injuryDetails,
  }) : id = id ?? const Uuid().v4(),
       goalDetails = goalDetails ?? [],
       assistDetails = assistDetails ?? [],
       yellowCardDetails = yellowCardDetails ?? [],
       redCardDetails = redCardDetails ?? [],
       substitutionDetails = substitutionDetails ?? [],
       ownGoalDetails = ownGoalDetails ?? [],
       missedPenaltyDetails = missedPenaltyDetails ?? [],
       injuryDetails = injuryDetails ?? [];

  factory ManagerFixturePlayerPerformance.fromMap(Map<String, Object?> map) {
    List<T> details<T>(
      String column,
      String? countColumn,
      T Function(Map<String, dynamic>) parse,
      T Function() placeholder,
    ) {
      if (map[column] == null) {
        final count = countColumn == null ? 0 : _int(map[countColumn]) ?? 0;
        return List.generate(count, (_) => placeholder());
      }
      return _decodeList(map[column]).map(parse).toList();
    }

    return ManagerFixturePlayerPerformance(
      id: map['id'] as String,
      personId: map['personId'] as String,
      fixtureId: map['fixtureId'] as String,
      playerInstanceId: map['playerInstanceId'] as String,
      goalsCount: _int(map['goalsCount']),
      assistsCount: _int(map['assistsCount']),
      shotsCount: _int(map['shotsCount']),
      avgRating: _double(map['avgRating']),
      shotAccuracy: _int(map['shotAccuracy']),
      passes: _int(map['passes']),
      keyPasses: _int(map['keyPasses']),
      passAccuracy: _int(map['passAccuracy']),
      tackles: _int(map['tackles']),
      tacklesAccuracy: _int(map['tacklesAccuracy']),
      dribbles: _int(map['dribbles']),
      dribblesAccuracy: _int(map['dribblesAccuracy']),
      saves: _int(map['saves']),
      penaltySaves: _int(map['penaltySaves']),
      apiStats: decodePerformanceStats(map['apiStats']),
      recordedMinutes: _int(map['recordedMinutes']),
      recordedStarted: map['recordedStarted'] == null
          ? null
          : map['recordedStarted'] == 1,
      yellowCards: _int(map['yellowCards']),
      redCards: _int(map['redCards']),
      goalDetails: details(
        'goalDetails',
        'goalsCount',
        PerformanceGoalDetails.fromMap,
        PerformanceGoalDetails.new,
      ),
      assistDetails: details(
        'assistDetails',
        'assistsCount',
        PerformanceAssistDetails.fromMap,
        PerformanceAssistDetails.new,
      ),
      ownGoalDetails: details(
        'ownGoalDetails',
        null,
        PerformanceTimeDetails.fromMap,
        PerformanceTimeDetails.new,
      ),
      missedPenaltyDetails: details(
        'missedPenaltyDetails',
        null,
        PerformanceTimeDetails.fromMap,
        PerformanceTimeDetails.new,
      ),
      injuryDetails: details(
        'injuryDetails',
        null,
        PerformanceTimeDetails.fromMap,
        PerformanceTimeDetails.new,
      ),
      yellowCardDetails: details(
        'yellowCardDetails',
        'yellowCards',
        PerformanceTimeDetails.fromMap,
        PerformanceTimeDetails.new,
      ),
      redCardDetails: details(
        'redCardDetails',
        'redCards',
        PerformanceTimeDetails.fromMap,
        PerformanceTimeDetails.new,
      ),
      substitutionDetails: details(
        'substitutionDetails',
        null,
        PerformanceSubstitutionDetails.fromMap,
        PerformanceSubstitutionDetails.new,
      ),
    );
  }

  final String id, personId, fixtureId;
  String playerInstanceId;
  int? goalsCount, assistsCount, yellowCards, redCards;
  double? avgRating;
  int? shotsCount, shotAccuracy, passes, keyPasses, passAccuracy;
  int? tackles, tacklesAccuracy, dribbles, dribblesAccuracy;
  int? saves, penaltySaves;
  int? recordedMinutes;
  bool? recordedStarted;
  Map<String, Object?> apiStats;
  List<PerformanceGoalDetails> goalDetails;
  List<PerformanceAssistDetails> assistDetails;
  List<PerformanceCardDetails> yellowCardDetails, redCardDetails;
  List<PerformanceSubstitutionDetails> substitutionDetails;
  List<PerformanceOwnGoalDetails> ownGoalDetails;
  List<PerformanceMissedPenaltyDetails> missedPenaltyDetails;
  List<PerformanceInjuryDetails> injuryDetails;

  ManagerFixturePlayerPerformance copy() =>
      ManagerFixturePlayerPerformance.fromMap(toMap());

  int? getLastMinuteValue() {
    final minutes = <int>[
      for (final list in <List<PerformanceTimeDetails>>[
        goalDetails,
        assistDetails,
        ownGoalDetails,
        injuryDetails,
        missedPenaltyDetails,
        yellowCardDetails,
        redCardDetails,
        substitutionDetails,
      ])
        for (final item in list)
          if (item.minute != null) item.minute!,
    ]..sort();
    return minutes.isEmpty ? null : minutes.last;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'personId': personId,
    'fixtureId': fixtureId,
    'playerInstanceId': playerInstanceId,
    if (apiStats.isNotEmpty) 'apiStats': jsonEncode(apiStats),
    if (recordedMinutes != null) 'recordedMinutes': recordedMinutes,
    if (recordedStarted != null) 'recordedStarted': recordedStarted! ? 1 : 0,
    'goalsCount': goalsCount,
    'assistsCount': assistsCount,
    'yellowCards': yellowCards,
    'avgRating': avgRating,
    'redCards': redCards,
    'shotsCount': shotsCount,
    'shotAccuracy': shotAccuracy,
    'passes': passes,
    'keyPasses': keyPasses,
    'passAccuracy': passAccuracy,
    'tackles': tackles,
    'tacklesAccuracy': tacklesAccuracy,
    'dribbles': dribbles,
    'dribblesAccuracy': dribblesAccuracy,
    'saves': saves,
    'penaltySaves': penaltySaves,
    'goalDetails': _encodeList(goalDetails),
    'ownGoalDetails': _encodeList(ownGoalDetails),
    'missedPenaltyDetails': _encodeList(missedPenaltyDetails),
    'injuryDetails': _encodeList(injuryDetails),
    'assistDetails': _encodeList(assistDetails),
    'yellowCardDetails': _encodeList(yellowCardDetails),
    'redCardDetails': _encodeList(redCardDetails),
    'substitutionDetails': _encodeList(substitutionDetails),
  };
}
