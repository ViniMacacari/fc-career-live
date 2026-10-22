import '../../Common/FixtureNavigation.dart';
import '../../Common/FixtureCaptainPanel.dart';
import '../../Common/FixtureFormationView.dart';
import '../../models/FixtureCaptaincy.dart';
import '../../utils/AppColors.dart';
import '../../FcScore/FcScoreRepository.dart';
import '../../utils/themes.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import 'package:uuid/uuid.dart';

import '../../Common/Seasons/CreateSeason.dart';
import '../../Common/SelectTeam/SelectTeamPage.dart';
import '../../Common/SelectTournamentPage.dart';
import '../../Common/StagePicker.dart';
import '../../models/ManagerFixture.dart';
import '../../models/FixtureFormation.dart';
import '../../models/OpponentLineup.dart';
import '../../models/ManagerFixturePlayerPerformance.dart';
import '../../models/Person.dart';
import '../../models/PlayerFixture.dart' show GameLocation;
import '../../models/PressConference.dart';
import '../../models/Season.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/CareerDatePicker.dart';
import '../../Twitter/TwitterGenerationService.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../../utils/ai/AIModelService.dart';
import '../../utils/competitions/CompetitionFormats.dart';
import '../../utils/competitions/TournamentAutomation.dart';
import '../../utils/databaseUtils.dart';
import '../../utils/managerFixturePerformanceUtils.dart';
import 'OpponentGoals/OpponentGoalsPanel.dart';
import 'Performances/PerformanceDetails.dart';
import 'Performances/TeamPlayersPerformanceGrid.dart';
import 'PressConferencePage.dart';
import 'SelectTeamPlayerPage.dart';
import 'SelectPlayerOfMatchSheet.dart';
import 'OpponentLineupEditor.dart';
import '../../Common/MatchUi.dart';
import '../../FcScore/FcScoreQuickImportPage.dart';

class ManagerFixtureForm extends StatefulWidget {
  const ManagerFixtureForm({
    super.key,
    required this.person,
    this.existing,
    this.seasonId,
    this.preloaded,
    this.opponentLineupLoader,
    this.preloadedPerformances,
    this.onFixtureSaved,
  });
  final Person person;
  final Map<String, Object?>? existing;

  final String? seasonId;
  @visibleForTesting
  final Future<OpponentLineup?> Function(CatalogItem, DateTime?)?
  opponentLineupLoader;
  @visibleForTesting
  final List<ManagerFixturePlayerPerformance>? preloadedPerformances;
  @visibleForTesting
  final Future<void> Function(
    Map<String, Object?>,
    List<ManagerFixturePlayerPerformance>,
  )?
  onFixtureSaved;

  @visibleForTesting
  final ({
    List<Season> seasons,
    List<Map<String, Object?>> players,
    List<Map<String, Object?>> roster,
  })?
  preloaded;

  @override
  State<ManagerFixtureForm> createState() => _ManagerFixtureFormState();
}

class _ManagerFixtureFormState extends State<ManagerFixtureForm> {
  late final String _id =
      widget.existing?['id'] as String? ?? const Uuid().v4();
  late Future<void> _ready = _load();

  final _stage = TextEditingController();
  final _possession = TextEditingController();
  final _passAccuracy = TextEditingController();
  final _myShots = TextEditingController();
  final _otherShots = TextEditingController();
  final _position = TextEditingController();
  final _notes = TextEditingController();

  final _otherPassAccuracy = TextEditingController();
  final _otherYellowCards = TextEditingController();
  final _otherRedCards = TextEditingController();
  final _otherOwnGoals = TextEditingController();
  final _otherMissedPenalties = TextEditingController();
  final _otherInjuries = TextEditingController();
  final _otherPosition = TextEditingController();
  bool _statsOpen = false, _notesOpen = false;

  List<Season> _seasons = const [];
  String? _seasonId;
  DateTime? _date;

  CompetitionFormat Function(String)? _formatOf;
  CatalogItem? _opponent, _tournament;
  GameLocation _location = GameLocation.home;
  int _myScore = 0, _otherScore = 0;
  bool _penalties = false;
  int _myPenalties = 0, _otherPenalties = 0;
  bool _extraTime = false;
  bool _national = false;
  String? _playerOfMatchId;
  bool _saving = false;

  List<Map<String, Object?>> _roster = const [];
  Map<String, String> _names = const {}, _positions = const {};
  Map<String, Map<String, Object?>> _playerDetails = const {};
  Map<String, String?> _positionIds = const {};
  List<ManagerFixturePlayerPerformance> _performances = [];
  final Set<String> _deletedIds = {};
  Future<List<Map<String, Object?>>>? _seasonStatsFuture;
  List<OpponentGoalDetails> _opponentGoals = [];
  OpponentLineup _opponentLineup = OpponentLineup.unselected();
  FixtureFormation? _matchFormation;
  bool _pitchSelected = false;
  bool _opponentLoading = false, _opponentDirty = false;
  int _opponentLoadToken = 0;
  bool _opponentLineupSelected = false;
  FixtureCaptaincy _captaincy = const FixtureCaptaincy();

  bool get _hasNationalTeam => widget.person.nationalCoachingTeamId != null;

  static const lineupViewKey = 'fixture_lineup_view';

  Future<bool> _savedPitchView() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(lineupViewKey) == 'pitch';
    } catch (_) {
      return false;
    }
  }

  Future<void> _rememberPitchView(bool pitch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lineupViewKey, pitch ? 'pitch' : 'list');
    } catch (_) {}
  }

  void _setPitchView(bool pitch) {
    if (pitch == _pitchSelected) return;
    setState(() => _pitchSelected = pitch);
    _rememberPitchView(pitch);
  }

  ({String id, String? leagueId}) get _ownTeam => _national
      ? (
          id: widget.person.nationalCoachingTeamId!,
          leagueId: GameCatalog.nationalLeagueId,
        )
      : (id: widget.person.teamId, leagueId: widget.person.leagueId);

  Future<void> _load() async {
    final service = SqlService.instance;
    _pitchSelected = await _savedPitchView();
    final catalog = await GameCatalog.load();
    final preloaded = widget.preloaded;
    _seasons = preloaded?.seasons ?? await service.getSeasons(widget.person.id);
    _formatOf = preloaded != null
        ? (id) => CompetitionFormat.of(id, widget.person.fifaVersion)
        : await TournamentAutomation.formats(widget.person);
    final players =
        preloaded?.players ?? await service.getCustomPlayers(widget.person.id);
    _playerDetails = {
      for (final player in players) player['id'] as String: player,
    };
    _names = {
      for (final row in players)
        row['id'] as String: row['name']?.toString() ?? '',
    };
    _positionIds = {
      for (final row in players)
        row['id'] as String: row['positionId'] as String?,
    };
    _positions = {
      for (final entry in _positionIds.entries)
        entry.key: positionShortName(entry.value),
    };
    final row = widget.existing;
    _seasonId =
        row?['seasonId'] as String? ??
        widget.seasonId ??
        _seasons.firstOrNull?.id;
    if (row != null) {
      int number(String key) => (row[key] as num?)?.toInt() ?? 0;
      String text(String key) => row[key]?.toString() ?? '';
      _date = DateTime.tryParse(text('date'));
      _location = GameLocation.values.byName(text('location'));
      _myScore = number('playerTeamScore');
      _otherScore = number('oppositeTeamScore');
      _penalties =
          row['playerTeamPenaltiesScore'] != null ||
          row['oppositeTeamPenaltiesScore'] != null;
      _myPenalties = number('playerTeamPenaltiesScore');
      _otherPenalties = number('oppositeTeamPenaltiesScore');
      _extraTime = row['extraTime'] == 1;
      _national = row['playerTeamLeagueId'] == GameCatalog.nationalLeagueId;
      _playerOfMatchId = row['playerOfTheMatchId'] as String?;
      _captaincy = FixtureCaptaincy.decode(row['captaincy']);
      _matchFormation = FixtureFormation.decode(row['matchLineup']);
      _stage.text = text('stage');
      _possession.text = text('teamPossession');
      _passAccuracy.text = text('passAccuracy');
      _myShots.text = text('playerTeamShoutsCount');
      _otherShots.text = text('opponentTeamShotsCount');
      _position.text = text('position');
      _notes.text = text('notes');
      final opponentStats = OpponentStats.decode(row['opponentStats']);
      _otherPassAccuracy.text = opponentStats.passAccuracy?.toString() ?? '';
      _otherYellowCards.text = opponentStats.yellowCards?.toString() ?? '';
      _otherRedCards.text = opponentStats.redCards?.toString() ?? '';
      _otherOwnGoals.text = opponentStats.ownGoals?.toString() ?? '';
      _otherMissedPenalties.text =
          opponentStats.missedPenalties?.toString() ?? '';
      _otherInjuries.text = opponentStats.injuries?.toString() ?? '';
      _otherPosition.text = opponentStats.position?.toString() ?? '';
      _opponentGoals = decodeOpponentGoals(row['opponentGoalDetails']);
      final savedLineup = OpponentLineup.decode(row['opponentLineup']);
      if (savedLineup != null) {
        _opponentLineup = savedLineup;
        _opponentDirty = true;
      }
      final opponentId = text('oppositeTeamId');
      final opponentLeague = row['oppositeTeamLeagueId'] as String?;
      _opponent = CatalogItem(
        opponentId,
        catalog.teamLabel(
          widget.person.fifaVersion,
          opponentId,
          leagueId: opponentLeague,
        ),
        leagueId: opponentLeague,
      );
      _tournament = CatalogItem(
        text('tournamentId'),
        await _tournamentLabel(catalog, text('tournamentId')),
      );
      _performances = _sorted(
        widget.preloadedPerformances ??
            (preloaded != null
                ? []
                : await service.getPerformanceModels(widget.person.id, _id)),
      );
    }
    await _loadRoster();
    if (row != null && preloaded == null) {
      try {
        final lineups = await FcScoreRepository(sql: service)
            .fixturePitchLineups(widget.person, row);
        _matchFormation = lineups.own ?? _matchFormation;
        _opponentLineup = lineups.opponent ?? _opponentLineup;
      } catch (_) {}
    }
    if (_opponent != null && !_opponentDirty) await _rememberOpponent();
  }

  Future<String> _tournamentLabel(GameCatalog catalog, String id) async {
    final builtIn = await catalog.tournaments(widget.person.fifaVersion);
    final custom = widget.preloaded != null
        ? const []
        : await SqlService.instance.getCustomTournaments(
            widget.person.fifaVersion,
          );
    final league = id.startsWith('league:')
        ? catalog
              .leagues(widget.person.fifaVersion)
              .where((item) => item.id == id.substring(7))
              .firstOrNull
        : null;
    return builtIn.where((item) => item.id == id).firstOrNull?.label ??
        custom.where((item) => item.id == id).firstOrNull?.name ??
        league?.label ??
        id;
  }

  Future<void> _loadRoster() async {
    final seasonId = _seasonId;
    if (widget.preloaded != null || seasonId == null) {
      _roster = widget.preloaded?.roster ?? const [];
      return;
    }
    final service = SqlService.instance;
    _roster =
        (_national
                ? await service.getNationalTeamPlayers(
                    widget.person.id,
                    seasonId,
                  )
                : await service.getTeamPlayers(widget.person.id, seasonId))
            .where((row) => row['playerId'] != null)
            .toList();
  }

  @override
  void dispose() {
    for (final controller in [
      _stage,
      _possession,
      _passAccuracy,
      _myShots,
      _otherShots,
      _position,
      _notes,
      _otherPassAccuracy,
      _otherYellowCards,
      _otherRedCards,
      _otherOwnGoals,
      _otherMissedPenalties,
      _otherInjuries,
      _otherPosition,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<ManagerFixturePlayerPerformance> _sorted(
    List<ManagerFixturePlayerPerformance> rows,
  ) => rows
    ..sort(
      (a, b) =>
          getPositionPriority(_positionIds[a.playerInstanceId])
              .compareTo(getPositionPriority(_positionIds[b.playerInstanceId])),
    );

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _applyAutoScore() {
    _myScore =
        calculateManagerFixtureAutoFilledTeamScore(_performances) +
        _opponentGoals.where((goal) => goal.isOwnGoal).length;
    _otherScore =
        _performances.fold<int>(
          0,
          (sum, item) => sum + item.ownGoalDetails.length,
        ) +
        _opponentGoals.where((goal) => !goal.isOwnGoal).length;
  }

  Future<void> _pickOpponent() async {
    final selected = await Navigator.of(context).push<CatalogItem>(
      MaterialPageRoute(
        builder: (_) => SelectTeamPage(
          fifaVersion: widget.person.fifaVersion,
          selectedTeamId: _opponent?.id,
          selectedLeagueId: _opponent?.leagueId,
          initialLeagueId: _opponent?.leagueId ?? _ownTeam.leagueId,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    if (selected.id == _opponent?.id &&
        selected.leagueId == _opponent?.leagueId) {
      return;
    }
    setState(() {
      _opponent = selected;
      _opponentDirty = false;
      _opponentLineup = OpponentLineup.unselected();
      _opponentGoals = [];
      for (final controller in [
        _otherYellowCards,
        _otherRedCards,
        _otherOwnGoals,
        _otherMissedPenalties,
        _otherInjuries,
      ]) {
        controller.clear();
      }
    });
    await _rememberOpponent();
  }

  Future<void> _rememberOpponent() async {
    final team = _opponent;
    if (team == null || _opponentDirty) return;
    final token = ++_opponentLoadToken;
    if (mounted) setState(() => _opponentLoading = true);
    try {
      final remembered = widget.opponentLineupLoader != null
          ? await widget.opponentLineupLoader!(team, _date ?? _defaultDate())
          : widget.preloaded != null
          ? null
          : await SqlService.instance.getRememberedOpponentLineup(
              personId: widget.person.id,
              fifaVersion: widget.person.fifaVersion,
              teamId: team.id,
              leagueId: team.leagueId,
              beforeDate: _date ?? _defaultDate(),
              excludeFixtureId: _id,
            );
      if (mounted && token == _opponentLoadToken && !_opponentDirty) {
        setState(
          () => _opponentLineup =
              (remembered?.forNewMatch() ?? OpponentLineup.unselected())
                  .withRecordedGoals(_opponentGoals),
        );
      }
    } catch (_) {
      if (mounted && token == _opponentLoadToken) {
        _message(
          'Não foi possível carregar a escalação anterior. Você pode preencher os nomes.',
        );
      }
    } finally {
      if (mounted && token == _opponentLoadToken) {
        setState(() => _opponentLoading = false);
      }
    }
  }

  void _changeOpponentLineup(OpponentLineup value) {
    final before = _opponentLineup;
    final recorded = value.mergeGoals(_opponentGoals, before: before);
    final next = value.withRecordedGoals(recorded);
    int count(
      OpponentLineup data,
      int Function(ManagerFixturePlayerPerformance) read,
    ) => data.performances.fold<int>(0, (n, p) => n + read(p));
    for (final (controller, read)
        in <
          (TextEditingController, int Function(ManagerFixturePlayerPerformance))
        >[
          (_otherYellowCards, (p) => p.yellowCardDetails.length),
          (_otherRedCards, (p) => p.redCardDetails.length),
          (_otherOwnGoals, (p) => p.ownGoalDetails.length),
          (_otherMissedPenalties, (p) => p.missedPenaltyDetails.length),
          (_otherInjuries, (p) => p.injuryDetails.length),
        ]) {
      if (controller.text.isEmpty ||
          controller.text == '${count(before, read)}') {
        final number = count(next, read);
        controller.text = number == 0 ? '' : '$number';
      }
    }
    setState(() {
      _opponentDirty = true;
      _opponentLineup = next;
      _opponentGoals = recorded;
      _applyAutoScore();
    });
  }

  Future<void> _pickTournament() async {
    final selected = await Navigator.of(context).push<CatalogItem>(
      MaterialPageRoute(
        builder: (_) =>
            SelectTournamentPage(fifaVersion: widget.person.fifaVersion),
      ),
    );
    if (selected != null) setState(() => _tournament = selected);
  }

  CompetitionFormat get _format {
    final tournament = _tournament;
    return tournament == null
        ? const CompetitionFormat.open()
        : _formatOf?.call(tournament.id) ?? const CompetitionFormat.open();
  }

  Future<void> _pickStage() async {
    final tournament = _tournament;
    final date = _date;
    final suggested = tournament == null
        ? null
        : await suggestStage(
            widget.person,
            tournamentId: tournament.id,
            seasonId: date == null ? _seasonId : _seasonFor(date) ?? _seasonId,
            format: _format,
            date: date,
            excludeFixtureId: _id,
          );
    if (!mounted) return;
    final stage = await showStagePicker(
      context,
      format: _format,
      current: _stage.text.trim(),
      competition: tournament?.label ?? 'tournaments.selectTournament'.tr(),
      suggested: suggested,
    );
    if (stage != null && mounted) setState(() => _stage.text = stage);
  }

  Future<void> _pickDate() async {
    final date = await showCareerDatePicker(
      context: context,
      personId: widget.person.id,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _date ?? _defaultDate(),
    );
    if (mounted && date != null) {
      setState(() => _date = date);
      if (!_opponentDirty) await _rememberOpponent();
    }
  }

  DateTime _defaultDate() {
    final season = _seasons.where((item) => item.id == _seasonId).firstOrNull;
    final now = DateTime.now();
    if (season == null ||
        (!now.isBefore(season.startDate) && !now.isAfter(season.endDate))) {
      return now;
    }
    return season.startDate;
  }

  Future<void> _pickPlayerOfMatch() async {
    if (_performances.isEmpty) {
      _message('players.playerPerformanceTapHint'.tr());
      return;
    }
    final selected = await showPlayerOfMatchPicker(
      context,
      fifaVersion: widget.person.fifaVersion,
      performances: _performances,
      players: {
        ..._playerDetails,
        for (final row in _roster)
          row['playerId'] as String: {
            ...?_playerDetails[row['playerId']],
            ...row,
            'overall':
                _playerDetails[row['playerId']]?['overall'] ?? row['overall'],
          },
      },
      names: _names,
      positions: _positions,
      selectedId: _playerOfMatchId,
    );
    if (!mounted || selected == null) return;
    setState(
      () => _playerOfMatchId = selected.isEmpty || selected == _playerOfMatchId
          ? null
          : selected,
    );
  }

  Future<void> _switchTeam(bool national) async {
    if (_performances.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: const Text(
            'Trocar o time remove a escalação desta partida.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('common.cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('common.remove'.tr()),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _national = national;
    _deletedIds.addAll(_performances.map((row) => row.id));
    _performances = [];
    _playerOfMatchId = null;
    _captaincy = const FixtureCaptaincy();
    _matchFormation = null;
    await _loadRoster();
    if (mounted) setState(_applyAutoScore);
  }

  void _autoLineup() {
    final used = _performances.map((row) => row.playerInstanceId).toSet();
    final starters = _roster
        .where((row) => row['isBench'] != 1)
        .map((row) => row['playerId'] as String)
        .where((id) => !used.contains(id))
        .toList();
    if (_roster.isEmpty) {
      _message('players.noTeamPlayers'.tr());
      return;
    }
    setState(() {
      _performances = _sorted([
        ..._performances,
        for (final id in starters)
          ManagerFixturePlayerPerformance(
            personId: widget.person.id,
            fixtureId: _id,
            playerInstanceId: id,
          ),
      ]);
    });
  }

  Future<List<Map<String, Object?>>>? get _seasonStats =>
      widget.preloaded != null
      ? null
      : _seasonStatsFuture ??= SqlService.instance.getManagerPlayerStatistics(
          widget.person.id,
          seasonId: _seasonId,
        );

  Future<void> _addPlayers() async {
    if (_roster.isEmpty) {
      _message('players.noTeamPlayers'.tr());
      return;
    }
    final selected = await Navigator.push<List<SelectedTeamPlayer>>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectTeamPlayerPage(
          fifaVersion: widget.person.fifaVersion,
          roster: _roster,
          names: _names,
          positions: _positions,
          multiple: true,
          usedIds: _performances.map((row) => row.playerInstanceId).toSet(),
          seasonStats: _seasonStats,
        ),
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    setState(() {
      _performances = _sorted([
        ..._performances,
        for (final player in selected)
          ManagerFixturePlayerPerformance(
            personId: widget.person.id,
            fixtureId: _id,
            playerInstanceId: player.id,
          ),
      ]);
    });
  }

  ManagerFixturePlayerPerformance _performanceOf(String id) =>
      _performances.where((p) => p.playerInstanceId == id).firstOrNull ??
      ManagerFixturePlayerPerformance(
        personId: widget.person.id,
        fixtureId: _id,
        playerInstanceId: id,
      );

  Future<void> _openPerformance(
    ManagerFixturePlayerPerformance? existing, {
    String? initialEvent,
  }) async {
    if (existing == null && _roster.isEmpty) {
      _message('players.noTeamPlayers'.tr());
      return;
    }
    final teamLastMinute = _performances.fold<int>(0, (last, item) {
      final minute = item.getLastMinuteValue() ?? 0;
      return minute > last ? minute : last;
    });
    final result = await Navigator.push<PerformanceDetailsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => PerformanceDetails(
          person: widget.person,
          performance:
              existing ??
              ManagerFixturePlayerPerformance(
                personId: widget.person.id,
                fixtureId: _id,
                playerInstanceId: '',
              ),
          isNew: existing == null,
          roster: _roster,
          names: _names,
          positions: _positions,
          usedIds: _performances.map((item) => item.playerInstanceId).toSet(),
          teamLastMinute: teamLastMinute == 0 ? null : teamLastMinute,
          isPlayerOfMatch:
              existing != null && _playerOfMatchId == existing.playerInstanceId,
          seasonStats: _seasonStats,
          initialEvent: initialEvent,
        ),
      ),
    );
    final edited = result?.performance;
    if (result == null || edited == null || !mounted) return;
    final all = _performances.map((item) => item.copy()).toList();
    if (result.deleted) {
      all.removeWhere((item) => item.id == edited.id);
      removePerformanceAndRelatedLinks(edited.playerInstanceId, all);
      _deletedIds.add(edited.id);
      if (_playerOfMatchId == edited.playerInstanceId) _playerOfMatchId = null;
    } else {
      final index = all.indexWhere((item) => item.id == edited.id);
      if (index >= 0) {
        all[index] = edited;
      } else {
        all.add(edited);
      }
      final name = _names[edited.playerInstanceId] ?? '';
      syncSubstitutions(
        edited,
        all,
        name,
        (playerInstanceId) => ManagerFixturePlayerPerformance(
          personId: widget.person.id,
          fixtureId: _id,
          playerInstanceId: playerInstanceId,
        ),
      );
      syncGoalsAndAssists(edited, all, name);
      if (result.isPlayerOfMatch) {
        _playerOfMatchId = edited.playerInstanceId;
      } else if (_playerOfMatchId == edited.playerInstanceId) {
        _playerOfMatchId = null;
      }
    }
    setState(() {
      _performances = _sorted(all);
      _captaincy = _captaincy.reconciled(_performances);
      _applyAutoScore();
    });
    if (!result.deleted) await _resolveCaptainChanges();
  }

  Future<void> _chooseCaptain() async {
    final eligible = _performances
        .where(FixtureCaptaincy.starter)
        .map((p) => p.playerInstanceId)
        .toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione os titulares antes de definir o capitão.'),
        ),
      );
      return;
    }
    final selected = await showCaptainPicker(
      context,
      title: 'Capitão no início da partida',
      eligible: eligible,
      names: _names,
      selectedId: _captaincy.initialPlayerId,
    );
    if (selected == null || !mounted) return;
    setState(
      () => _captaincy = FixtureCaptaincy(
        initialPlayerId: selected.isEmpty ? null : selected,
        handovers: selected == _captaincy.initialPlayerId
            ? _captaincy.handovers
            : [],
      ),
    );
    await _resolveCaptainChanges();
  }

  Future<bool> _chooseCaptainHandover(CaptainDeparture departure) async {
    final selected = await showCaptainPicker(
      context,
      title: 'Quem recebeu a braçadeira?',
      eligible: _captaincy.candidates(_performances, departure),
      names: _names,
      selectedId: departure.handover?.playerId,
      noneLabel: 'Não informar o próximo capitão',
    );
    if (selected == null || !mounted) return false;
    setState(
      () => _captaincy = _captaincy
          .assign(departure, selected.isEmpty ? null : selected)
          .reconciled(_performances),
    );
    return true;
  }

  Future<void> _resolveCaptainChanges() async {
    while (mounted) {
      final pending = _captaincy.pending(_performances);
      if (pending == null || !await _chooseCaptainHandover(pending)) return;
    }
  }

  int? _int(TextEditingController controller) =>
      int.tryParse(controller.text.trim());
  double? _double(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  bool _invalidNumber(
    TextEditingController controller, {
    bool decimal = false,
  }) {
    final text = controller.text.trim();
    if (text.isEmpty) return false;
    return decimal ? _double(controller) == null : _int(controller) == null;
  }

  String? _seasonFor(DateTime date) => _seasons
      .where(
        (season) =>
            !date.isBefore(season.startDate) &&
            !date.isAfter(season.endDate.add(const Duration(days: 1))),
      )
      .firstOrNull
      ?.id;

  Future<void> _save() async {
    if (_opponent == null || _tournament == null || _date == null) return;
    if ([
          _myShots,
          _otherShots,
          _position,
          _otherYellowCards,
          _otherRedCards,
          _otherOwnGoals,
          _otherMissedPenalties,
          _otherInjuries,
          _otherPosition,
        ].any(_invalidNumber) ||
        _invalidNumber(_possession, decimal: true) ||
        _invalidNumber(_passAccuracy, decimal: true) ||
        _invalidNumber(_otherPassAccuracy, decimal: true) ||
        (_int(_position) != null && _int(_position)! < 1)) {
      setState(() => _statsOpen = true);
      _message('common.invalidFieldsError'.tr());
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final createdAt =
          DateTime.tryParse(widget.existing?['createdAt'] as String? ?? '') ??
          now;
      final team = _ownTeam;
      final fixture = ManagerFixture(
        id: _id,
        personId: widget.person.id,
        date: _date!,
        fifaVersion: widget.person.fifaVersion,
        playerTeamScore: _myScore,
        oppositeTeamScore: _otherScore,
        oppositeTeamId: _opponent!.id,
        oppositeTeamLeagueId: _opponent!.leagueId,
        playerTeamId: team.id,
        playerTeamLeagueId: team.leagueId,
        tournamentId: _tournament!.id,
        seasonId: _seasonFor(_date!) ?? _seasonId ?? _seasons.first.id,
        location: _location,
        createdAt: createdAt,
        updatedAt: now,
        teamPossession: _double(_possession),
        passAccuracy: _double(_passAccuracy),
        playerTeamShotsCount: _int(_myShots),
        opponentTeamShotsCount: _int(_otherShots),
        extraTime: _extraTime,
        playerTeamPenaltiesScore: _penalties ? _myPenalties : null,
        oppositeTeamPenaltiesScore: _penalties ? _otherPenalties : null,
        position: _int(_position),
        stage: _stage.text.trim().isEmpty ? null : _stage.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ).toMap();
      fixture
        ..['captaincy'] = _captaincy.reconciled(_performances).encode()
        ..['playerOfTheMatchId'] = _playerOfMatchId
        ..['isPotmFromMyTeam'] = _playerOfMatchId == null ? null : 1
        ..['opponentGoalDetails'] = encodeOpponentGoals(_opponentGoals)
        ..['opponentLineup'] = _opponentLineup.encode()
        ..['opponentStats'] = OpponentStats(
          passAccuracy: _double(_otherPassAccuracy),
          yellowCards: _int(_otherYellowCards),
          redCards: _int(_otherRedCards),
          ownGoals: _int(_otherOwnGoals),
          missedPenalties: _int(_otherMissedPenalties),
          injuries: _int(_otherInjuries),
          position: _int(_otherPosition),
        ).encode()
        ..['isFavorite'] = widget.existing?['isFavorite'];
      fixture['matchLineup'] =
          (_matchFormation ??
                  FixtureFormation.initial(
                    roster: _roster,
                    names: _names,
                    positions: _positionIds,
                    performances: _performances,
                    useRosterWhenEmpty: false,
                  ))
              .reconciledWith(
                FixtureFormation.initial(
                  roster: _roster,
                  names: _names,
                  positions: _positionIds,
                  performances: _performances,
                  useRosterWhenEmpty: false,
                ),
              )
              .encode();
      if (widget.onFixtureSaved != null) {
        await widget.onFixtureSaved!(fixture, _performances);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      await SqlService.instance.createFixture(
        PersonCategory.manager,
        fixture,
        update: widget.existing != null,
      );
      await SqlService.instance.saveManagerPerformances(
        _performances,
        deletedIds: _deletedIds,
      );
      await SqlService.instance.syncMatchInjuries(
        widget.person.id,
        fixtureId: _id,
      );
      await TournamentAutomation.trySync(widget.person);
      final pressShared = await _offerPressConference();
      await TwitterGenerationService.instance.onFixtureSaved(
        widget.person,
        _id,
        update: widget.existing != null,
      );
      if (pressShared) {
        await TwitterGenerationService.instance.sharePressConference(
          widget.person,
          _id,
        );
      }
      if (!mounted) return;
      if (widget.existing == null) {
        await openFixtureDetails(context, widget.person, _id, replace: true);
      } else {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) _message('Erro ao salvar partida: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _offerPressConference() async {
    if (widget.existing != null) return false;
    final current = await SqlService.instance.getPressConference(
      widget.person.id,
      _id,
    );
    if (current != null || !await AIModelService.isReady() || !mounted) {
      return false;
    }
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(TablerIcons.microphone),
        title: const Text('Coletiva de imprensa'),
        content: const Text(
          'Deseja participar da coletiva de imprensa? Os jornalistas fazem '
          '3 perguntas sobre a partida e você responde.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Participar'),
          ),
        ],
      ),
    );
    if (accepted != true) {
      await SqlService.instance.savePressConference(
        widget.person.id,
        _id,
        PressConference.declined(),
      );
      return false;
    }
    if (!mounted) return false;
    final result = await Navigator.push<PressConference>(
      context,
      MaterialPageRoute(
        builder: (_) => PressConferencePage(
          person: widget.person,
          fixtureId: _id,
          publishOnFinish: false,
        ),
      ),
    );
    return result != null && result.done && result.shared;
  }

  Future<void> _createSeason() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateSeasonPage(personId: widget.person.id),
      ),
    );
    if (created == true && mounted) setState(() => _ready = _load());
  }

  AppColors get _c => AppColors.of(context);

  String get _ownName =>
      GameCatalog.current?.teamLabel(
        widget.person.fifaVersion,
        _ownTeam.id,
        leagueId: _ownTeam.leagueId,
      ) ??
      _ownTeam.id;

  Widget _round(
    IconData icon,
    VoidCallback? onPressed, {
    Key? key,
    String? tooltip,
  }) => SizedBox.square(
    dimension: 34,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: _c.raised,
        disabledBackgroundColor: _c.raised.withValues(alpha: .4),
        foregroundColor: _c.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 18),
    ),
  );

  Widget _stepper(int value, ValueChanged<int> onChanged, String side) =>
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _round(
              TablerIcons.minus,
              value > 0 ? () => setState(() => onChanged(value - 1)) : null,
              tooltip: 'Tirar gol · $side',
            ),
            const SizedBox(width: 8),
            _round(
              TablerIcons.plus,
              () => setState(() => onChanged(value + 1)),
              tooltip: 'Somar gol · $side',
            ),
          ],
        ),
      );

  Widget _team({required bool own}) {
    final c = _c;
    final missing = !own && _opponent == null;
    final id = own ? _ownTeam.id : _opponent?.id;
    final leagueId = own ? _ownTeam.leagueId : _opponent?.leagueId;
    final name = own ? _ownName : _opponent?.label ?? 'Escolher adversário';
    return InkWell(
      key: own ? null : const ValueKey('fixture-opponent-picker'),
      onTap: own ? null : _pickOpponent,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Center(
                child: missing
                    ? Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: .12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.accent.withValues(alpha: .45),
                          ),
                        ),
                        child: Icon(TablerIcons.plus, color: c.accent),
                      )
                    : TeamLogo.lookup(
                        fifaVersion: widget.person.fifaVersion,
                        teamId: id!,
                        leagueId: leagueId,
                        size: 50,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: missing ? c.accent : c.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            if (!own && !missing)
              Text(
                'Trocar',
                style: TextStyle(
                  color: c.accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final c = _c;
    final ownLeft = _location != GameLocation.away;
    final leftScore = ownLeft ? _myScore : _otherScore;
    final rightScore = ownLeft ? _otherScore : _myScore;
    void setLeft(int value) => ownLeft ? _myScore = value : _otherScore = value;
    void setRight(int value) =>
        ownLeft ? _otherScore = value : _myScore = value;
    final leftPenalties = ownLeft ? _myPenalties : _otherPenalties;
    final rightPenalties = ownLeft ? _otherPenalties : _myPenalties;
    void setLeftPenalties(int value) =>
        ownLeft ? _myPenalties = value : _otherPenalties = value;
    void setRightPenalties(int value) =>
        ownLeft ? _otherPenalties = value : _myPenalties = value;
    final leftName = ownLeft ? _ownName : _opponent?.label ?? 'adversário';
    final rightName = ownLeft ? _opponent?.label ?? 'adversário' : _ownName;
    Widget toggle(String label, bool value, VoidCallback onTap, Key key) =>
        FilterChip(
          key: key,
          visualDensity: VisualDensity.compact,
          showCheckmark: false,
          selected: value,
          avatar: Icon(
            value
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: value ? c.accent : c.muted,
          ),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          onSelected: (_) => setState(onTap),
        );
    return Container(
      key: const ValueKey('fixture-score-editor'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _team(own: ownLeft)),
              SizedBox(
                width: 112,
                child: Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$leftScore – $rightScore',
                          style: TextStyle(
                            color: c.text,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (_penalties)
                      Text(
                        '($leftPenalties–$rightPenalties '
                        '${'fixtures.penaltyMedium'.tr()})',
                        style: TextStyle(color: c.muted, fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              Expanded(child: _team(own: !ownLeft)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Center(child: _stepper(leftScore, setLeft, leftName)),
              ),
              const SizedBox(width: 112),
              Expanded(
                child: Center(child: _stepper(rightScore, setRight, rightName)),
              ),
            ],
          ),
          if (_penalties) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Center(
                    child: _stepper(leftPenalties, setLeftPenalties, leftName),
                  ),
                ),
                SizedBox(
                  width: 112,
                  child: Text(
                    'Pênaltis',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 11.5),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: _stepper(
                      rightPenalties,
                      setRightPenalties,
                      rightName,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              toggle(
                'Prorrogação',
                _extraTime,
                () => _extraTime = !_extraTime,
                const ValueKey('fixture-extra-time'),
              ),
              toggle(
                'Pênaltis',
                _penalties,
                () => _penalties = !_penalties,
                const ValueKey('fixture-penalties'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Os gols registrados na escalação atualizam o placar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _detailRow({
    Key? key,
    required IconData icon,
    required String label,
    required String? value,
    required VoidCallback onTap,
    bool required = false,
  }) {
    final c = _c;
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, size: 19, color: c.muted),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: c.text, fontSize: 13.5)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? (required ? 'Selecionar' : 'Opcional'),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value != null
                      ? c.text
                      : required
                      ? c.accent
                      : c.muted,
                  fontSize: 13.5,
                  fontWeight: value != null || required
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.muted),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: _c.line.withValues(alpha: .4));

  Widget _section({
    Key? key,
    required IconData icon,
    required String title,
    String? summary,
    bool? open,
    VoidCallback? onToggle,
    Widget? action,
    required Widget child,
  }) {
    final c = _c;
    final header = Row(
      children: [
        Icon(icon, size: 19, color: c.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: c.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (open == false && summary != null) ...[
                const SizedBox(height: 2),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
        ?action,
        if (open != null)
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(TablerIcons.chevronDown, size: 20, color: c.muted),
          ),
      ],
    );
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onToggle == null)
            header
          else
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: header,
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: open == false
                ? const SizedBox(width: double.infinity)
                : Padding(padding: const EdgeInsets.only(top: 8), child: child),
          ),
        ],
      ),
    );
  }

  Widget _details({required bool complete}) => _section(
    key: const ValueKey('fixture-details-section'),
    icon: TablerIcons.calendarEvent,
    title: 'Partida',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailRow(
          key: const ValueKey('fixture-tournament'),
          icon: TablerIcons.trophy,
          label: 'tournaments.tournament'.tr(),
          value: _tournament?.label,
          onTap: _pickTournament,
          required: true,
        ),
        _divider(),
        _detailRow(
          key: const ValueKey('fixture-date'),
          icon: TablerIcons.calendarMonth,
          label: 'common.date'.tr(),
          value: _date == null ? null : DateFormat('dd/MM/yyyy').format(_date!),
          onTap: _pickDate,
          required: true,
        ),
        _divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(TablerIcons.soccerField, size: 19, color: _c.muted),
                  const SizedBox(width: 12),
                  Text(
                    'Local',
                    style: TextStyle(color: _c.text, fontSize: 13.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MatchSegmented<GameLocation>(
                key: const ValueKey('fixture-location'),
                value: _location,
                height: 36,
                onChanged: (value) => setState(() => _location = value),
                items: [
                  for (final location in GameLocation.values)
                    MatchSegment(
                      location,
                      'fixtures.${location.name}'.tr(),
                      key: ValueKey('fixture-location-${location.name}'),
                    ),
                ],
              ),
            ],
          ),
        ),
        _divider(),
        _detailRow(
          key: const ValueKey('fixture-stage'),
          icon: TablerIcons.tournament,
          label: 'Fase',
          value: _stage.text.trim().isEmpty ? null : _stage.text.trim(),
          onTap: _pickStage,
        ),
        _divider(),
        _detailRow(
          key: const ValueKey('fixture-motm'),
          icon: TablerIcons.star,
          label: 'Melhor em campo',
          value: _playerOfMatchId == null ? null : _names[_playerOfMatchId],
          onTap: _pickPlayerOfMatch,
        ),
        if (!complete) ...[
          const SizedBox(height: 8),
          const MatchHint(
            'Escolha o adversário, o torneio e a data para salvar.',
            icon: Icons.info_outline_rounded,
          ),
        ],
      ],
    ),
  );

  String _statsSummary() {
    String? value(TextEditingController c, [String suffix = '']) =>
        c.text.trim().isEmpty ? null : '${c.text.trim()}$suffix';
    final parts = [
      if (value(_possession, '%') case final v?) 'Posse $v',
      if (value(_myShots) != null || value(_otherShots) != null)
        '${'fixtures.shots'.tr()} ${value(_myShots) ?? '—'}×${value(_otherShots) ?? '—'}',
      if (value(_passAccuracy, '%') case final v?) 'Passes $v',
      if (value(_position) case final v?) 'Posição $vº',
    ];
    return parts.isEmpty
        ? 'Opcional: posse, chutes, passes, cartões e posição'
        : parts.join(' · ');
  }

  Widget _statsTable() {
    final c = _c;
    final ownLeft = _location != GameLocation.away;
    int lineup(int Function(ManagerFixturePlayerPerformance) count) =>
        _performances.fold<int>(0, (sum, row) => sum + count(row));
    final possession = _double(_possession);
    Widget logo(bool own) {
      final team = own
          ? (id: _ownTeam.id, leagueId: _ownTeam.leagueId)
          : (id: _opponent?.id, leagueId: _opponent?.leagueId);
      return Center(
        child: team.id == null
            ? Icon(TablerIcons.shieldQuestion, size: 22, color: c.muted)
            : TeamLogo.lookup(
                fifaVersion: widget.person.fifaVersion,
                teamId: team.id!,
                leagueId: team.leagueId,
                size: 22,
              ),
      );
    }

    Widget row(String label, Widget own, Widget other) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            flex: 9,
            child: Text(label, style: TextStyle(color: c.text, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 5, child: ownLeft ? own : other),
          const SizedBox(width: 8),
          Expanded(flex: 5, child: ownLeft ? other : own),
        ],
      ),
    );
    Widget input(
      TextEditingController controller, {
      bool decimal = false,
      bool signed = false,
    }) => SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(
          decimal: decimal,
          signed: signed,
        ),
        onChanged: (_) => setState(() {}),
        style: TextStyle(
          color: c.text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          hintText: '—',
          hintStyle: TextStyle(color: c.muted),
          filled: true,
          fillColor: c.field,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.accent),
          ),
        ),
      ),
    );
    Widget auto(Object? value) => Tooltip(
      message: 'Calculado pela escalação',
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.raised.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          value?.toString() ?? '—',
          style: TextStyle(color: c.muted, fontSize: 14),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(flex: 9, child: SizedBox()),
            const SizedBox(width: 8),
            Expanded(flex: 5, child: logo(ownLeft)),
            const SizedBox(width: 8),
            Expanded(flex: 5, child: logo(!ownLeft)),
          ],
        ),
        row(
          'Posse de bola (%)',
          input(_possession, decimal: true),
          auto(
            possession == null
                ? null
                : (100 - (possession <= 1 ? possession * 100 : possession))
                      .toStringAsFixed(1),
          ),
        ),
        row('fixtures.shots'.tr(), input(_myShots), input(_otherShots)),
        row(
          'Precisão de passe (%)',
          input(_passAccuracy, decimal: true),
          input(_otherPassAccuracy, decimal: true),
        ),
        row(
          'fixtures.yellowCards'.tr(),
          auto(lineup((p) => p.yellowCardDetails.length)),
          input(_otherYellowCards),
        ),
        row(
          'fixtures.redCards'.tr(),
          auto(lineup((p) => p.redCardDetails.length)),
          input(_otherRedCards),
        ),
        row(
          'fixtures.ownGoals'.tr(),
          auto(lineup((p) => p.ownGoalDetails.length)),
          input(_otherOwnGoals),
        ),
        row(
          'Pênaltis perdidos',
          auto(lineup((p) => p.missedPenaltyDetails.length)),
          input(_otherMissedPenalties),
        ),
        row(
          'injuries.injuries'.tr(),
          auto(lineup((p) => p.injuryDetails.length)),
          input(_otherInjuries),
        ),
        row(
          'Posição na tabela',
          input(_position, signed: true),
          input(_otherPosition, signed: true),
        ),
        const SizedBox(height: 12),
        const MatchHint(
          'Em cinza, os números do seu time calculados pela escalação. '
          'Posição em branco mantém a do último jogo deste torneio.',
          icon: Icons.info_outline_rounded,
        ),
      ],
    );
  }

  Widget _notesSection() => _section(
    icon: TablerIcons.notes,
    title: 'fixtures.notesOpt'.tr(),
    summary: _notes.text.trim().isEmpty
        ? 'Opcional: o que aconteceu no jogo'
        : _notes.text.trim().replaceAll('\n', ' '),
    open: _notesOpen,
    onToggle: () => setState(() => _notesOpen = !_notesOpen),
    child: TextField(
      controller: _notes,
      minLines: 3,
      maxLines: 6,
      style: TextStyle(color: _c.text, fontSize: 14),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'O que aconteceu no jogo',
        helperText: 'fixtures.notesAiHelper'.tr(),
        helperMaxLines: 3,
        helperStyle: TextStyle(color: _c.muted, fontSize: 11.5),
        filled: true,
        fillColor: _c.field,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _c.accent),
        ),
      ),
    ),
  );

  Widget _tool(
    String label,
    IconData icon,
    VoidCallback onPressed, {
    Key? key,
  }) => OutlinedButton.icon(
    key: key,
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: _c.text,
      backgroundColor: _c.raised.withValues(alpha: .45),
      side: BorderSide(color: _c.line),
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: Icon(icon, size: 17, color: _c.accent),
    label: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    ),
  );

  Widget _viewToggle() {
    final c = _c;
    Widget option(bool pitch) {
      final selected = _pitchSelected == pitch;
      return Tooltip(
        message: pitch ? 'Formação' : 'Lista',
        child: InkWell(
          key: ValueKey('lineup-view-${pitch ? 'formation' : 'list'}'),
          onTap: () => _setPitchView(pitch),
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 40,
            height: 32,
            decoration: BoxDecoration(
              color: selected ? c.panel : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: selected ? Border.all(color: c.line) : null,
            ),
            child: Icon(
              pitch ? Icons.grid_view_rounded : Icons.format_list_bulleted,
              size: 18,
              color: selected ? c.accent : c.muted,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.raised.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [option(false), option(true)],
      ),
    );
  }

  Widget _lineup() {
    Widget? crest(String? id, String? leagueId) => id == null
        ? null
        : TeamLogo.lookup(
            fifaVersion: widget.person.fifaVersion,
            teamId: id,
            leagueId: leagueId,
            size: 18,
          );
    return _section(
      key: const ValueKey('fixture-lineups-section'),
      icon: TablerIcons.users,
      title: 'Escalação',
      action: _viewToggle(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MatchSegmented<bool>(
            key: const ValueKey('fixture-lineups-team-selector'),
            value: _opponentLineupSelected,
            onChanged: (other) =>
                setState(() => _opponentLineupSelected = other),
            items: [
              MatchSegment(
                false,
                _national ? 'Seleção' : 'Clube',
                key: const ValueKey('lineup-team-own'),
                leading: crest(_ownTeam.id, _ownTeam.leagueId),
              ),
              MatchSegment(
                true,
                'Adversário',
                key: const ValueKey('lineup-team-opponent'),
                leading: crest(_opponent?.id, _opponent?.leagueId),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _opponentLineupSelected
                ? [
                    _tool(
                      _opponentLineup.squad.formation.isEmpty
                          ? 'Formação'
                          : _opponentLineup.squad.formation,
                      Icons.grid_view_rounded,
                      () => OpponentLineupEditor.chooseFormation(
                        context,
                        _opponentLineup,
                        _changeOpponentLineup,
                      ),
                      key: const ValueKey('choose-opponent-formation'),
                    ),
                    _tool(
                      'Jogador',
                      TablerIcons.plus,
                      _opponent == null
                          ? _pickOpponent
                          : () => OpponentLineupEditor.addPlayer(
                              context,
                              widget.person,
                              _opponentLineup,
                              _changeOpponentLineup,
                            ),
                      key: const ValueKey('add-opponent-player'),
                    ),
                  ]
                : [
                    _tool(
                      'common.auto'.tr(),
                      TablerIcons.sparkles,
                      _autoLineup,
                      key: const ValueKey('lineup-auto'),
                    ),
                    _tool(
                      'Adicionar',
                      TablerIcons.plus,
                      _addPlayers,
                      key: const ValueKey('lineup-add'),
                    ),
                  ],
          ),
          const SizedBox(height: 12),
          if (_opponentLineupSelected)
            _opponentLineupContent()
          else ...[
            FixtureCaptainPanel(
              captaincy: _captaincy,
              performances: _performances,
              names: _names,
              onInitial: _chooseCaptain,
              onHandover: (d) async {
                if (await _chooseCaptainHandover(d)) {
                  await _resolveCaptainChanges();
                }
              },
            ),
            const SizedBox(height: 8),
            if (_pitchSelected)
              FixtureFormationView(
                key: const ValueKey('edit-own-formation'),
                person: widget.person,
                editable: true,
                embedded: true,
                available: FixtureFormation.initial(
                  roster: _roster,
                  names: _names,
                  positions: _positionIds,
                  performances: _performances,
                  useRosterWhenEmpty: false,
                ),
                saved: _matchFormation,
                performances: _performances,
                captainIds: _captaincy.players(_performances),
                header: const SizedBox.shrink(),
                playerActionLabel: 'Editar atuação',
                onSave: (value) async {
                  if (!mounted) return;
                  setState(() {
                    final previous =
                        (_matchFormation ??
                                FixtureFormation.initial(
                                  roster: _roster,
                                  names: _names,
                                  positions: _positionIds,
                                  performances: _performances,
                                  useRosterWhenEmpty: false,
                                ))
                            .starters
                            .keys
                            .toSet();
                    _matchFormation = value;
                    final selected = value.starters.keys.toSet();
                    if (previous.length == selected.length &&
                        previous.containsAll(selected)) {
                      return;
                    }
                    final all = _performances.map((p) => p.copy()).toList();
                    final unused = all
                        .where(
                          (p) =>
                              !selected.contains(p.playerInstanceId) &&
                              previous.contains(p.playerInstanceId) &&
                              FixtureCaptaincy.starter(p) &&
                              p.toMap().entries.every(
                                (e) =>
                                    {
                                      'id',
                                      'personId',
                                      'fixtureId',
                                      'playerInstanceId',
                                      'recordedStarted',
                                    }.contains(e.key) ||
                                    e.value == null ||
                                    e.value == '[]',
                              ),
                        )
                        .toList();
                    for (final p in unused) {
                      all.remove(p);
                      _deletedIds.add(p.id);
                      if (_playerOfMatchId == p.playerInstanceId) {
                        _playerOfMatchId = null;
                      }
                    }
                    for (final p in all) {
                      if (selected.contains(p.playerInstanceId)) {
                        p.recordedStarted = true;
                      } else if (previous.contains(p.playerInstanceId) &&
                          FixtureCaptaincy.starter(p)) {
                        p.recordedStarted = false;
                      }
                    }
                    final present = all.map((p) => p.playerInstanceId).toSet();
                    for (final id in selected.difference(present)) {
                      all.add(
                        ManagerFixturePlayerPerformance(
                          personId: widget.person.id,
                          fixtureId: _id,
                          playerInstanceId: id,
                          recordedStarted: true,
                        ),
                      );
                    }
                    _performances = _sorted(all);
                    _captaincy = _captaincy.reconciled(_performances);
                  });
                },
                onPlayerTap: (id) => _openPerformance(_performanceOf(id)),
                onPlayerAction: (id, event) =>
                    _openPerformance(_performanceOf(id), initialEvent: event),
              )
            else if (_performances.isNotEmpty)
              TeamPlayersPerformanceGrid(
                rows: _performances,
                names: _names,
                positions: _positions,
                playerOfMatchId: _playerOfMatchId,
                captainIds: _captaincy.players(_performances),
                showHeader: false,
                onTap: _openPerformance,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Nenhum jogador escalado. Use Auto para trazer os titulares do elenco ou Adicionar para escolher.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _c.muted, fontSize: 12.5),
                ),
              ),
            const SizedBox(height: 10),
            const MatchHint(
              'Toque em um jogador para registrar nota, gols, cartões e substituições. '
              'Só quem está na escalação conta como jogo disputado.',
              icon: Icons.touch_app_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _opponentLineupContent() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_opponent == null) ...[
        Text(
          'Escolha o adversário para montar a escalação.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _c.muted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _pickOpponent,
          icon: const Icon(Icons.groups_outlined),
          label: const Text('Selecionar adversário'),
        ),
      ] else ...[
        if (_opponentLoading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_pitchSelected && _opponentLineup.squad.formation.isNotEmpty)
          FixtureFormationView(
            key: const ValueKey('edit-opponent-formation'),
            person: widget.person,
            editable: true,
            embedded: true,
            available: _opponentLineup.squad,
            saved: _opponentLineup.squad,
            performances: _opponentLineup.performances,
            header: const SizedBox.shrink(),
            playerActionLabel: 'Editar atuação',
            onSave: (value) async =>
                _changeOpponentLineup(_opponentLineup.copy(squad: value)),
            onPlayerTap: (id) => OpponentLineupEditor(
              person: widget.person,
              fixtureId: _id,
              lineup: _opponentLineup,
              onChanged: _changeOpponentLineup,
            ).editPerformance(context, id),
            onPlayerAction: (id, event) => OpponentLineupEditor(
              person: widget.person,
              fixtureId: _id,
              lineup: _opponentLineup,
              onChanged: _changeOpponentLineup,
            ).editPerformance(context, id, initialEvent: event),
          )
        else
          OpponentLineupEditor(
            showTitle: false,
            person: widget.person,
            fixtureId: _id,
            lineup: _opponentLineup,
            onChanged: _changeOpponentLineup,
          ),
        const SizedBox(height: 10),
        const MatchHint(
          'Toque para registrar a atuação; segure para editar nome e foto.',
          icon: Icons.touch_app_outlined,
        ),
      ],
    ],
  );

  Widget _teamToggle() {
    Widget segment(bool national, String teamId, String? leagueId) {
      final selected = _national == national;
      return Material(
        color: selected ? _c.accent : _c.field,
        child: InkWell(
          onTap: selected ? null : () => _switchTeam(national),
          child: SizedBox(
            width: 48,
            height: 32,
            child: Center(
              child: TeamLogo.lookup(
                fifaVersion: widget.person.fifaVersion,
                teamId: teamId,
                leagueId: leagueId,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              true,
              widget.person.nationalCoachingTeamId!,
              GameCatalog.nationalLeagueId,
            ),
            segment(false, widget.person.teamId, widget.person.leagueId),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: careerDetailTheme(context),
    child: FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        final ready = snapshot.connectionState == ConnectionState.done;
        final canSave =
            ready && _opponent != null && _tournament != null && _date != null;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.existing == null
                  ? 'fixtures.addFixture'.tr()
                  : 'fixtures.editFixture'.tr(),
            ),
            actions: [if (ready && _hasNationalTeam) _teamToggle()],
          ),
          floatingActionButton: canSave
              ? FloatingActionButton.extended(
                  onPressed: _saving ? null : _save,
                  backgroundColor: _c.accent,
                  foregroundColor: _c.onAccent,
                  icon: const Icon(TablerIcons.deviceFloppy),
                  label: Text(
                    _saving ? 'common.inProgress'.tr() : 'common.save'.tr(),
                  ),
                )
              : null,
          body: Builder(
            builder: (context) {
              if (snapshot.hasError) {
                return Center(child: Text('${snapshot.error}'));
              }
              if (!ready) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_seasons.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('common.noSeasonsMessage'.tr()),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _createSeason,
                        child: Text('seasons.createSeason'.tr()),
                      ),
                    ],
                  ),
                );
              }
              return ListView(
                key: const PageStorageKey('edit-fixture-main'),
                primary: false,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                children: [
                  if (widget.existing == null)
                    FcScoreImportShortcut(
                      person: widget.person,
                      padding: const EdgeInsets.only(bottom: 12),
                    ),
                  _header(),
                  _details(complete: canSave),
                  _lineup(),
                  _section(
                    key: const ValueKey('fixture-opponent-goals'),
                    icon: TablerIcons.ballFootball,
                    title: 'Gols do adversário',
                    child: OpponentGoalsPanel(
                      person: widget.person,
                      lineup: _opponentLineup,
                      onLineupChanged: _changeOpponentLineup,
                      opponentTeamId: _opponent?.id,
                      opponentLeagueId: _opponent?.leagueId,
                      seasonId: _seasonId,
                      date: _date,
                      goals: _opponentGoals,
                      onChanged: (goals) {
                        setState(() => _opponentGoals = goals);
                        _changeOpponentLineup(
                          _opponentLineup.withRecordedGoals(goals),
                        );
                      },
                    ),
                  ),
                  _section(
                    icon: TablerIcons.chartBar,
                    title: 'Estatísticas',
                    summary: _statsSummary(),
                    open: _statsOpen,
                    onToggle: () => setState(() => _statsOpen = !_statsOpen),
                    child: _statsTable(),
                  ),
                  _notesSection(),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}
