import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/CareerDatePicker.dart';
import '../../utils/Components/PlayerAvatar.dart';
import '../../utils/Components/TeamLogo.dart';
import '../../utils/SqlService.dart';
import '../../utils/databaseUtils.dart';
import 'InjuresPage.dart';

class EditInjuryPage extends StatefulWidget {
  const EditInjuryPage({
    super.key,
    required this.person,
    required this.data,
    this.existing,
    this.initialSeasonId,
  });
  final Person person;
  final InjuryData data;
  final Map<String, Object?>? existing;
  final String? initialSeasonId;

  @override
  State<EditInjuryPage> createState() => _EditInjuryPageState();
}

class _EditInjuryPageState extends State<EditInjuryPage> {
  late final _existing = widget.existing;
  late final _description = TextEditingController(
    text: _existing?['description']?.toString(),
  );
  late final _days = TextEditingController(
    text: _existing?['expectedRecoveryDays']?.toString(),
  );
  late String _seasonId =
      _existing?['seasonId'] as String? ??
      widget.initialSeasonId ??
      widget.data.seasons
          .where(
            (s) =>
                !s.startDate.isAfter(widget.data.careerDate) &&
                !s.endDate.isBefore(widget.data.careerDate),
          )
          .firstOrNull
          ?.id ??
      widget.data.seasons.first.id;
  late String? _playerId = _existing?['playerId'] as String?;
  late String _teamId = _existing?['teamId'] as String? ?? widget.person.teamId;
  late String? _leagueId =
      _existing?['leagueId'] as String? ?? widget.person.leagueId;
  late DateTime _start =
      DateTime.tryParse('${_existing?['startDate']}') ?? widget.data.careerDate;
  late DateTime? _end = DateTime.tryParse('${_existing?['endDate']}');
  late Future<List<Map<String, Object?>>> _roster = _loadRoster();
  bool _saving = false;

  String get _version => widget.person.fifaVersion;

  Season get _season => widget.data.seasons.firstWhere(
    (s) => s.id == _seasonId,
    orElse: () => widget.data.seasons.first,
  );

  Future<List<Map<String, Object?>>> _loadRoster() =>
      SqlService.instance.getTeamPlayers(widget.person.id, _seasonId);

  @override
  void dispose() {
    _description.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final value = await showCareerDatePicker(
      context: context,
      personId: widget.person.id,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: start ? _start : (_end ?? _start),
    );
    if (mounted && value != null) {
      setState(() => start ? _start = value : _end = value);
    }
  }

  Future<T?> _sheet<T>(
    String title,
    List<Widget> Function(BuildContext) rows,
  ) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: rows(context)),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _pickSeason() async {
    final value = await _sheet<String>(
      'seasons.season'.tr(),
      (context) => [
        for (final s in widget.data.seasons)
          ListTile(
            title: Text(seasonText(s)),
            trailing: s.id == _seasonId ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, s.id),
          ),
      ],
    );
    if (value != null && value != _seasonId) {
      setState(() {
        _seasonId = value;
        _roster = _loadRoster();
      });
    }
  }

  Future<void> _pickPlayer() async {
    final roster = await _roster;
    if (!mounted) return;
    final options = roster.isNotEmpty
        ? [
            for (final r in roster)
              (
                id: r['playerId'] as String,
                name:
                    '${r['customName'] ?? widget.data.players[r['playerId']]?['name'] ?? '?'}',
                position: r['customPositionId']?.toString(),
                real: r['realPlayerId']?.toString(),
                avatar: r['customAvatarFilePath']?.toString(),
              ),
          ]
        : [
            for (final p in widget.data.players.values)
              (
                id: p['id'] as String,
                name: '${p['name'] ?? '?'}',
                position: p['positionId']?.toString(),
                real: p['realPlayerId']?.toString(),
                avatar: p['customAvatarFilePath']?.toString(),
              ),
          ];
    options.sort((a, b) => a.name.compareTo(b.name));
    final value = await _sheet<String>(
      'players.player'.tr(),
      (context) => [
        for (final p in options)
          ListTile(
            leading: PlayerAvatar(
              fifaVersion: _version,
              realPlayerId: p.real,
              customAvatarFilePath: p.avatar,
            ),
            title: Text(p.name),
            subtitle: Text(positionShortName(p.position)),
            trailing: p.id == _playerId ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, p.id),
          ),
      ],
    );
    if (value != null) setState(() => _playerId = value);
  }

  Future<void> _pickTeam() async {
    final teams = <String, String?>{
      widget.person.teamId: widget.person.leagueId,
    };
    for (final f in widget.data.fixtures) {
      teams.putIfAbsent(
        '${f['playerTeamId']}',
        () => f['playerTeamLeagueId']?.toString(),
      );
    }
    final value = await _sheet<MapEntry<String, String?>>(
      'teams.team'.tr(),
      (context) => [
        for (final team in teams.entries)
          ListTile(
            leading: TeamLogo.lookup(
              fifaVersion: _version,
              teamId: team.key,
              leagueId: team.value,
            ),
            title: Text(
              widget.data.catalog.teamLabel(
                _version,
                team.key,
                leagueId: team.value,
              ),
            ),
            trailing: team.key == _teamId ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, team),
          ),
      ],
    );
    if (value != null) {
      setState(() {
        _teamId = value.key;
        _leagueId = value.value;
      });
    }
  }

  Future<void> _save() async {
    if (_playerId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('players.selectTeamPlayer'.tr())));
      return;
    }
    if (_end != null && _end!.isBefore(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A data final deve ser posterior ao início.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await SqlService.instance.saveInjury({
        'id': _existing?['id'] ?? const Uuid().v4(),
        'personId': widget.person.id,
        'playerId': _playerId,
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'startDate': _start.toIso8601String(),
        'endDate': _end?.toIso8601String(),
        'seasonId': _seasonId,
        'teamId': _teamId,
        'expectedRecoveryDays': int.tryParse(_days.text),
        'leagueId': _leagueId ?? widget.person.leagueId,
        'createdAt':
            _existing?['createdAt'] ?? DateTime.now().toIso8601String(),
      }, update: _existing != null);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar lesão: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = _existing!['id'] as String;
    final match = SqlService.matchInjuryKey(id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('injuries.removeInjureConfirmation'.tr()),
        content: match == null
            ? null
            : const Text(
                'Esta lesão veio de uma partida: ela também será desmarcada na partida.',
              ),
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
    await SqlService.instance.deleteInjury(widget.person.id, id);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _selector({
    required String label,
    required String value,
    Widget? leading,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: InputDecorator(
      decoration: injuryFieldDecoration(
        label,
        suffixIcon: const Icon(Icons.arrow_right),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 12)],
          Expanded(
            child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ),
  );

  Widget _dateField(String label, DateTime? value, bool start) => InkWell(
    onTap: () => _pickDate(start),
    borderRadius: BorderRadius.circular(16),
    child: InputDecorator(
      isEmpty: value == null,
      decoration: injuryFieldDecoration(
        label,
        suffixIcon: !start && value != null
            ? IconButton(
                tooltip: 'Sem data de término',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _end = null),
              )
            : const Icon(Icons.calendar_month_outlined),
      ),
      child: Text(
        value == null
            ? ''
            : '${value.day.toString().padLeft(2, '0')}/'
                  '${value.month.toString().padLeft(2, '0')}/${value.year}',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final player = widget.data.players[_playerId];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _existing == null
              ? 'injuries.addInjury'.tr()
              : 'injuries.editInjury'.tr(),
        ),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: 'common.remove'.tr(),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: Text('common.save'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
        children: [
          TextField(
            controller: _description,
            textCapitalization: TextCapitalization.sentences,
            decoration: injuryFieldDecoration('injuries.injury'.tr()),
          ),
          const SizedBox(height: 18),
          _selector(
            label: 'seasons.season'.tr(),
            value: seasonText(_season),
            onTap: _pickSeason,
          ),
          const SizedBox(height: 18),
          _selector(
            label: 'players.player'.tr(),
            value: player?['name']?.toString() ?? '',
            leading: player == null
                ? null
                : PlayerAvatar(
                    fifaVersion: _version,
                    realPlayerId: player['realPlayerId']?.toString(),
                    customAvatarFilePath: player['customAvatarFilePath']
                        ?.toString(),
                    radius: 14,
                  ),
            onTap: _pickPlayer,
          ),
          const SizedBox(height: 18),
          _selector(
            label: 'teams.team'.tr(),
            value: widget.data.catalog.teamLabel(
              _version,
              _teamId,
              leagueId: _leagueId,
            ),
            leading: TeamLogo.lookup(
              fifaVersion: _version,
              teamId: _teamId,
              leagueId: _leagueId,
              size: 26,
            ),
            onTap: _pickTeam,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _dateField('injuries.startDate'.tr(), _start, true),
              ),
              const SizedBox(width: 14),
              Expanded(child: _dateField('injuries.endDate'.tr(), _end, false)),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: injuryFieldDecoration(
              'injuries.expectedRecovery'.tr(),
              suffixText: 'injuries.timing.days'.tr().toLowerCase(),
            ),
          ),
        ],
      ),
    );
  }
}
