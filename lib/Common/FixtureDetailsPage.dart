import 'FixtureCaptainPanel.dart';
import '../models/FixtureCaptaincy.dart';
import '../utils/AppColors.dart';
import '../utils/themes.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../FcScore/FcScoreQuickImportPage.dart';
import '../FcScore/FcScoreRepository.dart';
import '../ManagerCareer/Fixtures/EditManagerFixturePage.dart';
import '../ManagerCareer/Fixtures/Performances/PerformanceDetails.dart';
import '../ManagerCareer/Fixtures/PressConferencePage.dart';
import '../ManagerCareer/TeamPage/ViewPlayer/PlayerProfileVisuals.dart'
    show ProfilePortrait, TournamentBadge;
import '../ManagerCareer/TeamPage/ViewPlayer/ViewPlayerPage.dart';
import '../PlayerCareer/Fixtures/EditPlayerFixture.dart';
import '../models/ManagerFixture.dart';
import '../models/FixtureFormation.dart';
import '../models/OpponentLineup.dart';
import '../models/ManagerFixturePlayerPerformance.dart';
import '../models/Person.dart';
import '../models/PressConference.dart';
import '../utils/GameCatalog.dart';
import '../utils/Components/TeamLogo.dart';
import '../utils/SqlService.dart';
import '../utils/FixtureTablePosition.dart';
import '../utils/competitions/TournamentAutomation.dart';
import '../utils/databaseUtils.dart';
import '../utils/eventTimeUtils.dart';
import '../utils/managerPlayerMinutesUtils.dart';
import 'HeadToHeadDetailPage.dart';
import 'FixturePositionIndicator.dart';
import 'FixtureTimelineView.dart';
import 'FixtureNavigation.dart';
import 'FixtureFormationView.dart';
import 'FixtureFormationsPage.dart';
import 'FixturePlayerPerformancePage.dart';
import '../utils/Components/CompactDashboardWidgets.dart';
import '../utils/Components/PlayerAvatar.dart';
import 'MatchUi.dart';

class FixtureDetailsPage extends StatefulWidget {
  const FixtureDetailsPage({
    super.key,
    required this.person,
    required this.fixture,
    required this.opponent,
    required this.tournament,
    this.tournamentLogo,
    this.lineupData,
    this.tablePosition,
    this.onFormationSaved,
    this.sql,
  });
  final Person person;
  final SqlService? sql;
  final Map<String, Object?> fixture;
  final String opponent, tournament;
  final String? tournamentLogo;

  @visibleForTesting
  final Future<FixtureLineupData>? lineupData;
  @visibleForTesting
  final Future<FixtureTablePosition>? tablePosition;
  @visibleForTesting
  final Future<void> Function(FixtureFormation)? onFormationSaved;

  @override
  State<FixtureDetailsPage> createState() => _FixtureDetailsPageState();
}

class _FixtureDetailsPageState extends State<FixtureDetailsPage> {
  SqlService get _sql => widget.sql ?? SqlService.instance;
  late final Map<String, Object?> _fixture = Map.of(widget.fixture);
  late Future<FixtureLineupData> _lineup = widget.lineupData ?? _loadLineup();
  late Future<FixtureTablePosition> _tablePosition;

  bool get _manager => widget.person.category == PersonCategory.manager;
  String get _fixtureId => _fixture['id'] as String;

  PressConference? _press;

  bool _fcScore = false, _fcLinked = false;

  @override
  void initState() {
    super.initState();
    _tablePosition = _loadTablePosition();
    if (_manager && widget.lineupData == null) _loadPress();
    if (widget.lineupData == null) _loadFcScore();
  }

  Future<void> _loadFcScore() async {
    try {
      final link = await FcScoreRepository(sql: _sql).linkFor(widget.person.id);
      final linked =
          link != null &&
          (await (await _sql.database).query(
            'FcScoreImport',
            columns: ['fixtureId'],
            where: 'personId = ? AND fixtureId = ?',
            whereArgs: [widget.person.id, _fixtureId],
            limit: 1,
          )).isNotEmpty;
      if (mounted) {
        setState(() {
          _fcScore = link != null;
          _fcLinked = linked;
        });
      }
    } catch (_) {}
  }

  Future<void> _completeFromApi() async {
    final completed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FcScoreQuickImportPage(
          person: widget.person,
          repository: FcScoreRepository(sql: _sql),
          target: Map.of(_fixture),
        ),
      ),
    );
    if (completed == true && mounted) {
      await _reload();
      await _loadFcScore();
    }
  }

  Future<void> _loadPress() async {
    try {
      final press = await _sql.getPressConference(widget.person.id, _fixtureId);
      if (mounted) setState(() => _press = press);
    } catch (_) {}
  }

  Future<FixtureTablePosition> _loadTablePosition() async {
    final position =
        await (widget.tablePosition ??
            _sql.getFixtureTablePosition(widget.person.category, _fixture));
    if (mounted) setState(() => _fixture['position'] = position.position);
    return position;
  }

  Future<void> _pressConference() async {
    await Navigator.push<PressConference>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PressConferencePage(person: widget.person, fixtureId: _fixtureId),
      ),
    );
    if (mounted) await _loadPress();
  }

  List<OpponentGoalDetails> get _opponentGoals =>
      decodeOpponentGoals(_fixture['opponentGoalDetails']);

  Future<FixtureLineupData> _loadLineup() async {
    final service = _sql;
    if (!_manager) {
      final rows = await service.getManagerPerformances(
        widget.person.id,
        _fixtureId,
      );
      final performance = rows.isEmpty
          ? _migratedPlayerPerformance()
          : ManagerFixturePlayerPerformance.fromMap(rows.first);
      return FixtureLineupData(
        const [],
        [performance],
        {performance.playerInstanceId: widget.person.name},
        {
          performance.playerInstanceId: positionShortName(
            widget.person.positionId,
          ),
        },
        positionIds: {performance.playerInstanceId: widget.person.positionId},
      );
    }
    final roster =
        (_fixture['playerTeamId'] == widget.person.nationalCoachingTeamId
                ? await service.getNationalTeamPlayers(
                    widget.person.id,
                    _fixture['seasonId'] as String,
                  )
                : await service.getTeamPlayers(
                    widget.person.id,
                    _fixture['seasonId'] as String,
                  ))
            .where((row) => row['playerId'] != null)
            .toList();
    final performances = await service.getPerformanceModels(
      widget.person.id,
      _fixtureId,
    );
    final savedFormation = FixtureFormation.decode(_fixture['matchLineup']);
    final players = await service.getCustomPlayers(
      widget.person.id,
      playerIds: {
        for (final row in roster) row['playerId'] as String,
        for (final performance in performances) performance.playerInstanceId,
        ...?savedFormation?.players.keys,
      },
    );
    final positionOf = {
      for (final row in players)
        row['id'] as String: row['positionId'] as String?,
    };
    performances.sort(
      (a, b) =>
          getPositionPriority(positionOf[a.playerInstanceId])
              .compareTo(getPositionPriority(positionOf[b.playerInstanceId])),
    );
    ({FixtureFormation? own, OpponentLineup? opponent})? pitch;
    try {
      pitch = await FcScoreRepository(sql: service)
          .fixturePitchLineups(widget.person, _fixture);
    } catch (_) {}
    return FixtureLineupData(
      roster,
      performances,
      {
        for (final row in players)
          row['id'] as String: row['name']?.toString() ?? '',
      },
      {
        for (final row in players)
          row['id'] as String: positionShortName(row['positionId'] as String?),
      },
      avatars: {
        for (final row in players)
          row['id'] as String: (
            realPlayerId: row['realPlayerId'] as String?,
            path: row['customAvatarFilePath'] as String?,
          ),
      },
      positionIds: positionOf,
      playerProfiles: {
        for (final row in players)
          row['id'] as String: {
            ...row,
            'playerId': row['id'],
            'customName': row['name'],
            'customPositionId': row['positionId'],
            'seasonId': _fixture['seasonId'],
          },
      },
      ownFormation: pitch?.own,
      opponentLineup: pitch?.opponent,
    );
  }

  ManagerFixturePlayerPerformance _migratedPlayerPerformance() {
    final performance = ManagerFixturePlayerPerformance.fromMap(
      {
        'id': null,
        'personId': widget.person.id,
        'fixtureId': _fixtureId,
        'playerInstanceId': widget.person.id,
        'goalsCount': _fixture['goalsCount'],
        'assistsCount': _fixture['assistsCount'],
        'yellowCards': _fixture['yellowCards'],
        'redCards': _fixture['redCards'],
        'shotsCount': _fixture['shotsOnTarget'],
        'avgRating': _fixture['rating'],
        'saves': _fixture['savesCount'],
      }.map((key, value) => MapEntry(key, value ?? (key == 'id' ? '' : null))),
    );
    final penalties = (_fixture['goalsFromPenalty'] as int?) ?? 0;
    for (final goal in performance.goalDetails.take(penalties)) {
      goal.type = [GoalType.penalty];
    }
    return ManagerFixturePlayerPerformance(
      personId: performance.personId,
      fixtureId: performance.fixtureId,
      playerInstanceId: performance.playerInstanceId,
      goalsCount: performance.goalsCount,
      assistsCount: performance.assistsCount,
      yellowCards: performance.yellowCards,
      redCards: performance.redCards,
      shotsCount: performance.shotsCount,
      avgRating: performance.avgRating,
      saves: performance.saves,
      goalDetails: performance.goalDetails,
      assistDetails: performance.assistDetails,
      yellowCardDetails: performance.yellowCardDetails,
      redCardDetails: performance.redCardDetails,
    );
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => widget.person.category == PersonCategory.player
            ? EditPlayerFixture(person: widget.person, fixture: _fixture)
            : EditManagerFixturePage(person: widget.person, fixture: _fixture),
      ),
    );
    if (mounted && changed == true) {
      await openFixtureDetails(
        context,
        widget.person,
        _fixtureId,
        replace: true,
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('fixtures.removeFixture'.tr()),
        content: Text('fixtures.removeFixtureConfirmation'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('common.remove'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _sql.deleteFixture(widget.person.category, _fixtureId);
    await TournamentAutomation.trySync(widget.person);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _favorite() async {
    final next = _fixture['isFavorite'] != 1;
    await _sql.setFixtureFavorite(
      widget.person.category,
      widget.person.id,
      _fixtureId,
      next,
    );
    if (mounted) setState(() => _fixture['isFavorite'] = next ? 1 : 0);
  }

  Future<void> _reload() async {
    final latest = await _sql.getFixture(
      widget.person.category,
      widget.person.id,
      _fixtureId,
    );
    if (!mounted) return;
    setState(() {
      if (latest != null) {
        _fixture
          ..clear()
          ..addAll(latest);
      }
      _lineup = _loadLineup();
      _tablePosition = _loadTablePosition();
    });
  }

  Future<void> _openPlayerPerformance(FixtureLineupData data) async {
    final performance = data.performances.first;
    final result = await Navigator.push<PerformanceDetailsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => PerformanceDetails(
          person: widget.person,
          performance: performance,
          isNew: false,
          showPlayerOfMatch: false,
          showGoalkeeperStats: widget.person.positionId == '0',
        ),
      ),
    );
    final edited = result?.performance;
    if (edited == null || !mounted) return;
    await _sql.saveManagerPerformances(
      [edited],
      deletedIds: (await _sql.getManagerPerformances(
        widget.person.id,
        _fixtureId,
      )).map((row) => row['id'] as String).where((id) => id != edited.id),
    );
    await _sql.updateFixtureFields(
      PersonCategory.player,
      widget.person.id,
      _fixtureId,
      {
        'rating': edited.avgRating,
        'goalsCount': edited.goalsCount ?? 0,
        'assistsCount': edited.assistsCount ?? 0,
        'savesCount': edited.saves ?? 0,
        'yellowCards': edited.yellowCards ?? 0,
        'redCards': edited.redCards ?? 0,
        'goalsFromPenalty': edited.goalDetails
            .where((goal) => goal.isPenalty)
            .length,
        'shotsOnTarget': edited.shotsCount,
      },
    );
    await _reload();
  }

  AppColors get _c => AppColors.of(context);
  bool get _away => _fixture['location'] == 'away';

  String _teamName(String teamId, String? leagueId) =>
      GameCatalog.current?.teamLabel(
        widget.person.fifaVersion,
        teamId,
        leagueId: leagueId,
      ) ??
      teamId;

  Widget _logo(String teamId, String? leagueId, double size) => TeamLogo.lookup(
    fifaVersion: widget.person.fifaVersion,
    teamId: teamId,
    leagueId: leagueId,
    size: size,
  );

  ({String id, String? league, String name, Object? score, Object? penalties})
  _side({required bool left, required String ownTeam}) => left != _away
      ? (
          id: _fixture['playerTeamId'] as String,
          league: _fixture['playerTeamLeagueId'] as String?,
          name: ownTeam,
          score: _fixture['playerTeamScore'],
          penalties: _fixture['playerTeamPenaltiesScore'],
        )
      : (
          id: _fixture['oppositeTeamId'] as String,
          league: _fixture['oppositeTeamLeagueId'] as String?,
          name: widget.opponent,
          score: _fixture['oppositeTeamScore'],
          penalties: _fixture['oppositeTeamPenaltiesScore'],
        );

  List<_Scorer> _scorers(FixtureLineupData data, {required bool mine}) {
    final scorers = <String, _Scorer>{};
    void add(
      String key,
      String name,
      int? minute,
      int? added,
      bool penalty,
      bool ownGoal,
    ) {
      final scorer = scorers.putIfAbsent(
        '$key|$ownGoal',
        () => _Scorer(name, ownGoal),
      );
      scorer.goals.add((minute, added, penalty));
    }

    for (final performance in data.performances) {
      final name =
          data.names[performance.playerInstanceId] ??
          performance.playerInstanceId;
      if (mine) {
        for (final goal in performance.goalDetails) {
          add(
            performance.playerInstanceId,
            name,
            goal.minute,
            goal.addedMinute,
            goal.isPenalty,
            false,
          );
        }
      } else {
        for (final goal in performance.ownGoalDetails) {
          add(
            performance.playerInstanceId,
            name,
            goal.minute,
            goal.addedMinute,
            false,
            true,
          );
        }
      }
    }
    for (final goal in _opponentGoals) {
      if (goal.isOwnGoal != mine) continue;
      add(
        goal.scorerName,
        goal.scorerName,
        goal.minute,
        goal.addedMinute,
        goal.type.contains(GoalType.penalty),
        goal.isOwnGoal,
      );
    }
    return scorers.values.toList()
      ..sort((a, b) => a.firstGoal.compareTo(b.firstGoal));
  }

  Widget _scorerColumn(List<_Scorer> scorers, {required bool left}) => Column(
    crossAxisAlignment: left
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    children: [
      for (final scorer in scorers)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Builder(
            builder: (context) {
              final minutes = scorer.goals
                  .where((goal) => goal.$1 != null)
                  .map(
                    (goal) =>
                        formatEventMinute(goal.$1, goal.$2, isPenalty: goal.$3),
                  )
                  .join(', ');
              final name =
                  scorer.name +
                  (scorer.ownGoal ? ' (${'fixtures.ownGoalsShort'.tr()})' : '');
              final strong = TextStyle(
                color: _c.text,
                fontWeight: FontWeight.w600,
              );
              final soft = TextStyle(color: _c.muted);
              return Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 12.5, height: 1.35),
                  children: left
                      ? [
                          TextSpan(text: name, style: strong),
                          if (minutes.isNotEmpty)
                            TextSpan(text: '  $minutes', style: soft),
                        ]
                      : [
                          if (minutes.isNotEmpty)
                            TextSpan(text: '$minutes  ', style: soft),
                          TextSpan(text: name, style: strong),
                        ],
                ),
                textAlign: left ? TextAlign.right : TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
        ),
    ],
  );

  Widget _tournamentBadge(double size) {
    final tournamentId = _fixture['tournamentId']?.toString() ?? '';
    final badge = TournamentBadge(
      version: widget.person.fifaVersion,
      tournamentId: tournamentId,
      size: size,
    );
    return widget.tournamentLogo == null
        ? badge
        : Image.asset(
            widget.tournamentLogo!,
            width: size,
            height: size,
            errorBuilder: (_, _, _) => badge,
          );
  }

  String get _competition => [
    widget.tournament,
    if ((_fixture['stage'] as String?)?.isNotEmpty == true)
      _fixture['stage'] as String,
  ].join(' · ');

  Widget _hero(String ownTeam, FixtureLineupData data, DateTime? date) {
    final c = _c;
    final left = _side(left: true, ownTeam: ownTeam);
    final right = _side(left: false, ownTeam: ownTeam);
    final mine = _scorers(data, mine: true);
    final theirs = _scorers(data, mine: false);
    String dateLabel = '—';
    if (date != null) {
      try {
        dateLabel = DateFormat(
          'EEE, dd/MM/yyyy',
          context.locale.toString(),
        ).format(date);
      } catch (_) {
        dateLabel = DateFormat('dd/MM/yyyy').format(date);
      }
    }
    final location = switch (_fixture['location']) {
      'home' => 'fixtures.home'.tr(),
      'away' => 'fixtures.away'.tr(),
      _ => 'fixtures.neutral'.tr(),
    };
    Widget club(
      ({
        String id,
        String? league,
        String name,
        Object? score,
        Object? penalties,
      })
      side,
    ) => Expanded(
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: Center(child: _logo(side.id, side.league, 50)),
          ),
          const SizedBox(height: 8),
          Text(
            side.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
    Widget meta(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: c.muted),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: c.muted, fontSize: 11.5)),
      ],
    );
    return Container(
      key: const ValueKey('fixture-hero'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.accent.withValues(alpha: .2)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(c.accent.withValues(alpha: .1), c.panel),
            c.panel,
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _tournamentBadge(16),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  _competition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              club(left),
              SizedBox(
                width: 112,
                child: Column(
                  children: [
                    SizedBox(
                      height: 52,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${left.score ?? '–'} – ${right.score ?? '–'}',
                          style: TextStyle(
                            color: c.text,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (left.penalties != null && right.penalties != null)
                      Text(
                        '(${left.penalties}–${right.penalties} '
                        '${'fixtures.penaltyMedium'.tr()})',
                        style: TextStyle(color: c.muted, fontSize: 11.5),
                      ),
                    const SizedBox(height: 6),
                    MatchResultChip(fixture: _fixture),
                  ],
                ),
              ),
              club(right),
            ],
          ),
          if (mine.isNotEmpty || theirs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: c.line.withValues(alpha: .6)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _scorerColumn(_away ? theirs : mine, left: true),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    TablerIcons.ballFootball,
                    size: 16,
                    color: c.muted,
                  ),
                ),
                Expanded(
                  child: _scorerColumn(_away ? mine : theirs, left: false),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 6,
            children: [
              meta(TablerIcons.calendarMonth, dateLabel),
              meta(TablerIcons.soccerField, location),
            ],
          ),
        ],
      ),
    );
  }

  static String _percent(num value) {
    final share = value <= 1 ? value * 100 : value;
    final text = share == share.roundToDouble()
        ? share.round().toString()
        : share.toStringAsFixed(1).replaceAll('.', ',');
    return '$text%';
  }

  Widget _compare(
    String label, {
    num? mine,
    num? theirs,
    Widget? mineChild,
    Widget? theirsChild,
    String Function(num)? format,
    bool bar = false,
  }) {
    final c = _c;
    String text(num? value) =>
        value == null ? '—' : (format?.call(value) ?? '$value');
    Widget value(num? number, Widget? child, {required bool start}) => Align(
      alignment: start ? Alignment.centerLeft : Alignment.centerRight,
      child:
          child ??
          Text(
            text(number),
            style: TextStyle(
              color: number == null ? c.muted : c.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
    );
    final left = _away ? theirs : mine, right = _away ? mine : theirs;
    final total = (left ?? 0) + (right ?? 0);
    final ownColor = c.accent, otherColor = c.muted.withValues(alpha: .55);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                child: value(
                  left,
                  _away ? theirsChild : mineChild,
                  start: true,
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 64,
                child: value(
                  right,
                  _away ? mineChild : theirsChild,
                  start: false,
                ),
              ),
            ],
          ),
          if (bar && left != null && right != null && total > 0) ...[
            const SizedBox(height: 7),
            SizedBox(
              height: 5,
              child: Row(
                children: [
                  Expanded(
                    flex: (left / total * 1000).round().clamp(1, 999),
                    child: _barSegment(_away ? otherColor : ownColor),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    flex: (right / total * 1000).round().clamp(1, 999),
                    child: _barSegment(_away ? ownColor : otherColor),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _barSegment(Color color) => Container(
    height: 5,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );

  Widget _statistics(FixtureLineupData lineup) {
    if (!_manager) return _playerStatistics();
    final possession = _fixture['teamPossession'] as num?;
    final ownPossession = possession == null
        ? null
        : (possession <= 1 ? possession * 100 : possession);
    int total(int Function(ManagerFixturePlayerPerformance) value) =>
        lineup.performances.fold<int>(0, (sum, row) => sum + value(row));
    final counted = lineup.performances.isNotEmpty;
    int? own(int Function(ManagerFixturePlayerPerformance) value) =>
        counted ? total(value) : null;
    final opponent = OpponentStats.decode(_fixture['opponentStats']);
    final events = [
      (
        'fixtures.yellowCards'.tr(),
        own((row) => row.yellowCardDetails.length),
        opponent.yellowCards,
      ),
      (
        'fixtures.redCards'.tr(),
        own((row) => row.redCardDetails.length),
        opponent.redCards,
      ),
      (
        'fixtures.ownGoals'.tr(),
        own((row) => row.ownGoalDetails.length),
        opponent.ownGoals,
      ),
      (
        'Pênaltis perdidos',
        own((row) => row.missedPenaltyDetails.length),
        opponent.missedPenalties,
      ),
      (
        'injuries.injuries'.tr(),
        own((row) => row.injuryDetails.length),
        opponent.injuries,
      ),
    ];
    final rows = <Widget>[
      if (ownPossession != null)
        _compare(
          'Posse de bola',
          mine: ownPossession,
          theirs: 100 - ownPossession,
          format: _percent,
          bar: true,
        ),
      if (_fixture['playerTeamShoutsCount'] != null ||
          _fixture['opponentTeamShotsCount'] != null)
        _compare(
          'fixtures.shots'.tr(),
          mine: _fixture['playerTeamShoutsCount'] as num?,
          theirs: _fixture['opponentTeamShotsCount'] as num?,
          bar: true,
        ),
      if (_fixture['passAccuracy'] != null || opponent.passAccuracy != null)
        _compare(
          'Precisão de passe',
          mine: _fixture['passAccuracy'] as num?,
          theirs: opponent.passAccuracy,
          format: _percent,
        ),
      for (final (label, mine, theirs) in events)
        if ((mine ?? 0) > 0 || (theirs ?? 0) > 0)
          _compare(label, mine: mine, theirs: theirs),
      if (_fixture['position'] != null || opponent.position != null)
        _compare(
          'Posição na tabela',
          mineChild: _fixture['position'] == null ? null : _positionIndicator(),
          theirs: opponent.position,
          format: (value) => '$valueº',
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final left = _side(left: true, ownTeam: ''),
        right = _side(left: false, ownTeam: '');
    return DashboardSection(
      key: const ValueKey('fixture-statistics'),
      title: 'Estatísticas',
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _logo(left.id, left.league, 18),
          const SizedBox(width: 6),
          Text('x', style: TextStyle(color: _c.muted, fontSize: 11)),
          const SizedBox(width: 6),
          _logo(right.id, right.league, 18),
        ],
      ),
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, color: _c.line.withValues(alpha: .4)),
            row,
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: _c.text, fontSize: 13)),
        ),
        if (value is Widget)
          value
        else
          Text(
            value?.toString() ?? '—',
            style: TextStyle(
              color: _c.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
      ],
    ),
  );

  Widget _playerStatistics() {
    final rows = [
      ('fixtures.rating'.tr(), _fixture['rating']),
      ('fixtures.goals'.tr(), _fixture['goalsCount']),
      ('fixtures.assists'.tr(), _fixture['assistsCount']),
      ('fixtures.saves'.tr(), _fixture['savesCount']),
      ('fixtures.minutesPlayed'.tr(), _fixture['minsPlayed']),
      ('fixtures.yellowCards'.tr(), _fixture['yellowCards']),
      ('fixtures.redCards'.tr(), _fixture['redCards']),
    ];
    return DashboardSection(
      title: 'Sua atuação',
      child: Column(
        children: [
          for (final (i, (label, value)) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, color: _c.line.withValues(alpha: .4)),
            _infoRow(label, value),
          ],
          if (_fixture['position'] != null) ...[
            Divider(height: 1, color: _c.line.withValues(alpha: .4)),
            _infoRow('Posição na tabela', _positionIndicator()),
          ],
        ],
      ),
    );
  }

  Widget _positionIndicator() => FutureBuilder<FixtureTablePosition>(
    future: _tablePosition,
    builder: (context, snapshot) => snapshot.hasData
        ? FixturePositionIndicator(value: snapshot.data!)
        : Text(
            '${_fixture['position'] ?? '—'}',
            style: TextStyle(
              color: AppColors.of(context).text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
  );

  Widget _tabHeader(String ownTeam) {
    final c = _c;
    final left = _side(left: true, ownTeam: ownTeam);
    final right = _side(left: false, ownTeam: ownTeam);
    Widget name(String text, TextAlign align) => Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: c.text,
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _logo(left.id, left.league, 30),
              const SizedBox(width: 8),
              Expanded(child: name(left.name, TextAlign.start)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '${left.score ?? '–'} – ${right.score ?? '–'}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
              ),
              Expanded(child: name(right.name, TextAlign.end)),
              const SizedBox(width: 8),
              _logo(right.id, right.league, 30),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _competition,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: c.muted),
          ),
        ],
      ),
    );
  }

  Widget _photo(FixtureLineupData data, String playerId, double width) {
    final opponent = data.opponentLineup?.squad.players[playerId];
    return ProfilePortrait(
      version: widget.person.fifaVersion,
      realPlayerId:
          data.avatars[playerId]?.realPlayerId ??
          opponent?['realPlayerId'] as String?,
      customAvatarFilePath:
          data.avatars[playerId]?.path ??
          opponent?['customAvatarFilePath'] as String?,
      width: width,
      height: width * 1.3,
    );
  }

  String? _opponentPlayerOfMatch(FixtureLineupData data) {
    final potm = _fixture['playerOfTheMatchId']?.toString();
    final squad = data.opponentLineup?.squad.players;
    if (potm == null || squad == null || _fixture['isPotmFromMyTeam'] == 1) {
      return null;
    }
    if (squad.containsKey(potm)) return potm;
    final wanted = potm.trim().toLowerCase();
    return squad.entries
        .where((e) => '${e.value['name'] ?? ''}'.trim().toLowerCase() == wanted)
        .firstOrNull
        ?.key;
  }

  Widget _highlights(FixtureLineupData data) {
    final opponentPotm = _opponentPlayerOfMatch(data);
    final potm = opponentPotm ?? _fixture['playerOfTheMatchId'] as String?;
    final opponent = data.opponentLineup;
    double? rating(String id) => [
      ...data.performances,
      if (id == opponentPotm) ...?opponent?.performances,
    ].where((row) => row.playerInstanceId == id).firstOrNull?.avgRating;
    final rated =
        data.performances.where((row) => row.avgRating != null).toList()
          ..sort((a, b) => b.avgRating!.compareTo(a.avgRating!));
    final others = rated
        .where((row) => row.playerInstanceId != potm)
        .take(potm == null ? 3 : 2)
        .map((row) => row.playerInstanceId);
    final ids = [?potm, ...others];
    if (ids.isEmpty) return const SizedBox.shrink();
    final ownId = _fixture['playerTeamId'] as String;
    final ownLeague = _fixture['playerTeamLeagueId'] as String?;
    return DashboardSection(
      key: const ValueKey('fixture-highlights'),
      title: 'Destaques',
      child: Column(
        children: [
          for (final (i, id) in ids.indexed) ...[
            if (i > 0) Divider(height: 1, color: _c.line.withValues(alpha: .4)),
            InkWell(
              key: ValueKey('fixture-highlight-$id'),
              borderRadius: BorderRadius.circular(12),
              onTap: !_manager
                  ? null
                  : id == opponentPotm
                  ? () => _openMatchPlayer(data, id, opponent: opponent)
                  : () => _openMatchPlayer(data, id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    _photo(data, id, 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            id == opponentPotm
                                ? opponent?.names[id] ?? id
                                : data.names[id] ?? id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _c.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (id == potm)
                            Row(
                              children: [
                                const Icon(
                                  TablerIcons.starFilled,
                                  color: AppColors.missedEvent,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    id == opponentPotm
                                        ? '${'fixtures.playerOfTheMatch'.tr()} · ${widget.opponent}'
                                        : 'fixtures.playerOfTheMatch'.tr(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.missedEvent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                _logo(ownId, ownLeague, 13),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    data.positions[id] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _c.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    MatchRating(rating(id), size: 13),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openMatchPlayer(
    FixtureLineupData data,
    String id, {
    OpponentLineup? opponent,
  }) async {
    final own = _teamName(
      _fixture['playerTeamId']?.toString() ?? widget.person.teamId,
      _fixture['playerTeamLeagueId']?.toString() ?? widget.person.leagueId,
    );
    final p = (opponent?.performances ?? data.performances)
        .where((p) => p.playerInstanceId == id)
        .firstOrNull;
    final profile =
        data.roster.any((r) => r['playerId'] == id) ||
        data.playerProfiles.containsKey(id);
    final name = opponent?.names[id] ?? data.names[id] ?? 'Jogador';
    final player = opponent?.squad.players[id];
    final away = _fixture['location'] == 'away';
    final score =
        '${_fixture['playerTeamScore'] ?? 0} × ${_fixture['oppositeTeamScore'] ?? 0}';
    final reversed =
        '${_fixture['oppositeTeamScore'] ?? 0} × ${_fixture['playerTeamScore'] ?? 0}';
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FixturePlayerPerformancePage(
          name: name,
          team: opponent == null ? own : widget.opponent,
          position: opponent == null
              ? data.positions[id] ?? ''
              : positionShortName(player?['positionId'] as String?),
          match: away
              ? '${widget.opponent}  $reversed  $own'
              : '$own  $score  ${widget.opponent}',
          date: DateTime.tryParse('${_fixture['date']}'),
          extraTime: _fixture['extraTime'] == 1,
          performance: p,
          captain:
              opponent == null &&
              FixtureCaptaincy.decode(_fixture['captaincy'])
                  .players(data.performances)
                  .contains(id),
          playerOfMatch:
              _fixture['playerOfTheMatchId'] == id ||
              (opponent != null && id == _opponentPlayerOfMatch(data)),
          avatar: (radius) => PlayerAvatar(
            fifaVersion: widget.person.fifaVersion,
            radius: radius,
            realPlayerId:
                player?['realPlayerId'] as String? ??
                data.avatars[id]?.realPlayerId,
            customAvatarFilePath:
                player?['customAvatarFilePath'] as String? ??
                data.avatars[id]?.path,
          ),
          onViewPlayer: profile ? () => _openRosterPlayer(data, id) : null,
        ),
      ),
    );
  }

  Future<void> _openRosterPlayer(FixtureLineupData data, String id) async {
    final row =
        data.roster.where((item) => item['playerId'] == id).firstOrNull ??
        data.playerProfiles[id];
    if (row == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ViewPlayerPage(person: widget.person, row: row),
      ),
    );
  }

  Widget _playerPerformance(FixtureLineupData data) {
    final performance = data.performances.first;
    final duration = getManagerFixtureDurationMinutes(
      extraTime: false,
      performance: performance,
    );
    final goals = getSortedDetails(performance.goalDetails)
        .where((goal) => goal.minute != null)
        .map(
          (goal) => formatEventMinute(
            goal.minute,
            goal.addedMinute,
            isPenalty: goal.isPenalty,
          ),
        )
        .join(', ');
    return DashboardSection(
      title: 'fixtures.performanceDetails'.tr(),
      action: DashboardLink(
        'common.edit'.tr(),
        onTap: () => _openPlayerPerformance(data),
      ),
      child: Column(
        children: [
          if (goals.isNotEmpty) _infoRow('fixtures.goals'.tr(), goals),
          if (performance.substitutionDetails.isNotEmpty)
            _infoRow(
              'fixtures.minutes'.tr(),
              getManagerPlayerPlayedMinutes(performance, duration),
            ),
          if (goals.isEmpty && performance.substitutionDetails.isEmpty)
            const MatchHint(
              'Registre gols, cartões e substituições desta partida.',
            ),
        ],
      ),
    );
  }

  Widget _shortcuts() {
    final otherId = _fixture['oppositeTeamId'] as String;
    final otherLeague = _fixture['oppositeTeamLeagueId'] as String?;
    final headToHead = MatchActionTile(
      key: const ValueKey('fixture-head-to-head'),
      icon: Icons.compare_arrows_rounded,
      title: 'fixtures.headToHead'.tr(),
      subtitle: 'Contra ${widget.opponent}',
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => HeadToHeadDetailPage(
            person: widget.person,
            opponentId: otherId,
            opponentLeagueId: otherLeague,
          ),
        ),
      ),
    );
    if (!_manager) return headToHead;
    final done = _press?.done == true;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MatchActionTile(
              key: const ValueKey('fixture-press-conference'),
              icon: TablerIcons.microphone,
              title: 'Coletiva de imprensa',
              subtitle: done ? 'Concluída' : 'Pendente',
              highlighted: done,
              onTap: _pressConference,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: headToHead),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(_fixture['date'] as String? ?? '');
    final c = _c;
    final favorite = _fixture['isFavorite'] == 1;
    return Theme(
      data: careerDetailTheme(context),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(64),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TabBar(
                  key: ValueKey('fixture-details-tabs'),
                  labelPadding: EdgeInsets.symmetric(horizontal: 6),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  tabs: [
                    Tab(text: 'Principal'),
                    Tab(text: 'Linha do Tempo'),
                    Tab(text: 'Formação'),
                  ],
                ),
              ),
            ),
            actions: [
              if (_fcScore)
                IconButton(
                  key: const Key('fixture-complete-api'),
                  onPressed: _completeFromApi,
                  tooltip: _fcLinked
                      ? 'Vinculada à API · completar de novo'
                      : 'Completar com a API',
                  icon: Icon(
                    TablerIcons.cloudDownload,
                    color: _fcLinked ? c.accent : null,
                  ),
                ),
              IconButton(
                onPressed: _favorite,
                tooltip: 'trophies.favorites'.tr(),
                icon: Icon(
                  favorite ? TablerIcons.heartFilled : TablerIcons.heart,
                  color: favorite ? c.accent : null,
                ),
              ),
              IconButton(
                onPressed: _edit,
                tooltip: 'common.edit'.tr(),
                icon: const Icon(TablerIcons.pencil),
              ),
              PopupMenuButton<String>(
                key: const ValueKey('fixture-more'),
                tooltip: 'Mais opções',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'delete') _delete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(TablerIcons.trash, size: 20, color: c.danger),
                        const SizedBox(width: 12),
                        Text(
                          'fixtures.removeFixture'.tr(),
                          style: TextStyle(color: c.danger),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: FutureBuilder<GameCatalog>(
            future: GameCatalog.load(),
            builder: (context, catalogSnapshot) {
              if (!catalogSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final ownTeam = _teamName(
                _fixture['playerTeamId'] as String,
                _fixture['playerTeamLeagueId'] as String?,
              );
              return FutureBuilder<FixtureLineupData>(
                future: _lineup,
                builder: (context, lineupSnapshot) {
                  if (lineupSnapshot.hasError) {
                    return Center(child: Text('${lineupSnapshot.error}'));
                  }
                  if (!lineupSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = lineupSnapshot.data!;
                  final captaincy = FixtureCaptaincy.decode(
                    _fixture['captaincy'],
                  );
                  final captainIds = captaincy.players(data.performances);
                  final notes = (_fixture['notes'] as String?)?.trim() ?? '';
                  final savedFormation =
                      data.ownFormation ??
                      FixtureFormation.decode(_fixture['matchLineup']);
                  FixtureFormation available() => FixtureFormation.initial(
                    roster: data.roster,
                    names: data.names,
                    positions: data.positionIds,
                    avatars: data.avatars,
                    performances: data.performances,
                    useRosterWhenEmpty: false,
                  );
                  return TabBarView(
                    children: [
                      ListView(
                        primary: false,
                        key: const PageStorageKey('fixture-principal'),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        children: [
                          _hero(ownTeam, data, date),
                          _statistics(data),
                          if (!_manager) _playerPerformance(data),
                          if (_manager) ...[
                            _highlights(data),
                            if (data.performances.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: FixtureFormationView(
                                  key: const ValueKey('principal-formation'),
                                  person: widget.person,
                                  embedded: true,
                                  saved: savedFormation,
                                  available: available(),
                                  performances: data.performances,
                                  captainIds: captainIds,
                                  header: captaincy.isRecorded
                                      ? Container(
                                          padding: const EdgeInsets.fromLTRB(
                                            14,
                                            8,
                                            14,
                                            8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.panel,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(color: c.line),
                                          ),
                                          child: FixtureCaptainPanel(
                                            captaincy: captaincy,
                                            performances: data.performances,
                                            names: data.names,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                  onPlayerTap: (id) =>
                                      _openMatchPlayer(data, id),
                                ),
                              ),
                          ],
                          if (notes.isNotEmpty)
                            DashboardSection(
                              key: const ValueKey('fixture-notes'),
                              title: 'fixtures.notesOpt'.tr(),
                              child: Text(
                                notes,
                                style: TextStyle(
                                  color: c.text,
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          _shortcuts(),
                        ],
                      ),
                      FixtureTimelineView(
                        fixture: _fixture,
                        performances: data.performances,
                        names: data.names,
                        header: _tabHeader(ownTeam),
                      ),
                      FixtureFormationsPage(
                        fifaVersion: widget.person.fifaVersion,
                        ownName: ownTeam,
                        opponentName: widget.opponent,
                        ownTeam: (
                          id: _fixture['playerTeamId'] as String,
                          leagueId: _fixture['playerTeamLeagueId'] as String?,
                        ),
                        opponentTeam: (
                          id: _fixture['oppositeTeamId'] as String,
                          leagueId: _fixture['oppositeTeamLeagueId'] as String?,
                        ),
                        opponent:
                            data.opponentLineup ??
                            OpponentLineup.decode(_fixture['opponentLineup']),
                        header: _tabHeader(ownTeam),
                        onOpponentPlayerTap: (opponent, id) =>
                            _openMatchPlayer(data, id, opponent: opponent),
                        own: FixtureFormationView(
                          person: widget.person,
                          saved: savedFormation,
                          available: available(),
                          performances: data.performances,
                          captainIds: captainIds,
                          header: _tabHeader(ownTeam),
                          onPlayerTap: !_manager
                              ? null
                              : (id) => _openMatchPlayer(data, id),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Scorer {
  _Scorer(this.name, this.ownGoal);
  final String name;
  final bool ownGoal;
  final List<(int?, int?, bool)> goals = [];

  int get firstGoal => goals
      .map((goal) => eventSortValue(goal.$1, goal.$2))
      .reduce((a, b) => a < b ? a : b);
}

class FixtureLineupData {
  const FixtureLineupData(
    this.roster,
    this.performances,
    this.names,
    this.positions, {
    this.avatars = const {},
    this.positionIds = const {},
    this.ownFormation,
    this.opponentLineup,
    this.playerProfiles = const {},
  });
  final List<Map<String, Object?>> roster;
  final List<ManagerFixturePlayerPerformance> performances;
  final Map<String, String> names, positions;
  final Map<String, ({String? realPlayerId, String? path})> avatars;
  final Map<String, String?> positionIds;
  final FixtureFormation? ownFormation;
  final OpponentLineup? opponentLineup;
  final Map<String, Map<String, Object?>> playerProfiles;
}
