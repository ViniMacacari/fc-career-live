import '../../../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../Common/GoalShotPlacementPage.dart';
import '../../../models/ManagerFixturePlayerPerformance.dart';
import '../../../models/MatchPerformanceStats.dart';
import '../../../models/Person.dart';
import '../../../utils/themes.dart';
import '../../../utils/GamePlayers.dart';
import '../../../utils/eventTimeUtils.dart';
import '../../TeamPage/SelectRealPlayerPage.dart';
import '../OpponentGoals/NameInputPage.dart';
import '../SelectTeamPlayerPage.dart';
import 'SelectGoalTypePage.dart';
import 'TeamPlayersPerformanceGrid.dart' show performanceRatingColor;
import 'SpeechParser.dart';
import 'VoiceRecognizerModal.dart';

class PerformanceDetailsResult {
  const PerformanceDetailsResult({
    this.performance,
    this.isPlayerOfMatch = false,
    this.deleted = false,
  });
  final ManagerFixturePlayerPerformance? performance;
  final bool isPlayerOfMatch, deleted;
}

class PerformanceDetails extends StatefulWidget {
  const PerformanceDetails({
    super.key,
    required this.person,
    required this.performance,
    required this.isNew,
    this.roster = const [],
    this.names = const {},
    this.positions = const {},
    this.usedIds = const {},
    this.teamLastMinute,
    this.isPlayerOfMatch = false,
    this.showPlayerOfMatch = true,
    this.showGoalkeeperStats = true,
    this.seasonStats,
    this.onEditPlayerIdentity,
    this.initialEvent,
  });
  final Person person;
  final ManagerFixturePlayerPerformance performance;
  final bool isNew, isPlayerOfMatch, showPlayerOfMatch, showGoalkeeperStats;
  final List<Map<String, Object?>> roster;
  final Map<String, String> names, positions;
  final Set<String> usedIds;
  final int? teamLastMinute;

  final Future<List<Map<String, Object?>>>? seasonStats;
  final Future<String?> Function()? onEditPlayerIdentity;
  final String? initialEvent;

  @override
  State<PerformanceDetails> createState() => _PerformanceDetailsState();
}

class _PerformanceDetailsState extends State<PerformanceDetails> {
  String? _editedPlayerName;

  Future<void> _editPlayerIdentity() async {
    final name = await widget.onEditPlayerIdentity?.call();
    if (mounted && name != null) setState(() => _editedPlayerName = name);
  }

  static const _accuracyFields = {
    'shotAccuracy',
    'passAccuracy',
    'dribblesAccuracy',
    'tacklesAccuracy',
  };

  late final ManagerFixturePlayerPerformance _perf = widget.performance.copy();

  @override
  void initState() {
    super.initState();
    final event = widget.initialEvent;
    if (event != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startEvent(event);
      });
    }
  }

  Future<void> _startEvent(String event) async {
    final substitution = event.startsWith('substitution');
    final PerformanceTimeDetails item;
    final List<PerformanceTimeDetails> items;
    final String titleKey;
    switch (event) {
      case 'goal':
        item = PerformanceGoalDetails();
        items = _perf.goalDetails;
        titleKey = 'fixtures.goals';
      case 'assist':
        item = PerformanceAssistDetails();
        items = _perf.assistDetails;
        titleKey = 'fixtures.assists';
      case 'yellowCard' when _perf.yellowCardDetails.length < 2:
        item = PerformanceTimeDetails();
        items = _perf.yellowCardDetails;
        titleKey = 'fixtures.yellowCards';
      case 'redCard' when _perf.redCardDetails.isEmpty:
        item = PerformanceTimeDetails();
        items = _perf.redCardDetails;
        titleKey = 'fixtures.redCards';
      case 'substitutionIn' || 'substitutionOut':
        item = PerformanceSubstitutionDetails(
          type: event == 'substitutionIn'
              ? SubstitutionType.inGame
              : SubstitutionType.outGame,
        );
        items = _perf.substitutionDetails;
        titleKey = 'fixtures.substitutions';
      default:
        return;
    }
    setState(() {
      items.add(item);
      _syncCounts();
    });
    final value = await getEventTime(
      context,
      titleKey.tr(),
      _defaultMinute,
      null,
    );
    if (!mounted) return;
    if (value == null) {
      setState(() {
        items.remove(item);
        _syncCounts();
      });
      return;
    }
    setState(() {
      item
        ..minute = value.minute
        ..addedMinute = value.addedMinute;
    });
    if (!substitution) _save();
  }

  late final _ratingText = TextEditingController(
    text: _ratingLabel(_perf.avgRating),
  );
  final _ratingFocus = FocusNode();

  static String _ratingLabel(double? rating) =>
      rating == null || rating <= 0 ? '' : rating.toStringAsFixed(1);

  void _showRating() {
    final label = _ratingLabel(_perf.avgRating);
    if (_ratingText.text != label) _ratingText.text = label;
  }

  void _typeRating(String text) {
    final value = double.tryParse(text.replaceAll(',', '.'));
    setState(
      () => _perf.avgRating = value == null || value <= 0
          ? null
          : value.clamp(0, 10).toDouble(),
    );
  }

  void _finishRating() {
    _ratingFocus.unfocus();
    _showRating();
  }

  late bool _playerOfMatch = widget.isPlayerOfMatch;
  late final Map<String, TextEditingController> _numbers = {
    for (final entry in _statValues().entries)
      entry.key: TextEditingController(text: entry.value?.toString()),
  };
  late final _advanced = <String, TextEditingController>{
    for (final s in performanceStats)
      if (!s.percentage && _perf.apiStats[s.key] is num)
        s.key: TextEditingController(text: '${_perf.apiStats[s.key]}'),
  };

  bool get _managerMode => widget.person.category == PersonCategory.manager;

  Map<String, int?> _statValues() => {
    'shotsCount': _perf.shotsCount,
    'shotAccuracy': _perf.shotAccuracy,
    'passes': _perf.passes,
    'passAccuracy': _perf.passAccuracy,
    'keyPasses': _perf.keyPasses,
    'dribbles': _perf.dribbles,
    'dribblesAccuracy': _perf.dribblesAccuracy,
    'tackles': _perf.tackles,
    'tacklesAccuracy': _perf.tacklesAccuracy,
    'saves': _perf.saves,
    'penaltySaves': _perf.penaltySaves,
  };

  Map<String, String> get _statLabels => {
    'shotsCount': 'fixtures.shots'.tr(),
    'shotAccuracy': 'fixtures.shotAccuracy'.tr(),
    'passes': 'fixtures.passes'.tr(),
    'passAccuracy': 'fixtures.passAccuracyPerf'.tr(),
    'keyPasses': 'fixtures.keyPasses'.tr(),
    'dribbles': 'fixtures.dribbles'.tr(),
    'dribblesAccuracy': 'fixtures.successDribbleRate'.tr(),
    'tackles': 'fixtures.tackles'.tr(),
    'tacklesAccuracy': 'fixtures.successTackleRate'.tr(),
    'saves': 'fixtures.saves'.tr(),
    'penaltySaves': 'fixtures.penaltySaves'.tr(),
  };

  @override
  void dispose() {
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    for (final controller in _advanced.values) {
      controller.dispose();
    }
    _ratingText.dispose();
    _ratingFocus.dispose();
    super.dispose();
  }

  int get _defaultMinute {
    final own = _perf.getLastMinuteValue() ?? 0;
    final team = widget.teamLastMinute ?? 0;
    return own > team ? own : team;
  }

  void _syncCounts() {
    _perf
      ..goalsCount = _perf.goalDetails.length
      ..assistsCount = _perf.assistDetails.length
      ..yellowCards = _perf.yellowCardDetails.length
      ..redCards = _perf.redCardDetails.length;
  }

  void _save() {
    final advancedValues = <String, num?>{};
    for (final e in _advanced.entries) {
      final text = e.value.text.trim().replaceAll(',', '.');
      final value = num.tryParse(text);
      final definition = performanceStats.firstWhere((s) => s.key == e.key);
      if (text.isNotEmpty &&
          (value == null ||
              !value.isFinite ||
              value < 0 ||
              (definition.decimals == 0 &&
                  value != value.truncateToDouble()))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Informe valores válidos nas estatísticas detalhadas.',
            ),
          ),
        );
        return;
      }
      advancedValues[e.key] = value;
    }
    if (advancedValues.isNotEmpty) {
      _perf.apiStats = {..._perf.apiStats, ...advancedValues};
    }
    if (_perf.playerInstanceId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('players.selectTeamPlayer'.tr())));
      return;
    }
    final values = {
      for (final entry in _numbers.entries)
        entry.key: int.tryParse(entry.value.text.trim()),
    };
    final invalid = values.entries.any(
      (entry) =>
          _accuracyFields.contains(entry.key) &&
          entry.value != null &&
          (entry.value! < 0 || entry.value! > 100),
    );
    if (invalid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('common.invalidFieldsError'.tr())));
      return;
    }
    _perf
      ..shotsCount = values['shotsCount']
      ..shotAccuracy = values['shotAccuracy']
      ..passes = values['passes']
      ..passAccuracy = values['passAccuracy']
      ..keyPasses = values['keyPasses']
      ..dribbles = values['dribbles']
      ..dribblesAccuracy = values['dribblesAccuracy']
      ..tackles = values['tackles']
      ..tacklesAccuracy = values['tacklesAccuracy']
      ..saves = values['saves']
      ..penaltySaves = values['penaltySaves'];
    _syncCounts();
    Navigator.pop(
      context,
      PerformanceDetailsResult(
        performance: _perf,
        isPlayerOfMatch: _playerOfMatch,
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('common.remove'.tr()),
        content: Text(widget.names[_perf.playerInstanceId] ?? ''),
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
    if (confirmed == true && mounted) {
      Navigator.pop(
        context,
        PerformanceDetailsResult(performance: _perf, deleted: true),
      );
    }
  }

  Future<SelectedTeamPlayer?> _pickPartner(String title) async {
    if (_managerMode) {
      return Navigator.push<SelectedTeamPlayer>(
        context,
        MaterialPageRoute(
          builder: (_) => SelectTeamPlayerPage(
            fifaVersion: widget.person.fifaVersion,
            title: title,
            roster: widget.roster,
            names: widget.names,
            positions: widget.positions,
            excludeId: _perf.playerInstanceId,
            seasonStats: widget.seasonStats,
          ),
        ),
      );
    }
    final manual = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_search),
              title: Text('players.selectRealPlayer'.tr()),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text('common.enterManually'.tr()),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (manual == null || !mounted) return null;
    if (manual) {
      final name = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const NameInputPage()),
      );
      return name == null ? null : SelectedTeamPlayer('', name);
    }
    final player = await Navigator.push<GamePlayer>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectRealPlayerPage.pick(person: widget.person),
      ),
    );
    return player == null ? null : SelectedTeamPlayer('', player.name);
  }

  Widget _chip({
    Widget? avatar,
    required Widget label,
    required VoidCallback onPressed,
    VoidCallback? onDeleted,
    bool highlighted = false,
  }) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 180, minWidth: 36),
    child: Material(
      color: AppColors.of(context).field,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        onLongPress: onDeleted,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.of(context).line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (avatar != null) ...[avatar, const SizedBox(width: 6)],
              Flexible(
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: AppColors.of(context).text,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: label,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _timeChip(PerformanceTimeDetails item, String titleKey) => _chip(
    label: item.minute == null
        ? const Icon(Icons.more_time, size: 18)
        : Text(
            '${item is PerformanceSubstitutionDetails && item.inferred ? '~' : ''}${formatEventMinute(item.minute, item.addedMinute)} '
            '${'common.minShort'.tr()}',
          ),
    onPressed: () async {
      final value = await getEventTime(
        context,
        titleKey.tr(),
        item.minute ?? _defaultMinute,
        item.addedMinute,
      );
      if (value != null) {
        setState(() {
          item
            ..minute = value.minute
            ..addedMinute = value.addedMinute;
          if (item is PerformanceSubstitutionDetails) item.inferred = false;
        });
      }
    },
  );

  Widget _partnerChip({
    required String? name,
    required String pickTitle,
    required Widget icon,
    required void Function(SelectedTeamPlayer?) onChanged,
  }) => _chip(
    avatar: icon,
    label: Text(name?.isNotEmpty == true ? name! : '-'),
    highlighted: name?.isNotEmpty == true,
    onPressed: () async {
      final selected = await _pickPartner(pickTitle);
      if (selected != null) setState(() => onChanged(selected));
    },
    onDeleted: name?.isNotEmpty == true
        ? () => setState(() => onChanged(null))
        : null,
  );

  Widget _assistIcon() => SvgPicture.asset(
    'assets/images/assistBoot.svg',
    width: 18,
    height: 18,
    colorFilter: ColorFilter.mode(
      Theme.of(context).colorScheme.onSurface,
      BlendMode.srcIn,
    ),
  );

  Widget _panel({required String title, required Widget child, Key? key}) {
    final c = AppColors.of(context);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: c.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _section<T extends PerformanceTimeDetails>({
    required String titleKey,
    required List<T> items,
    required List<Widget> Function(T) chips,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final sorted = getSortedDetails(items);
    void remove(T item) => setState(() {
      items.removeWhere((other) => other.id == item.id);
      _syncCounts();
    });
    return _panel(
      key: ValueKey(titleKey),
      title: '${titleKey.tr()} · ${items.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, item) in sorted.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(
                  height: 1,
                  color: AppColors.of(context).line.withValues(alpha: .4),
                ),
              ),
            item is PerformanceSubstitutionDetails
                ? _substitutionRow(item, () => remove(item))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...chips(item),
                      _eventAction(
                        key: ValueKey('remove-${item.id}'),
                        icon: Icons.remove_circle_outline,
                        color: AppColors.eventRed,
                        tooltip: 'common.remove'.tr(),
                        onPressed: () => remove(item),
                      ),
                    ],
                  ),
          ],
        ],
      ),
    );
  }

  Widget _cardIcon(Color color) => Container(
    width: 10,
    height: 14,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _addEvents() {
    final c = AppColors.of(context);
    Widget add<T extends PerformanceTimeDetails>(
      String titleKey,
      String label,
      Widget icon,
      List<T> items,
      T Function() create, {
      bool canAdd = true,
    }) => ActionChip(
      key: ValueKey('add-$titleKey'),
      tooltip: '${'common.create'.tr()} ${titleKey.tr()}',
      avatar: Opacity(opacity: canAdd ? 1 : .35, child: icon),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      onPressed: canAdd
          ? () => setState(() {
              items.add(create());
              _syncCounts();
            })
          : null,
    );
    return _panel(
      key: const ValueKey('performance-add-events'),
      title: 'Adicionar lance',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          add(
            'fixtures.goals',
            'Gol',
            Icon(Icons.sports_soccer, size: 16, color: c.accent),
            _perf.goalDetails,
            PerformanceGoalDetails.new,
          ),
          add(
            'fixtures.assists',
            'Assistência',
            _assistIcon(),
            _perf.assistDetails,
            PerformanceAssistDetails.new,
          ),
          add(
            'fixtures.substitutions',
            'Substituição',
            const Icon(
              Icons.swap_vert_rounded,
              size: 17,
              color: AppColors.ratingGood,
            ),
            _perf.substitutionDetails,
            () =>
                PerformanceSubstitutionDetails(type: SubstitutionType.outGame),
          ),
          add(
            'fixtures.yellowCards',
            'Cartão amarelo',
            _cardIcon(AppColors.yellowCard),
            _perf.yellowCardDetails,
            PerformanceTimeDetails.new,
            canAdd: _perf.yellowCardDetails.length < 2,
          ),
          add(
            'fixtures.redCards',
            'Cartão vermelho',
            _cardIcon(AppColors.redCard),
            _perf.redCardDetails,
            PerformanceTimeDetails.new,
            canAdd: _perf.redCardDetails.isEmpty,
          ),
          add(
            'fixtures.ownGoals',
            'Gol contra',
            const Icon(
              Icons.sports_soccer,
              size: 16,
              color: AppColors.eventRed,
            ),
            _perf.ownGoalDetails,
            PerformanceTimeDetails.new,
          ),
          add(
            'fixtures.missedPenalties',
            'Pênalti perdido',
            const Icon(
              Icons.cancel_outlined,
              size: 16,
              color: AppColors.eventRed,
            ),
            _perf.missedPenaltyDetails,
            PerformanceTimeDetails.new,
          ),
          add(
            'injuries.injuries',
            'Lesão',
            const Icon(
              Icons.medical_services_outlined,
              size: 16,
              color: AppColors.eventRed,
            ),
            _perf.injuryDetails,
            PerformanceTimeDetails.new,
            canAdd: _perf.injuryDetails.isEmpty,
          ),
        ],
      ),
    );
  }

  List<Widget> _goalChips(PerformanceGoalDetails goal) => [
    _timeChip(goal, 'fixtures.goalTime'),
    _partnerChip(
      name: goal.assistantName,
      pickTitle: 'fixtures.selectAssistant'.tr(),
      icon: _assistIcon(),
      onChanged: (player) {
        goal
          ..assistantId = player == null || player.id.isEmpty ? null : player.id
          ..assistantName = player?.name;
      },
    ),
    _chip(
      avatar: const Icon(Icons.gps_fixed, size: 18),
      label: Text('goalShotMap.goalsMap'.tr()),
      highlighted: goal.goalLocation != null || goal.fieldLocation != null,
      onPressed: () async {
        final result = await Navigator.push<GoalShotPlacementResult>(
          context,
          MaterialPageRoute(
            builder: (_) => GoalShotPlacementPage(
              goalLocation: goal.goalLocation,
              fieldLocation: goal.fieldLocation,
              isPenalty: goal.isPenalty,
            ),
          ),
        );
        if (result != null) {
          setState(() {
            goal
              ..goalLocation = result.goalLocation
              ..fieldLocation = result.fieldLocation;
          });
        }
      },
    ),
    _chip(
      avatar: goal.type.isEmpty
          ? const Icon(Icons.category_outlined, size: 18)
          : null,
      label: Text(
        goal.type.isEmpty
            ? 'fixtures.selectGoalType'.tr()
            : goal.type.map(goalTypeLabel).join(' | '),
      ),
      highlighted: goal.type.isNotEmpty,
      onPressed: () async {
        final types = await Navigator.push<List<GoalType>>(
          context,
          MaterialPageRoute(
            builder: (_) => SelectGoalTypePage(selected: goal.type),
          ),
        );
        if (types != null) setState(() => goal.type = types);
      },
    ),
  ];

  List<Widget> _assistChips(PerformanceAssistDetails assist) => [
    _timeChip(assist, 'fixtures.assistTime'),
    _partnerChip(
      name: assist.goalscorerName,
      pickTitle: 'fixtures.selectGoalScorer'.tr(),
      icon: const Icon(Icons.sports_soccer, size: 18),
      onChanged: (player) {
        assist
          ..goalscorerId = player == null || player.id.isEmpty
              ? null
              : player.id
          ..goalscorerName = player?.name;
      },
    ),
  ];

  List<Widget> _substitutionChips(PerformanceSubstitutionDetails sub) => [
    _timeChip(sub, 'fixtures.substitutionTime'),
    _partnerChip(
      name: sub.anotherPlayerName,
      pickTitle: 'players.selectTeamPlayer'.tr(),
      icon: const Icon(
        Icons.person_add_alt,
        size: 18,
        color: AppColors.ratingGood,
      ),
      onChanged: (player) {
        sub
          ..anotherPlayerId = player == null || player.id.isEmpty
              ? null
              : player.id
          ..anotherPlayerName = player?.name;
      },
    ),
  ];

  Widget _substitutionRow(
    PerformanceSubstitutionDetails sub,
    VoidCallback remove,
  ) {
    final chips = _substitutionChips(sub);
    return Row(
      children: [
        ToggleButtons(
          borderRadius: BorderRadius.circular(16),
          constraints: const BoxConstraints(minWidth: 50, minHeight: 34),
          color: AppColors.of(context).muted,
          fillColor: AppColors.of(context).accent,
          borderColor: AppColors.of(context).line,
          selectedBorderColor: AppColors.of(context).line,
          isSelected: [
            sub.type == SubstitutionType.inGame,
            sub.type == SubstitutionType.outGame,
          ],
          onPressed: (index) => setState(() {
            final type = index == 0
                ? SubstitutionType.inGame
                : SubstitutionType.outGame;
            sub.type = sub.type == type ? null : type;
          }),
          children: [
            Icon(
              Icons.arrow_drop_up,
              size: 30,
              color: sub.type == SubstitutionType.inGame
                  ? AppColors.ratingGood
                  : AppColors.of(context).muted,
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 30,
              color: sub.type == SubstitutionType.outGame
                  ? AppColors.eventRed
                  : AppColors.of(context).muted,
            ),
          ],
        ),
        const SizedBox(width: 8),
        SizedBox(width: 60, child: chips[0]),
        const SizedBox(width: 8),
        Expanded(child: chips[1]),
        const SizedBox(width: 8),
        _eventAction(
          key: ValueKey('remove-${sub.id}'),
          onPressed: remove,
          icon: Icons.remove_circle_outline,
          color: AppColors.eventRed,
          tooltip: 'common.remove'.tr(),
        ),
      ],
    );
  }

  Widget _eventAction({
    Key? key,
    required VoidCallback? onPressed,
    required IconData icon,
    required String tooltip,
    Color? color,
  }) => SizedBox.square(
    dimension: 36,
    child: IconButton(
      key: key,
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.of(context).field,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.of(context).line),
        ),
      ),
      icon: Icon(
        icon,
        size: 24,
        color: onPressed == null
            ? AppColors.of(context).line
            : color ?? AppColors.of(context).text,
      ),
    ),
  );

  void _changeRating(int delta) => setState(() {
    final value =
        (((_perf.avgRating ?? 0) * 10).round() + delta).clamp(0, 100) / 10;
    _perf.avgRating = value == 0 ? null : value;
    _showRating();
  });

  Widget _ratingControls(double rating) => SizedBox(
    height: 54,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.of(context).field,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.of(context).line),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('rating-minus'),
                        onPressed: () => _changeRating(-1),
                        icon: Icon(
                          Icons.remove,
                          color: AppColors.of(context).text,
                        ),
                        iconSize: 24,
                      ),
                      Container(width: 1, color: AppColors.of(context).line),
                      Expanded(
                        child: Center(
                          child: TextField(
                            key: const ValueKey('rating-input'),
                            controller: _ratingText,
                            focusNode: _ratingFocus,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              TextInputFormatter.withFunction(
                                (previous, next) =>
                                    RegExp(r'^\d{0,2}([.,]\d?)?$')
                                        .hasMatch(next.text)
                                    ? next
                                    : previous,
                              ),
                            ],
                            style: TextStyle(
                              color: AppColors.of(context).text,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: '-',
                              hintStyle: TextStyle(
                                color: AppColors.of(context).line,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: _typeRating,
                            onEditingComplete: _finishRating,
                            onTapOutside: (_) => _finishRating(),
                          ),
                        ),
                      ),
                      Container(width: 1, color: AppColors.of(context).line),
                      IconButton(
                        key: const ValueKey('rating-plus'),
                        onPressed: () => _changeRating(1),
                        icon: Icon(
                          Icons.add,
                          color: AppColors.of(context).text,
                        ),
                        iconSize: 24,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: -7,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    color: AppColors.of(context).field,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'fixtures.rating'.tr(),
                      style: TextStyle(
                        color: AppColors.of(context).muted,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.showPlayerOfMatch) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(left: 14, right: 6),
              decoration: BoxDecoration(
                color: AppColors.of(context).field,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.of(context).line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Melhor em campo',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.of(context).text,
                      ),
                    ),
                  ),
                  Switch(
                    value: _playerOfMatch,
                    thumbColor: WidgetStatePropertyAll(
                      AppColors.of(context).text,
                    ),
                    trackOutlineColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    inactiveTrackColor: AppColors.of(context).background,
                    activeTrackColor: AppColors.of(context).accent,
                    onChanged: (value) =>
                        setState(() => _playerOfMatch = value),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _numberField(String field) {
    final c = AppColors.of(context);
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _statLabels[field]!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.muted, fontSize: 11.5),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 44,
          child: TextField(
            key: ValueKey(field),
            controller: _numbers[field],
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '—',
              hintStyle: TextStyle(color: c.muted),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              filled: true,
              fillColor: c.field,
              border: border(c.line),
              enabledBorder: border(c.line),
              focusedBorder: border(c.accent, 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statGrid() {
    final fields = [
      'shotsCount',
      'shotAccuracy',
      'passes',
      'passAccuracy',
      'dribbles',
      'dribblesAccuracy',
      'tackles',
      'tacklesAccuracy',
      'keyPasses',
      if (widget.showGoalkeeperStats) ...['saves', 'penaltySaves'],
    ].where((f) => _perf.apiStats.isEmpty || _statValues()[f] != null).toList();
    if (fields.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            for (final field in fields)
              SizedBox(width: width, child: _numberField(field)),
          ],
        );
      },
    );
  }

  Future<void> _voice() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const VoiceRecognizerModal(),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    final parsed = await StatsParser.parse(text, context.locale.languageCode);
    if (!mounted) return;
    setState(() {
      for (final entry in parsed.stats.entries) {
        if (entry.key == 'rating') {
          final rating = entry.value.clamp(0, 10).toDouble();
          _perf.avgRating = rating == 0 ? null : rating;
          _showRating();
        } else if (_numbers.containsKey(entry.key)) {
          final value = entry.value.round();
          if (value >= 0 &&
              (!_accuracyFields.contains(entry.key) || value <= 100)) {
            _numbers[entry.key]!.text = '$value';
          }
        }
      }
      _perf.goalDetails.addAll(parsed.goals);
      _perf.assistDetails.addAll(parsed.assists);
      _perf.substitutionDetails.addAll(parsed.substitutions);
      _perf.ownGoalDetails.addAll(parsed.ownGoals);
      _perf.missedPenaltyDetails.addAll(parsed.missedPenalties);
      for (final card in parsed.yellowCards) {
        if (_perf.yellowCardDetails.length < 2) {
          _perf.yellowCardDetails.add(card);
        }
      }
      if (_perf.redCardDetails.isEmpty && parsed.redCards.isNotEmpty) {
        _perf.redCardDetails.add(parsed.redCards.first);
      }
      if (_perf.injuryDetails.isEmpty && parsed.injuries.isNotEmpty) {
        _perf.injuryDetails.add(parsed.injuries.first);
      }
      _syncCounts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final choices = widget.roster
        .where(
          (row) =>
              !widget.usedIds.contains(row['playerId']) ||
              row['playerId'] == _perf.playerInstanceId,
        )
        .toList();
    final rating = _perf.avgRating ?? 0;
    final c = AppColors.of(context);
    final stats = _statGrid();
    return Theme(
      data: careerDetailTheme(context),
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          foregroundColor: c.text,
          title: widget.onEditPlayerIdentity == null
              ? Text(
                  widget.names[_perf.playerInstanceId] ??
                      (_managerMode
                          ? 'players.player'.tr()
                          : widget.person.name),
                )
              : InkWell(
                  key: const ValueKey('performance-player-identity'),
                  onTap: _editPlayerIdentity,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _editedPlayerName ??
                              widget.names[_perf.playerInstanceId] ??
                              '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_outlined, size: 16, color: c.muted),
                    ],
                  ),
                ),
          actions: [
            IconButton(
              onPressed: _voice,
              tooltip: 'fixtures.voiceRecognition.help.primaryTitle'.tr(),
              icon: const Icon(Icons.mic_none),
            ),
            if (!widget.isNew && _managerMode)
              PopupMenuButton<String>(
                tooltip: 'Mais opções',
                icon: const Icon(Icons.more_vert),
                onSelected: (_) => _delete(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: c.danger,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'common.remove'.tr(),
                          style: TextStyle(color: c.danger),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          onPressed: _save,
          icon: const Icon(Icons.check_rounded),
          label: Text('common.apply'.tr()),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (_managerMode && widget.isNew)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: _perf.playerInstanceId.isEmpty
                      ? null
                      : _perf.playerInstanceId,
                  decoration: InputDecoration(labelText: 'players.player'.tr()),
                  isExpanded: true,
                  items: choices
                      .map(
                        (row) => DropdownMenuItem<String>(
                          value: row['playerId'] as String,
                          child: Text(
                            widget.names[row['playerId']] ??
                                row['playerId'].toString(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _perf.playerInstanceId = value ?? ''),
                ),
              ),
            _panel(
              key: const ValueKey('performance-rating'),
              title: 'Desempenho',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                              ),
                              trackShape: const RoundedRectSliderTrackShape(),
                              activeTrackColor: performanceRatingColor(rating),
                              inactiveTrackColor: c.raised,
                              thumbColor: performanceRatingColor(rating),
                              overlayColor: performanceRatingColor(rating)
                                  .withValues(alpha: .15),
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 11,
                              ),
                              trackHeight: 6,
                              tickMarkShape: SliderTickMarkShape.noTickMark,
                            ),
                            child: Slider(
                              value: rating.clamp(0, 10).toDouble(),
                              max: 10,
                              divisions: 100,
                              onChanged: (value) => setState(() {
                                _perf.avgRating = value <= 0 ? null : value;
                                _showRating();
                              }),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: _RatingDotsPainter(c)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ratingControls(rating),
                ],
              ),
            ),
            _addEvents(),
            _section<PerformanceGoalDetails>(
              titleKey: 'fixtures.goals',
              items: _perf.goalDetails,
              chips: _goalChips,
            ),
            _section<PerformanceAssistDetails>(
              titleKey: 'fixtures.assists',
              items: _perf.assistDetails,
              chips: _assistChips,
            ),
            _section<PerformanceSubstitutionDetails>(
              titleKey: 'fixtures.substitutions',
              items: _perf.substitutionDetails,
              chips: _substitutionChips,
            ),
            _section<PerformanceCardDetails>(
              titleKey: 'fixtures.yellowCards',
              items: _perf.yellowCardDetails,
              chips: (item) => [_timeChip(item, 'fixtures.cardTime')],
            ),
            _section<PerformanceCardDetails>(
              titleKey: 'fixtures.redCards',
              items: _perf.redCardDetails,
              chips: (item) => [_timeChip(item, 'fixtures.cardTime')],
            ),
            _section<PerformanceOwnGoalDetails>(
              titleKey: 'fixtures.ownGoals',
              items: _perf.ownGoalDetails,
              chips: (item) => [_timeChip(item, 'fixtures.goalTime')],
            ),
            _section<PerformanceMissedPenaltyDetails>(
              titleKey: 'fixtures.missedPenalties',
              items: _perf.missedPenaltyDetails,
              chips: (item) => [_timeChip(item, 'fixtures.time')],
            ),
            _section<PerformanceInjuryDetails>(
              titleKey: 'injuries.injuries',
              items: _perf.injuryDetails,
              chips: (item) => [_timeChip(item, 'fixtures.time')],
            ),
            if (stats is! SizedBox || _advanced.isNotEmpty)
              _panel(
                key: const ValueKey('performance-stats'),
                title: 'Estatísticas',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    stats,
                    if (_advanced.isNotEmpty)
                      ExpansionTile(
                        key: const ValueKey('detailed-performance-editor'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: const Text(
                          'Estatísticas detalhadas',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        children: [
                          for (final group
                              in performanceStats
                                  .map((s) => s.group)
                                  .toSet()) ...[
                            if (performanceStats.any(
                              (s) =>
                                  s.group == group &&
                                  _advanced.containsKey(s.key),
                            ))
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    group,
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            for (final s in performanceStats.where(
                              (s) =>
                                  s.group == group &&
                                  _advanced.containsKey(s.key),
                            ))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TextField(
                                  key: ValueKey('performance-stat/${s.key}'),
                                  controller: _advanced[s.key],
                                  keyboardType: TextInputType.numberWithOptions(
                                    decimal: s.decimals > 0,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: s.label,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RatingDotsPainter extends CustomPainter {
  const _RatingDotsPainter(this.colors);
  final AppColors colors;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colors.text.withValues(alpha: .35);
    for (var i = 0; i <= 10; i++) {
      canvas.drawCircle(
        Offset(28 + (size.width - 56) * i / 10, size.height / 2),
        3,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RatingDotsPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
