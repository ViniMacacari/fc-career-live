import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/Components/CareerPageWidgets.dart';
import 'FcScoreApi.dart';
import 'FcScoreConnectionPage.dart';
import 'FcScoreHubPage.dart' show FcFixtureCard;
import 'FcScoreImportPage.dart';
import 'FcScoreMatchSource.dart';
import 'FcScoreModels.dart';
import 'FcScoreRepository.dart';
import 'FcScoreWidgets.dart';

class FcScoreImportShortcut extends StatelessWidget {
  const FcScoreImportShortcut({
    super.key,
    required this.person,
    this.padding = EdgeInsets.zero,
  });
  final Person person;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: FcChoice(
      title: 'FC Score',
      value: 'Importar partida da API',
      icon: Icons.cloud_download_outlined,
      onTap: () async {
        final imported = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => FcScoreQuickImportPage(person: person),
          ),
        );
        if (imported == true && context.mounted) Navigator.pop(context, true);
      },
    ),
  );
}

class FcScoreQuickImportPage extends StatefulWidget {
  const FcScoreQuickImportPage({
    super.key,
    required this.person,
    this.repository,
    this.apiFactory,
    this.target,
  });
  final Person person;
  final FcScoreRepository? repository;
  final FcScoreApi Function(Uri)? apiFactory;
  final Map<String, Object?>? target;
  @override
  State<FcScoreQuickImportPage> createState() => _FcScoreQuickImportPageState();
}

class _FcScoreQuickImportPageState extends State<FcScoreQuickImportPage> {
  late final _repo = widget.repository ?? FcScoreRepository();
  FcScoreApi? _api;
  FcScoreLink? _link;
  List<FcJson> _fixtures = [];
  Map<String, FcJson> _reports = {};
  Map<String, FcScoreMatch> _unsaved = {};
  final Map<String, FcImportState> _states = {};
  Map<String, String> _linked = {};
  FcJson? _recommended;
  String? get _targetId =>
      widget.target == null ? null : fcId(widget.target!['id']);
  List<String> _addresses = [];
  String? _error;
  bool _loading = true, _ready = false, _opening = false, _imported = false;
  bool _needsLink = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _ready = false;
      _error = null;
      _needsLink = false;
    });
    try {
      final link = await _repo.linkFor(widget.person.id);
      if (link == null) {
        _needsLink = true;
        return;
      }
      final api = _api;
      if (api == null) {
        _addresses = await _repo.recentAddresses();
        return;
      }
      final save = _repo.currentSave(
        await api.list('careers'),
        link,
        widget.person,
      );
      if (save == null) {
        throw const FcScoreException(
          'O save desta carreira não foi encontrado no PC. Conecte-se e escolha a carreira novamente.',
        );
      }
      _link = fcId(save['id']) == link.saveId
          ? link
          : await _repo.moveLink(link, fcId(save['id']));
      _link = await _repo.rememberCareerAddress(_link!, api.address);
      final page = await api.object(
        api.careerPath(_link!.saveId, 'fixtures'),
        query: {
          'status': 'played',
          'limit': widget.target == null ? '30' : '400',
        },
      );
      _fixtures = fcList(page['items']);
      List<FcJson> summaries;
      try {
        summaries = await api.list('matches');
      } on FcScoreException {
        summaries = [];
      }
      _reports = await fcReportsByFixture(api, reports: summaries);
      final unsaved = await fcUnsavedReports(
        api,
        saveId: _link!.saveId,
        savedAt: fcId(save['savedAt']),
        clubId: _link!.remoteClubId,
        playedFixtures: {for (final f in _fixtures) fcId(f['id'])},
        reports: summaries,
      );
      _unsaved = {for (final match in unsaved) match.fixtureId: match};
      _fixtures = [...unsaved.map(fcFixtureOf), ..._fixtures];
      if (widget.target == null) {
        await _refreshStates();
      } else {
        _linked = await _repo.linkedFixtures(widget.person);
        final current = _fixtures
            .where((f) => _linked[_match(f).remoteKey] == _targetId)
            .firstOrNull;
        final best = fcRecommendedMatch(widget.target!, [
          for (final f in _fixtures)
            if (!_linkedElsewhere(f)) _match(f),
        ], _link!);
        _recommended =
            current ??
            _fixtures
                .where((f) => best != null && fcId(f['id']) == best.fixtureId)
                .firstOrNull;
      }
      _ready = true;
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect(String address) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final uri = Uri.parse(address);
    final api = widget.apiFactory?.call(uri) ?? FcScoreApi(uri);
    try {
      await api.connect();
      await _repo.rememberAddress(uri);
      _api?.close();
      _api = api;
    } catch (error) {
      api.close();
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
      return;
    }
    if (mounted) await _load();
  }

  FcScoreMatch _match(FcJson fixture) =>
      FcScoreMatch.fromFixture(fixture, _link!.saveId);

  bool _linkedElsewhere(FcJson fixture) {
    final at = _linked[_match(fixture).remoteKey];
    return at != null && at != _targetId;
  }

  Future<void> _refreshStates() async {
    for (final fixture in _fixtures) {
      final match = _match(fixture);
      _states[match.fixtureId] = await _repo.importState(
        widget.person,
        _link!,
        match,
      );
    }
  }

  Future<void> _open(FcJson fixture) async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final before = _states[fcId(fixture['id'])];
      final match =
          _unsaved[fcId(fixture['id'])] ??
          await fcDetailedMatch(
            _api!,
            _match(fixture),
            reports: _reports.values.toList(),
          );
      if (!mounted) return;
      final completed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => FcScoreImportPage(
            repository: _repo,
            person: widget.person,
            link: _link!,
            match: match,
            target: widget.target,
            api: _api,
          ),
        ),
      );
      if (widget.target != null) {
        if (completed == true && mounted) Navigator.pop(context, true);
        return;
      }
      await _refreshStates();
      if (_states[fcId(fixture['id'])] != before) _imported = true;
    } catch (error) {
      _error = '$error';
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openConnection() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FcScoreConnectionPage(initialPerson: widget.person),
      ),
    );
    if (mounted) await _load();
  }

  String _note(FcJson fixture) {
    final id = fcId(fixture['id']);
    final detailed = _reports.containsKey(id);
    final available = _unsaved.containsKey(id)
        ? 'Ainda não salva no jogo · com desempenho dos jogadores'
        : detailed
        ? 'Com desempenho dos jogadores'
        : 'Somente placar';
    if (widget.target != null) {
      final at = _linked[_match(fixture).remoteKey];
      return at == null
          ? available
          : at == _targetId
          ? 'Vinculada a esta partida'
          : 'Já vinculada a outra partida da carreira';
    }
    return switch (_states[id]) {
      FcImportState.alreadyImported => 'Já importada',
      FcImportState.canComplete when detailed =>
        'Placar importado · completar com os jogadores',
      FcImportState.canComplete => 'Placar importado',
      _ => available,
    };
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.of(context).pop(_imported);
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.target == null ? 'Importar da API' : 'Completar com a API',
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              CareerPageHeader(
                title: widget.target == null
                    ? 'Partidas do save'
                    : 'Qual é esta partida?',
                subtitle:
                    '${widget.person.name}\n${_link?.saveName ?? 'FC Score'}',
                icon: Icons.cloud_download_rounded,
                eyebrow: 'FC Score',
              ),
              if (_loading || _opening) const LinearProgressIndicator(),
              if (_needsLink) ...[
                const FcNotice(
                  'Esta carreira ainda não está vinculada a um save do jogo. Conecte-se ao PC e escolha a carreira uma vez; depois as partidas aparecem aqui.',
                ),
                FilledButton.icon(
                  onPressed: _openConnection,
                  icon: const Icon(Icons.link),
                  label: const Text('Conectar ao PC'),
                ),
              ],
              if (!_loading && !_needsLink && _api == null) ...[
                FcSection(
                  'Conectar ao PC',
                  subtitle: _addresses.isEmpty
                      ? 'Nenhuma conexão recente.'
                      : 'Toque no computador com a API aberta.',
                ),
                for (final address in _addresses)
                  FcChoice(
                    title: 'Conexão recente',
                    value:
                        '${Uri.parse(address).host}:${Uri.parse(address).port}',
                    icon: Icons.computer,
                    onTap: () => _connect(address),
                  ),
                OutlinedButton.icon(
                  onPressed: _openConnection,
                  icon: const Icon(Icons.link),
                  label: Text(
                    _addresses.isEmpty ? 'Conectar ao PC' : 'Outro endereço',
                  ),
                ),
              ],
              if (_error != null) FcNotice(_error!, error: true),
              if (_error != null && !_ready && _api != null)
                OutlinedButton.icon(
                  onPressed: _openConnection,
                  icon: const Icon(Icons.link),
                  label: const Text('Abrir conexão'),
                ),
              if (_ready && widget.target != null) ...[
                const FcNotice(
                  'Escolha o jogo do save. Só o que estiver vazio na sua partida será preenchido: o placar, os gols e cartões com os minutos, as substituições e as escalações que você registrou continuam como estão.',
                ),
                if (_recommended == null)
                  const FcNotice(
                    'Nenhum jogo do save bate com a data desta partida. Escolha o jogo certo na lista.',
                  )
                else ...[
                  const FcSection(
                    'Recomendada',
                    subtitle: 'O jogo do save mais parecido com esta partida',
                  ),
                  FcFixtureCard(
                    key: const Key('fc-recommended-match'),
                    fixture: _recommended!,
                    note: _note(_recommended!),
                    onTap: _opening ? null : () => _open(_recommended!),
                    action: 'Revisar e completar →',
                  ),
                ],
                FcSection(
                  'Outros jogos do save',
                  subtitle: _fixtures.isEmpty
                      ? 'Nenhuma partida realizada neste save.'
                      : 'Do mais recente ao mais antigo',
                ),
                for (final fixture in _fixtures)
                  if (fixture != _recommended)
                    FcFixtureCard(
                      fixture: fixture,
                      note: _note(fixture),
                      action: 'Revisar e completar →',
                      onTap: _opening || _linkedElsewhere(fixture)
                          ? null
                          : () => _open(fixture),
                    ),
              ],
              if (_ready && widget.target == null) ...[
                const FcNotice(
                  'Jogos com relatório exportado trazem notas, gols, assistências e cartões de cada jogador. Os demais trazem só o placar.',
                ),
                if (_unsaved.isNotEmpty)
                  const FcNotice(
                    'Partidas exportadas depois do último save do jogo aparecem no topo. O jogo ainda não gravou o resultado, mas o relatório já tem todos os jogadores e pode ser importado agora.',
                  ),
                FcSection(
                  'Partidas realizadas',
                  subtitle: _fixtures.isEmpty
                      ? 'Nenhuma partida realizada neste save.'
                      : '${_fixtures.length} jogos mais recentes',
                ),
                for (final fixture in _fixtures)
                  FcFixtureCard(
                    fixture: fixture,
                    note: _note(fixture),
                    onTap: _opening ? null : () => _open(fixture),
                  ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}
