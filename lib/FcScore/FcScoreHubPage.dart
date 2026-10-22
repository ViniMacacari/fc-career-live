import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../utils/Components/CareerUiStyle.dart';
import 'FcScoreCareerIdentity.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';
import 'FcScoreRepository.dart';
import 'FcScoreMappingPage.dart';
import 'FcScoreDataPage.dart';
import 'FcScoreImportPage.dart';
import 'FcScoreMatchSource.dart';
import 'FcScoreWidgets.dart';
import 'FcScoreWorldImportPage.dart';
import 'CareerCompetitionsPage.dart';

class FcScoreHubPage extends StatefulWidget {
  const FcScoreHubPage({
    super.key,
    required this.api,
    required this.repository,
    required this.remote,
    required this.person,
    required this.link,
  });
  final FcScoreApi api;
  final FcScoreRepository repository;
  final FcScoreRemoteCareer remote;
  final Person person;
  final FcScoreLink link;
  @override
  State<FcScoreHubPage> createState() => _FcScoreHubPageState();
}

class _FcScoreHubPageState extends State<FcScoreHubPage> {
  late FcScoreRemoteCareer _remote = widget.remote;
  late Person _person = widget.person;
  late FcScoreLink _link = widget.link;
  FcScoreCareerIdentity? _identity;

  String _competitionName(FcJson competition) =>
      _identity
          ?.competitions[_link.competitions[fcId(competition['id'])]]
          ?.label ??
      fcName(competition['name']);

  String _teamName(FcJson team) {
    final local = _link.teams[fcId(team['id'])];
    return (local == null || local.startsWith('new:')
            ? null
            : _identity?.club(local, null)?.label) ??
        fcName(team['name']);
  }

  bool _busy = false;
  bool _linked = true;
  String? _error;
  @override
  void initState() {
    FcScoreCareerIdentity.load(widget.repository.sql, widget.person).then((
      identity,
    ) {
      if (mounted) setState(() => _identity = identity);
    });
    super.initState();
    _syncState();
  }

  Future<void> _syncState() async {
    final saved = await widget.repository.linkFor(_person.id);
    if (saved != null && saved.saveId == _link.saveId) _link = saved;
    if (mounted) setState(() => _linked = _link.belongsTo(_remote, _person));
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      FcScoreRemoteCareer remote;
      try {
        remote = await FcScoreRemoteCareer.load(
          widget.api,
          _link.saveId,
          _link.gameVersion,
        );
      } on FcScoreException catch (error) {
        if (error.status != 404) rethrow;
        final current = widget.repository.currentSave(
          await widget.api.list('careers'),
          _link,
          _person,
        );
        if (current == null) rethrow;
        remote = await FcScoreRemoteCareer.load(
          widget.api,
          fcId(current['id']),
          _link.gameVersion,
        );
      }
      if (!_link.belongsTo(remote, _person)) {
        throw const FcScoreException(
          'O clube ou o tipo desta carreira mudou. Revise o vínculo com o aplicativo.',
        );
      }
      if (_link.saveId != remote.saveId || _link.saveName != remote.saveName) {
        _link = await widget.repository.moveLink(
          _link,
          remote.saveId,
          saveName: remote.saveName,
        );
      }
      if (mounted) setState(() => _remote = remote);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mapping() async {
    final bound = await Navigator.push<FcBoundCareer>(
      context,
      MaterialPageRoute(
        builder: (_) => FcScoreMappingPage(
          remote: _remote,
          repository: widget.repository,
          initialPerson: _person,
          reviewExisting: true,
        ),
      ),
    );
    if (bound != null && mounted) {
      setState(() {
        _person = bound.person;
        _link = bound.link;
        _linked = _link.belongsTo(_remote, _person);
      });
    }
  }

  Future<void> _report() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final raw = await widget.api.report(_link.saveId);
      if (!mounted) return;
      await _preview(FcScoreMatch.fromReport(raw));
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(FcScoreMatch match) async {
    var resolved = match;
    if (!match.detailed) {
      setState(() {
        _busy = true;
        _error = null;
      });
      resolved = await fcDetailedMatch(widget.api, match);
      if (!mounted) return;
      setState(() => _busy = false);
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FcScoreImportPage(
          repository: widget.repository,
          person: _person,
          link: _link,
          match: resolved,
          api: widget.api,
        ),
      ),
    );
  }

  Future<void> _importWorld() async {
    await _refresh();
    if (!mounted || _error != null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FcScoreWorldImportPage(
          api: widget.api,
          repository: widget.repository,
          remote: _remote,
          person: _person,
          link: _link,
        ),
      ),
    );
    await _syncState();
  }

  Future<void> _localCompetitions() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => CareerCompetitionsPage(
        person: _person,
        repository: widget.repository,
        initialSeasonId: _link.seasonId,
      ),
    ),
  );
  void _data(FcScoreView kind) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => FcScoreDataPage(
        api: widget.api,
        remote: _remote,
        kind: kind,
        onMatch: _preview,
        onImport: _importWorld,
        updatingCareer: _linked,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final overview = _remote.overview,
        standing = fcObject(overview['leagueStanding']);
    final budget = fcObject(overview['budgets']),
        squad = fcObject(overview['squad']);
    final last = fcObject(overview['lastMatch']),
        next = fcObject(overview['nextMatch']);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FC Score'),
        actions: [
          IconButton(
            tooltip: 'Revisar vínculos',
            onPressed: _busy ? null : _mapping,
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: 'Atualizar dados do save',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              CareerPageHeader(
                title: fcName(_remote.club['name']),
                subtitle:
                    '${_person.name} · ${_link.gameVersion}\nSave em ${fcDay(overview['currentDate'])}',
                icon: Icons.sports_soccer,
                eyebrow: 'Carreira conectada',
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) FcNotice(_error!, error: true),
              FcPanel(
                child: Column(
                  children: [
                    FcFact('Liga', fcName(_remote.league['name'])),
                    if (standing.isNotEmpty) ...[
                      FcFact(
                        'Classificação',
                        '${fcValue(standing['position'])}º · ${fcValue(standing['points'])} pontos',
                      ),
                      FcFact(
                        'Campanha',
                        '${fcValue(standing['wins'])} V · ${fcValue(standing['draws'])} E · ${fcValue(standing['losses'])} D',
                      ),
                    ],
                    FcFact(
                      'Elenco',
                      '${fcValue(squad['players'])} jogadores · OVR ${fcValue(squad['averageOverall'])}',
                    ),
                    FcFact(
                      'Orçamento de transferências',
                      fcMoney(budget['transfer']),
                    ),
                    FcFact('Orçamento salarial', fcMoney(budget['wage'])),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _importWorld,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  _linked ? 'Atualizar carreira' : 'Importar para carreira',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _localCompetitions,
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Competições da carreira'),
              ),
              const SizedBox(height: 16),
              const FcNotice(
                'Atualize tabelas, calendário e elencos na sua carreira. Seus vínculos são reutilizados e os dados ficam disponíveis sem conexão.',
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _report,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Último relatório detalhado'),
              ),
              const SizedBox(height: 14),
              const FcNotice(
                'Confira a data e o placar na prévia. O último relatório exportado pode ser de um jogo anterior ao último resultado do save.',
              ),
              if (last.isNotEmpty) ...[
                const FcSection('Último resultado do save'),
                FcFixtureCard(
                  fixture: last,
                  competitionName: _competitionName,
                  teamName: _teamName,
                  onTap: _busy
                      ? null
                      : () => _preview(
                          FcScoreMatch.fromFixture(last, _link.saveId),
                        ),
                ),
              ],
              if (next.isNotEmpty) ...[
                const FcSection('Próximo jogo'),
                FcFixtureCard(
                  fixture: next,
                  competitionName: _competitionName,
                  teamName: _teamName,
                ),
              ],
              const FcSection(
                'Consultar dados da API',
                subtitle: 'Dados consultados diretamente no save do PC.',
              ),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final kind in FcScoreView.values)
                      SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: _FcShortcut(
                          kind: kind,
                          onTap: () => _data(kind),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _FcShortcut extends StatelessWidget {
  const _FcShortcut({required this.kind, required this.onTap});
  final FcScoreView kind;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = CareerUiColors(context);
    return Material(
      color: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(kind.icon, color: colors.accent, size: 26),
              const SizedBox(height: 14),
              Text(
                kind.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                kind.subtitle,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FcFixtureCard extends StatelessWidget {
  const FcFixtureCard({
    super.key,
    required this.fixture,
    this.onTap,
    this.note,
    this.action = 'Revisar importação →',
    this.competitionName,
    this.teamName,
  });
  final String Function(FcJson competition)? competitionName;
  final String Function(FcJson team)? teamName;
  final FcJson fixture;
  final VoidCallback? onTap;
  final String? note;
  final String action;
  @override
  Widget build(BuildContext context) {
    final home = fcObject(fixture['home']), away = fcObject(fixture['away']);
    return FcPanel(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Text(
              '${fcDay(fixture['date'])} ${fcId(fixture['time'])}',
              style: TextStyle(
                color: CareerUiColors(context).muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    teamName?.call(fcObject(home['team'])) ??
                        fcName(fcObject(home['team'])['name']),
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    fixture['played'] == true
                        ? '${fcValue(home['goals'])} – ${fcValue(away['goals'])}'
                        : '×',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    teamName?.call(fcObject(away['team'])) ??
                        fcName(fcObject(away['team'])['name']),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              competitionName?.call(fcObject(fixture['competition'])) ??
                  fcName(fcObject(fixture['competition'])['name']),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CareerUiColors(context).muted,
                fontSize: 12,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(
                note!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (onTap != null) ...[
              const SizedBox(height: 12),
              Text(
                action,
                style: TextStyle(
                  color: CareerUiColors(context).accent,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
