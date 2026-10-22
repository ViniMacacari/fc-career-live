import '../utils/AppColors.dart';

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/Person.dart';
import '../RootPage/DrawerWidget.dart';
import '../Settings/AISettingsPage.dart';
import '../utils/SqlService.dart';
import '../utils/GameCatalog.dart';
import '../utils/databaseUtils.dart';
import 'TwitterGenerationService.dart';
import 'TwitterModels.dart';
import 'TwitterSettingsPage.dart';
import 'TwitterStore.dart';
import 'TwitterStyle.dart';
import 'XGenerationDialog.dart';
import 'XContextButton.dart';
import 'TwitterPublicationDate.dart';
import 'TwitterClubPostForm.dart';
import 'TwitterFeedContext.dart';

TwitterAccount _postAccount(SocialRow row) =>
    TwitterAccount.fromMap({...row, 'id': row['accountId']});
void _message(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(TwitterGenerationService.errorText(error))),
    );

TwitterAccount? mentionedAccount(List<TwitterAccount> accounts, String token) {
  String plain(String value) => normalizeTwitterHandle(value).toLowerCase();
  final wanted = plain(token);
  if (wanted.isEmpty) return null;
  final close =
      accounts
          .where(
            (a) =>
                a.handle.length >= 4 &&
                (wanted.startsWith(a.handle.toLowerCase()) ||
                    a.handle.toLowerCase().startsWith(wanted)),
          )
          .toList()
        ..sort((a, b) => b.handle.length.compareTo(a.handle.length));
  return accounts.where((a) => a.handle.toLowerCase() == wanted).firstOrNull ??
      accounts.where((a) => plain(a.name) == wanted).firstOrNull ??
      close.firstOrNull;
}

Future<bool> _confirmAi(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => XAlertDialog(
        title: Text(title),
        content: Text('$message Isso faz uma chamada à IA.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Regerar'),
          ),
        ],
      ),
    ) ==
    true;

void _profile(BuildContext context, Person person, String id) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => TwitterProfilePage(person: person, accountId: id),
  ),
);
void _thread(BuildContext context, Person person, String id) => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => TwitterThreadPage(person: person, postId: id),
  ),
);
Future<void> _compose(
  BuildContext context,
  Person person, {
  SocialRow? parent,
}) async {
  final id = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) => TwitterComposePage(person: person, parent: parent),
    ),
  );
  if (parent != null && id != null && context.mounted) {
    _thread(context, person, id);
  }
}

class TwitterPage extends StatefulWidget {
  const TwitterPage({super.key, required this.person});
  final Person person;
  @override
  State<TwitterPage> createState() => _TwitterPageState();
}

class _TwitterPageState extends State<TwitterPage> {
  final _store = TwitterStore.instance, _scroll = ScrollController();
  final _generator = TwitterGenerationService.instance;
  List<SocialRow> _posts = [], _jobs = [];
  List<TwitterAccount> _accounts = [];
  bool _loading = true, _following = false;
  String _search = '', _error = '';
  int _destination = 0, _limit = 40, _request = 0;
  Timer? _searchTimer;
  @override
  void initState() {
    super.initState();
    _store.addListener(_reload);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await CustomImageFiles.docsDir();
      await _store.initialize(widget.person);
      await _generator.syncLatest(widget.person);
      await _reload();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = TwitterGenerationService.errorText(e);
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _store.removeListener(_reload);
    _scroll.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final request = ++_request;
    try {
      final posts = _destination == 2
          ? await _store.notifications(widget.person.id, limit: _limit)
          : await _store.posts(
              widget.person.id,
              followingOnly: _following && _destination == 0,
              search: _destination == 1 ? _search : '',
              limit: _limit,
            );
      final accounts = await _store.accounts(widget.person.id);
      final jobs = await _generator.jobs(widget.person.id);
      if (mounted && request == _request) {
        setState(() {
          _posts = posts;
          _accounts = accounts
              .where((a) => !TwitterStore.isLegacyExample(a))
              .toList();
          _jobs = jobs;
          _loading = false;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = TwitterGenerationService.errorText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _generate() async {
    try {
      final fixtures = await SqlService.instance.getFixtures(
        widget.person.id,
        widget.person.category,
      );
      final transfers = await _generator.transferEvents(widget.person);
      final catalog = await GameCatalog.load();
      final club = await _store.ensureClub(
        widget.person,
        widget.person.teamId,
        widget.person.leagueId,
      );
      var clubDate = await TwitterFeedContext.publicationDate(
        await _store.db,
        widget.person,
      );
      if (!mounted) return;
      final topic = TextEditingController();
      var topicDate = DateUtils.dateOnly(
        fixtures.isEmpty
            ? DateTime.now()
            : DateTime.parse(fixtures.first['date'] as String),
      );
      final chosen = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: xColors(context).panel,
        isScrollControlled: true,
        builder: (context) => XSafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.75,
            child: DefaultTabController(
              length: 4,
              initialIndex: fixtures.isEmpty ? 2 : 0,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Gerar posts sobre...',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'Partidas'),
                      Tab(text: 'Transferências'),
                      Tab(text: 'Assunto'),
                      Tab(text: 'Clube'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        fixtures.isEmpty
                            ? const Center(
                                child: Text('Nenhuma partida registrada.'),
                              )
                            : ListView(
                                children: [
                                  for (final f in fixtures.take(30))
                                    ListTile(
                                      title: Text(
                                        '${catalog.teamLabel(widget.person.fifaVersion, f['playerTeamId'] as String, leagueId: f['playerTeamLeagueId'] as String?)} '
                                        '${f['playerTeamScore']} × ${f['oppositeTeamScore']} '
                                        '${catalog.teamLabel(widget.person.fifaVersion, f['oppositeTeamId'] as String, leagueId: f['oppositeTeamLeagueId'] as String?)}',
                                      ),
                                      subtitle: Text(
                                        DateFormat('dd/MM/yyyy').format(
                                          DateTime.parse(f['date'] as String),
                                        ),
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => Navigator.pop(
                                        context,
                                        'match:${f['id']}',
                                      ),
                                    ),
                                ],
                              ),
                        transfers.isEmpty
                            ? const Center(
                                child: Text(
                                  'Nenhuma transferência registrada.',
                                ),
                              )
                            : ListView(
                                children: [
                                  for (final t in transfers)
                                    ListTile(
                                      leading: const Icon(Icons.swap_horiz),
                                      title: Text(
                                        t['playerName']?.toString() ??
                                            'Jogador',
                                      ),
                                      subtitle: Text(
                                        '${_generator.transferEventLabel(widget.person, t)} · '
                                        '${DateFormat('dd/MM/yyyy').format(DateTime.parse(t['date'] as String))}',
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => Navigator.pop(
                                        context,
                                        'transfer:${t['id']}',
                                      ),
                                    ),
                                ],
                              ),
                        StatefulBuilder(
                          builder: (context, setTopicState) =>
                              SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  20,
                                  20,
                                  20,
                                  20 + MediaQuery.viewInsetsOf(context).bottom,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Escreva um assunto e a torcida, as páginas e os jornais comentam, com o momento do clube de pano de fundo.',
                                      style: TextStyle(
                                        color: xColors(context).muted,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () async {
                                        final selected = await showDatePicker(
                                          context: context,
                                          initialDate: topicDate,
                                          firstDate: DateTime(1900),
                                          lastDate: DateTime(2200, 12, 31),
                                        );
                                        if (selected != null &&
                                            context.mounted) {
                                          setTopicState(
                                            () => topicDate = selected,
                                          );
                                        }
                                      },
                                      child: InputDecorator(
                                        decoration: const InputDecoration(
                                          labelText: 'Data da geração',
                                          suffixIcon: Icon(
                                            Icons.calendar_month_outlined,
                                          ),
                                          helperText: 'A conversa usa o contexto até esse dia.',
                                        ),
                                        child: Text(
                                          DateFormat('dd/MM/yyyy')
                                              .format(topicDate),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextField(
                                      controller: topic,
                                      minLines: 3,
                                      maxLines: 6,
                                      maxLength: 300,
                                      textCapitalization:
                                          TextCapitalization.sentences,
                                      decoration: const InputDecoration(
                                        hintText: 'Ex.: boatos de que o Calleri vai sair no fim da temporada',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: () {
                                        final text = topic.text.trim();
                                        if (text.isNotEmpty) {
                                          Navigator.pop(context, 'topic:$text');
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.auto_awesome_outlined,
                                      ),
                                      label: const Text('Gerar posts'),
                                    ),
                                  ],
                                ),
                              ),
                        ),
                        TwitterClubPostForm(
                          club: club,
                          version: widget.person.fifaVersion,
                          initialDate: clubDate,
                          onSubmit: (text, date) {
                            clubDate = date;
                            Navigator.pop(context, 'club:$text');
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      topic.dispose();
      if (chosen == null) return;
      if (chosen.startsWith('club:')) {
        await _generator.generateClubPost(
          widget.person,
          chosen.substring(5),
          date: clubDate,
        );
      } else if (chosen.startsWith('topic:')) {
        await _generator.generateTopic(
          widget.person,
          chosen.substring(6),
          date: topicDate,
        );
      } else if (chosen.startsWith('transfer:')) {
        await _generator.generateTransfer(widget.person, chosen.substring(9));
      } else {
        await _generator.generate(
          widget.person,
          fixtureId: chosen.substring(6),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              chosen.startsWith('club:')
                  ? 'Post publicado pela conta oficial do clube.'
                  : 'Posts e respostas gerados.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _message(context, e);
    }
  }

  Future<void> _pullToRefresh() async {
    if (_destination != 0 || _generator.isBusy(widget.person.id)) {
      return _reload();
    }
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => XTheme(
        builder: (context) => XAlertDialog(
          title: const Text('Atualizar o feed?'),
          content: const Text(
            'Continue as conversas recentes com o padrão salvo ou escolha o que gerar. Gerar posts usa a IA configurada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'reload'),
              child: const Text('Só recarregar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'custom'),
              child: const Text('Gerar personalizado'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'default'),
              child: const Text('Gerar posts'),
            ),
          ],
        ),
      ),
    );
    try {
      if (action == 'default') await _generator.generateMore(widget.person);
      if (action == 'custom' && mounted) {
        final request = await showXGenerationDialog(context, widget.person);
        if (request != null) {
          await _generator.generateCustom(
            widget.person,
            request.selection,
            fixtureId: request.fixtureId,
          );
        }
      }
    } catch (e) {
      if (mounted) _message(context, e);
    }
    await _reload();
  }

  Future<void> _settings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TwitterSettingsPage(person: widget.person),
      ),
    );
    if (mounted) await _reload();
  }

  Widget _status() {
    if (_generator.isBusy(widget.person.id)) {
      final current = _jobs
          .where((job) => job['status'] == 'running')
          .firstOrNull;
      return ListTile(
        leading: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text(
          current?['eventType'] == 'clubTopic'
              ? 'O clube está preparando o post...'
              : 'O feed está ganhando novos posts...',
        ),
        subtitle: Text(
          current == null
              ? 'Você pode continuar usando o aplicativo.'
              : '${current['generatedPostCount'] ?? 0}/${current['postCount'] ?? '?'} posts publicados. Você pode continuar usando o aplicativo.',
        ),
      );
    }
    final failed = _jobs
        .where((j) => ['failed', 'waiting', 'queued'].contains(j['status']))
        .firstOrNull;
    final error =
        failed?['error']?.toString() ?? _generator.errors[widget.person.id];
    final legacyStyleFailure =
        error?.startsWith(
              'A resposta anterior está salva, mas o contexto mudou.',
            ) ==
            true ||
        const {
          'A IA não respeitou a linguagem de arquibancada. Tente novamente.',
          'A IA não respeitou a distribuição das torcidas. Tente novamente.',
          'Use autores diferentes nas respostas ao clube.',
        }.contains(error);
    if (failed != null || error != null) {
      return ListTile(
        leading: Icon(
          Icons.auto_awesome_outlined,
          color: xColors(context).accent,
        ),
        title: Text(
          (failed?['savedResponseCount'] as int? ?? 0) > 0
              ? 'Geração salva para retomar'
              : 'Geração pendente',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: (failed?['savedResponseCount'] as int? ?? 0) > 0
            ? const Text('Reaproveitar a etapa recebida.')
            : legacyStyleFailure
            ? const Text(
                'A resposta não foi salva. Retomar fará uma nova chamada à IA.',
              )
            : null,
        trailing: IconButton(
          tooltip: failed == null
              ? 'Fechar aviso'
              : (failed['savedResponseCount'] as int? ?? 0) > 0
              ? 'Retomar resposta salva'
              : 'Tentar novamente',
          icon: Icon(failed == null ? Icons.close : Icons.refresh),
          onPressed: () async {
            if (failed != null) {
              await _generator.retry(widget.person, failed['id'] as String);
            } else {
              _generator.errors.remove(widget.person.id);
              _store.changed();
            }
          },
        ),
        onTap: () async {
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => XAlertDialog(
              title: const Text('Geração do X'),
              content: SingleChildScrollView(
                child: SelectableText(
                  legacyStyleFailure
                      ? 'A versão anterior interrompeu esta geração. As etapas recebidas serão reaproveitadas; somente conteúdo ainda não recebido precisa de uma nova chamada à IA.'
                      : error ?? 'A geração aguarda a configuração da IA.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Fechar'),
                ),
                if (error != null)
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: error));
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('Erro copiado.')),
                        );
                      }
                    },
                    child: const Text('Copiar erro'),
                  ),
                if (failed?['status'] == 'waiting' ||
                    error == null ||
                    RegExp(
                      r'chave|configure|sem permissão',
                      caseSensitive: false,
                    ).hasMatch(error))
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AISettingsPage(),
                        ),
                      );
                    },
                    child: const Text('Configurar IA'),
                  ),
              ],
            ),
          );
        },
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) => XTheme(
    builder: (context) => Scaffold(
      appBar: AppBar(
        leading: RootDrawerScope.leading(context),
        title: Row(
          children: [
            Icon(TablerIcons.brandX, color: xColors(context).accent, size: 28),
            const SizedBox(width: 10),
            Text(
              _destination == 2 ? 'Notificações' : 'X',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          XContextButton(personId: widget.person.id),
          IconButton(
            onPressed: _generator.isBusy(widget.person.id) ? null : _generate,
            tooltip: 'Gerar posts com IA',
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            onPressed: _settings,
            tooltip: 'Configurações do X',
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
        bottom: _destination == 0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Row(
                  children: [
                    for (final (label, selected) in [
                      ('Para você', false),
                      ('Seguindo', true),
                    ])
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _following = selected;
                              _limit = 40;
                            });
                            _reload();
                          },
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _following == selected
                                        ? xColors(context).text
                                        : xColors(context).muted,
                                  ),
                                ),
                              ),
                              Container(
                                height: 3,
                                width: 64,
                                color: _following == selected
                                    ? xColors(context).accent
                                    : Colors.transparent,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 90),
                children: [
                  if (_destination == 1) ...[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar posts, pessoas e @usuários',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) {
                          _search = value;
                          _searchTimer?.cancel();
                          _searchTimer = Timer(
                            const Duration(milliseconds: 250),
                            _reload,
                          );
                        },
                      ),
                    ),
                    for (final a in _accounts.where(
                      (a) => '${a.name} ${a.handle}'.toLowerCase().contains(
                        _search.replaceAll('@', '').toLowerCase(),
                      ),
                    ))
                      ListTile(
                        leading: TwitterAvatar(
                          account: a,
                          version: widget.person.fifaVersion,
                        ),
                        title: Text(a.name),
                        subtitle: Text('@${a.handle}'),
                        trailing: a.kind == TwitterAccountKind.user
                            ? null
                            : OutlinedButton(
                                onPressed: () => _store.follow(a),
                                child: Text(
                                  a.following ? 'Seguindo' : 'Seguir',
                                ),
                              ),
                        onTap: () => _profile(context, widget.person, a.id),
                      ),
                    const Divider(),
                  ],
                  _status(),
                  if (_error.isNotEmpty)
                    ListTile(
                      title: Text(_error),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _reload,
                      ),
                    ),
                  if (_posts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 48,
                            color: xColors(context).muted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _destination == 2
                                ? 'As respostas aos seus posts aparecem aqui.'
                                : _following
                                ? 'Siga contas para acompanhar seus posts.'
                                : 'A conversa começa aqui. Publique ou gere posts sobre uma partida.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: xColors(context).muted),
                          ),
                        ],
                      ),
                    ),
                  for (final post in _posts)
                    TwitterPostTile(person: widget.person, row: post),
                  if (_posts.length == _limit)
                    TextButton(
                      onPressed: () {
                        _limit += 40;
                        _reload();
                      },
                      child: const Text('Carregar mais'),
                    ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: xColors(context).accent,
        foregroundColor: xColors(context).onAccent,
        onPressed: () => _compose(context, widget.person),
        child: const Icon(Icons.edit_outlined),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: xColors(context).background,
        indicatorColor: xColors(context).panel,
        selectedIndex: _destination,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        onDestinationSelected: (index) {
          if (index == 3) {
            _profile(context, widget.person, '${widget.person.id}:user');
            return;
          }
          setState(() {
            _destination = index;
            _limit = 40;
          });
          _reload();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Buscar'),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            label: 'Notificações',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Perfil',
          ),
        ],
      ),
    ),
  );
}

class TwitterPostText extends StatefulWidget {
  const TwitterPostText({
    super.key,
    required this.person,
    required this.text,
    this.expanded = false,
  });
  final Person person;
  final String text;
  final bool expanded;
  @override
  State<TwitterPostText> createState() => _TwitterPostTextState();
}

class _TwitterPostTextState extends State<TwitterPostText> {
  final _links = <TapGestureRecognizer>[];
  List<TextSpan> _spans = [];
  @override
  void initState() {
    super.initState();
    _buildSpans();
  }

  @override
  void didUpdateWidget(TwitterPostText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.person.id != widget.person.id) {
      _buildSpans();
    }
  }

  void _buildSpans() {
    for (final link in _links) {
      link.dispose();
    }
    _links.clear();
    _spans = [];
    var offset = 0;
    for (final match in RegExp(
      r'@[A-Za-z0-9_]{1,15}|#[\wÀ-ÿ]+',
    ).allMatches(widget.text)) {
      if (match.start > offset) {
        _spans.add(TextSpan(text: widget.text.substring(offset, match.start)));
      }
      final token = match.group(0)!;
      TapGestureRecognizer? link;
      if (token.startsWith('@')) {
        link = TapGestureRecognizer()
          ..onTap = () async {
            try {
              final account = mentionedAccount(
                await TwitterStore.instance.accounts(widget.person.id),
                token.substring(1),
              );
              if (!mounted) return;
              if (account != null) {
                _profile(context, widget.person, account.id);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Conta $token não encontrada.')),
                );
              }
            } catch (e) {
              if (mounted) {
                _message(context, e);
              }
            }
          };
        _links.add(link);
      }
      _spans.add(
        TextSpan(
          text: token,
          style: const TextStyle(color: AppColors.socialBlue),
          recognizer: link,
        ),
      );
      offset = match.end;
    }
    if (offset < widget.text.length) {
      _spans.add(TextSpan(text: widget.text.substring(offset)));
    }
  }

  @override
  void dispose() {
    for (final link in _links) {
      link.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final span = TextSpan(children: _spans);
    final style = TextStyle(
      fontSize: widget.expanded ? 19 : 15,
      height: 1.35,
      color: xColors(context).text,
    );
    return widget.expanded
        ? SelectableText.rich(span, style: style)
        : Text.rich(span, style: style);
  }
}

class TwitterPostTile extends StatelessWidget {
  const TwitterPostTile({
    super.key,
    required this.person,
    required this.row,
    this.expanded = false,
    this.connected = false,
    this.replyHandle,
  });
  final Person person;
  final SocialRow row;
  final bool expanded;
  final bool connected;
  final String? replyHandle;
  Widget _action(
    BuildContext context,
    IconData icon,
    Object? count,
    VoidCallback action, {
    Color? color,
    String? tooltip,
  }) => Expanded(
    child: InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Tooltip(
              message: tooltip ?? '',
              child: Icon(
                icon,
                size: 18,
                color: color ?? xColors(context).muted,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                shortSocialCount(count as int? ?? 0),
                style: TextStyle(
                  fontSize: 12,
                  color: color ?? xColors(context).muted,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final account = _postAccount(row),
        date = DateTime.tryParse(row['postedAt'] as String? ?? '');
    return InkWell(
      onTap: expanded
          ? null
          : () => _thread(context, person, row['id'] as String),
      child: Container(
        decoration: BoxDecoration(
          border: connected
              ? null
              : Border(
                  bottom: BorderSide(color: xColors(context).line, width: .5),
                ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  InkWell(
                    onTap: () => _profile(context, person, account.id),
                    child: TwitterAvatar(
                      account: account,
                      version: person.fifaVersion,
                    ),
                  ),
                  if (connected) ...[
                    const SizedBox(height: 6),
                    Expanded(
                      child: Container(width: 2, color: xColors(context).line),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _profile(context, person, account.id),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 5,
                        children: [
                          Text(
                            account.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (account.kind == TwitterAccountKind.club)
                            Icon(
                              Icons.verified,
                              color: AppColors.socialBlue,
                              size: 16,
                            ),
                          Text(
                            '@${account.handle}',
                            style: TextStyle(
                              color: xColors(context).muted,
                              fontSize: 13,
                            ),
                          ),
                          if (date != null)
                            Text(
                              '· ${DateFormat('dd/MM/yy').format(date)}',
                              style: TextStyle(
                                color: xColors(context).muted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (row['parentId'] != null)
                      InkWell(
                        onTap: () =>
                            _thread(context, person, row['parentId'] as String),
                        child: Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Text(
                            replyHandle == null
                                ? 'Em resposta a um post'
                                : 'Em resposta a @$replyHandle',
                            style: TextStyle(
                              color: xColors(context).accent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    TwitterPostText(
                      person: person,
                      text: row['text'] as String,
                      expanded: expanded,
                    ),
                    Row(
                      children: [
                        _action(
                          context,
                          Icons.chat_bubble_outline,
                          row['repliesCount'],
                          () => _compose(context, person, parent: row),
                          tooltip: 'Responder',
                        ),
                        _action(
                          context,
                          Icons.repeat,
                          row['reposts'],
                          () => TwitterStore.instance.toggleReaction(
                            person.id,
                            row['id'] as String,
                            repost: true,
                          ),
                          color: row['reposted'] == 1
                              ? xColors(context).success
                              : null,
                          tooltip: 'Repostar',
                        ),
                        _action(
                          context,
                          row['liked'] == 1
                              ? Icons.favorite
                              : Icons.favorite_border,
                          row['likes'],
                          () => TwitterStore.instance.toggleReaction(
                            person.id,
                            row['id'] as String,
                          ),
                          color: row['liked'] == 1
                              ? xColors(context).danger
                              : null,
                          tooltip: 'Curtir',
                        ),
                        IconButton(
                          tooltip: 'Ver conversa',
                          onPressed: () =>
                              _thread(context, person, row['id'] as String),
                          icon: Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: xColors(context).muted,
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Opções do post',
                          icon: Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: xColors(context).muted,
                          ),
                          onSelected: (action) => switch (action) {
                            'regen' => _regenerate(context),
                            'replies' => _regenerateReplies(context),
                            'event' => _regenerateEvent(context),
                            _ => _delete(context),
                          },
                          itemBuilder: (_) => _menu(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on TwitterPostTile {
  bool get _isReply => row['parentId'] != null;

  bool get _fromAi => row['category'] != 'user';

  List<PopupMenuEntry<String>> _menu() {
    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      Color? color,
    }) => PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
    return [
      if (_fromAi)
        item(
          'regen',
          Icons.autorenew,
          _isReply ? 'Regerar resposta' : 'Regerar post',
        ),
      if ((row['generatedRepliesCount'] as int? ?? 0) > 0)
        item('replies', Icons.forum_outlined, 'Regerar respostas'),
      if (!_isReply &&
          _fromAi &&
          row['category'] != 'club' &&
          row['eventType'] != 'clubTopic' &&
          row['eventType'] != 'user')
        item('event', Icons.dynamic_feed_outlined, 'Regerar posts do dia'),
      item(
        'delete',
        Icons.delete_outline,
        _isReply ? 'Excluir resposta' : 'Excluir post',
        color: Colors.redAccent,
      ),
    ];
  }

  Future<void> _runAi(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() action,
    required String done,
  }) async {
    if (!await _confirmAi(context, title, message) || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context)
      ..showSnackBar(const SnackBar(content: Text('Gerando com IA...')));
    try {
      await action();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(TwitterGenerationService.errorText(e))),
        );
    }
  }

  Future<void> _regenerate(BuildContext context) => _runAi(
    context,
    title: _isReply ? 'Regerar resposta?' : 'Regerar post?',
    message: _isReply
        ? 'A IA escreve um novo texto para esta resposta, da mesma conta.'
        : 'A IA escreve um novo texto para este post, da mesma conta, e as respostas dele são refeitas.',
    action: () => TwitterGenerationService.instance.regeneratePost(person, row),
    done: _isReply ? 'Resposta regerada.' : 'Post regerado.',
  );

  Future<void> _regenerateReplies(BuildContext context) => _runAi(
    context,
    title: 'Regerar respostas?',
    message: 'As respostas da IA a este post são substituídas por novas.',
    action: () =>
        TwitterGenerationService.instance.regenerateReplies(person, row),
    done: 'Respostas regeradas.',
  );

  Future<void> _regenerateEvent(BuildContext context) => _runAi(
    context,
    title: 'Regerar posts do dia?',
    message: 'Os posts gerados para este jogo, transferência ou assunto, e as respostas deles, são substituídos por novos. O post oficial do clube fica.',
    action: () =>
        TwitterGenerationService.instance.regenerateEvent(person, row),
    done: 'Novos posts sendo gerados.',
  );

  Future<void> _delete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => XAlertDialog(
        title: Text(_isReply ? 'Excluir resposta?' : 'Excluir post?'),
        content: const Text(
          'Este conteúdo e todas as respostas serão excluídos. Essa ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await TwitterStore.instance.deletePost(person, row['id'] as String);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isReply ? 'Resposta excluída.' : 'Post excluído.'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível excluir o post. Tente novamente.'),
        ),
      );
    }
  }
}

class TwitterThreadPage extends StatefulWidget {
  const TwitterThreadPage({
    super.key,
    required this.person,
    required this.postId,
    this.store,
    this.generator,
  });
  final Person person;
  final String postId;
  final TwitterStore? store;
  final TwitterGenerationService? generator;
  @override
  State<TwitterThreadPage> createState() => _TwitterThreadPageState();
}

class _TwitterThreadPageState extends State<TwitterThreadPage> {
  SocialRow? _post;
  List<SocialRow> _parents = [], _replies = [];
  bool _loading = true, _generating = false;
  int _request = 0;
  TwitterStore get _store => widget.store ?? TwitterStore.instance;
  bool get _working =>
      _generating ||
      (widget.generator ?? TwitterGenerationService.instance)
          .isGeneratingReplies(widget.person.id, widget.postId);
  String? _error;
  @override
  void initState() {
    super.initState();
    _store.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _store.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final request = ++_request;
    try {
      final store = _store;
      final post = await store.post(widget.person.id, widget.postId);
      final parents = <SocialRow>[];
      var nextId = post?['parentId'] as String?;
      final seen = {widget.postId};
      while (nextId != null && seen.add(nextId)) {
        final parent = await store.post(widget.person.id, nextId);
        if (parent == null) break;
        parents.insert(0, parent);
        nextId = parent['parentId'] as String?;
      }
      final replies = await store.posts(
        widget.person.id,
        parentId: widget.postId,
        limit: null,
      );
      if (mounted && request == _request) {
        setState(() {
          _post = post;
          _parents = parents;
          _replies = replies;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = TwitterGenerationService.errorText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_post == null || _working) return;
    setState(() => _generating = true);
    try {
      final fresh = await _store.post(widget.person.id, widget.postId);
      if (fresh == null) return;
      final total = (fresh['repliesCount'] as int? ?? 0).clamp(0, 2147483647);
      final loaded = fresh['loadedRepliesCount'] as int? ?? 0;
      if (loaded > _replies.length) {
        await _reload();
        return;
      }
      final visible = _replies.length.clamp(0, loaded);
      final target = (visible + 5).clamp(0, total);
      if (target <= visible) return;
      final missing = target - loaded;
      if (missing > 0) {
        await (widget.generator ?? TwitterGenerationService.instance)
            .generateReplies(widget.person, fresh, count: missing.clamp(1, 5));
      }
      if (!mounted) return;
      await _reload();
    } catch (e) {
      if (mounted) _message(context, e);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) => XTheme(
    builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _post == null
          ? Center(child: Text(_error ?? 'Este post foi removido.'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 80),
              children: [
                for (final (index, parent) in _parents.indexed)
                  TwitterPostTile(
                    person: widget.person,
                    row: parent,
                    connected: true,
                    replyHandle: index == 0
                        ? null
                        : _parents[index - 1]['handle'] as String?,
                  ),
                TwitterPostTile(
                  person: widget.person,
                  row: _post!,
                  expanded: true,
                  replyHandle: _parents.lastOrNull?['handle'] as String?,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Respostas · ${_post!['repliesCount'] ?? 0}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      if (_working)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                for (final reply in _replies)
                  TwitterPostTile(
                    person: widget.person,
                    row: reply,
                    replyHandle: _post!['handle'] as String?,
                  ),
                if (_replies.isEmpty &&
                    (_post!['repliesCount'] as int? ?? 0) == 0)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Seja o primeiro a responder.',
                      style: TextStyle(color: xColors(context).muted),
                    ),
                  ),
                if (_replies.length < (_post!['repliesCount'] as int? ?? 0))
                  TextButton(
                    onPressed: _working ? null : _loadMore,
                    child: Text(
                      _working
                          ? 'Carregando respostas...'
                          : 'Carregar mais respostas',
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: _post == null
          ? null
          : XSafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _compose(context, widget.person, parent: _post),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Publicar sua resposta'),
                ),
              ),
            ),
    ),
  );
}

class TwitterComposePage extends StatefulWidget {
  const TwitterComposePage({super.key, required this.person, this.parent});
  final Person person;
  final SocialRow? parent;
  @override
  State<TwitterComposePage> createState() => _TwitterComposePageState();
}

class _TwitterComposePageState extends State<TwitterComposePage> {
  final _text = TextEditingController();
  bool _saving = false, _generate = false;
  List<TwitterAccount> _accounts = [];
  DateTime? _publicationDate;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDate());
    _text.addListener(() => setState(() {}));
    unawaited(
      TwitterStore.instance.accounts(widget.person.id).then((accounts) {
        if (mounted) {
          setState(
            () => _accounts = accounts
                .where(
                  (a) =>
                      a.enabled &&
                      a.kind != TwitterAccountKind.user &&
                      !TwitterStore.isLegacyExample(a),
                )
                .toList(),
          );
        }
      }),
    );
  }

  Future<void> _loadDate() async {
    try {
      final latest = await SqlService.instance.getLatestFixtureDate(
        widget.person.id,
      );
      if (mounted) {
        setState(() {
          _dateError = null;
          _publicationDate = resolveTwitterPublicationDate(
            parent: DateTime.tryParse(
              widget.parent?['postedAt']?.toString() ?? '',
            ),
            latestFixture: latest,
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _dateError = 'Não foi possível carregar a data.');
      }
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _mentionQuery {
    final selection = _text.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final before = _text.text.substring(0, selection.baseOffset);
    return RegExp(r'(?:^|\s)@([A-Za-z0-9_]{0,15})$')
        .firstMatch(before)
        ?.group(1);
  }

  List<TwitterAccount> _suggestions(String query) {
    final wanted = normalizeTwitterHandle(query).toLowerCase();
    bool matches(TwitterAccount a) =>
        wanted.isEmpty ||
        a.handle.toLowerCase().contains(wanted) ||
        normalizeTwitterHandle(a.name).toLowerCase().contains(wanted);
    final found = _accounts.where(matches).toList()
      ..sort((a, b) {
        int rank(TwitterAccount x) =>
            x.handle.toLowerCase().startsWith(wanted) ? 0 : 1;
        return rank(a) != rank(b)
            ? rank(a).compareTo(rank(b))
            : b.followers.compareTo(a.followers);
      });
    return found.take(6).toList();
  }

  void _insertMention(TwitterAccount account) {
    final cursor = _text.selection.baseOffset;
    final start = _text.text.substring(0, cursor).lastIndexOf('@');
    if (start < 0) return;
    final text = _text.text.replaceRange(start, cursor, '@${account.handle} ');
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: start + account.handle.length + 2,
      ),
    );
  }

  Future<void> _publish() async {
    setState(() => _saving = true);
    try {
      final id = await TwitterStore.instance.publish(
        widget.person,
        _text.text,
        parent: widget.parent,
        publicationDate: _publicationDate,
      );
      if (_generate) {
        final post = await TwitterStore.instance.post(widget.person.id, id);
        if (post != null) {
          unawaited(
            TwitterGenerationService.instance
                .generateReplies(widget.person, post)
                .catchError((Object e) {
                  TwitterGenerationService.instance.errors[widget.person.id] =
                      TwitterGenerationService.errorText(e);
                  TwitterStore.instance.changed();
                }),
          );
        }
      }
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) _message(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => XTheme(
    builder: (context) => Scaffold(
      appBar: AppBar(
        title: Text(widget.parent == null ? 'Novo post' : 'Responder'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed:
                  _saving ||
                      _publicationDate == null ||
                      _text.text.trim().isEmpty
                  ? null
                  : _publish,
              child: Text(_saving ? 'Publicando...' : 'Publicar'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.parent != null) ...[
            Text(
              'Respondendo a @${widget.parent!['handle']}',
              style: TextStyle(color: xColors(context).accent),
            ),
            const SizedBox(height: 8),
            Text(
              widget.parent!['text'] as String,
              style: TextStyle(color: xColors(context).muted),
            ),
            const Divider(height: 32),
          ],
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 280,
            minLines: 5,
            maxLines: 10,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              hintText: widget.parent == null
                  ? 'O que está acontecendo?'
                  : 'Escreva sua resposta...',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
            ),
          ),
          if (_mentionQuery case final query?)
            for (final account in _suggestions(query))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: TwitterAvatar(
                  account: account,
                  version: widget.person.fifaVersion,
                  size: 36,
                ),
                title: Text(account.name),
                subtitle: Text(
                  '@${account.handle}',
                  style: TextStyle(color: xColors(context).muted),
                ),
                onTap: () => _insertMention(account),
              ),
          const SizedBox(height: 18),
          if (_publicationDate case final date?)
            TwitterPublicationDateField(
              date: date,
              enabled: !_saving,
              firstDate: DateTime.tryParse(
                widget.parent?['postedAt']?.toString() ?? '',
              ),
              onChanged: (date) => setState(() => _publicationDate = date),
            )
          else if (_dateError != null)
            ListTile(
              title: Text(_dateError!),
              trailing: TextButton(
                onPressed: _loadDate,
                child: const Text('Tentar novamente'),
              ),
            )
          else
            const LinearProgressIndicator(),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _generate,
            onChanged: (v) => setState(() => _generate = v),
            title: const Text('Gerar respostas com IA'),
            subtitle: const Text('A conversa continua depois de publicar.'),
          ),
        ],
      ),
    ),
  );
}

class TwitterProfilePage extends StatefulWidget {
  const TwitterProfilePage({
    super.key,
    required this.person,
    required this.accountId,
  });
  final Person person;
  final String accountId;
  @override
  State<TwitterProfilePage> createState() => _TwitterProfilePageState();
}

class _TwitterProfilePageState extends State<TwitterProfilePage> {
  TwitterAccount? _account;
  List<SocialRow> _posts = [];
  bool _loading = true;
  int _tab = 0, _limit = 40, _request = 0, _count = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    TwitterStore.instance.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    TwitterStore.instance.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final request = ++_request;
    try {
      final store = TwitterStore.instance;
      final account = await store.account(widget.person.id, widget.accountId);
      final posts = _tab == 2
          ? await store.likedPosts(widget.person.id, limit: _limit)
          : await store.posts(
              widget.person.id,
              accountId: widget.accountId,
              repliesOnly: _tab == 1,
              limit: _limit,
            );
      final count = await store.postCount(widget.person.id, widget.accountId);
      if (mounted && request == _request) {
        setState(() {
          _account = account;
          _posts = posts;
          _count = count;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = TwitterGenerationService.errorText(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _account;
    return XTheme(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a?.name ?? 'Perfil',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$_count posts',
                style: TextStyle(fontSize: 12, color: xColors(context).muted),
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : a == null
            ? Center(child: Text(_error ?? 'Conta não encontrada.'))
            : RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Container(
                      height: 110,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            xColors(context).headerStart,
                            xColors(context).panel,
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              TwitterAvatar(
                                account: a,
                                version: widget.person.fifaVersion,
                                size: 76,
                              ),
                              const Spacer(),
                              OutlinedButton(
                                onPressed: () async {
                                  if (a.kind == TwitterAccountKind.user) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TwitterAccountForm(
                                          person: widget.person,
                                          account: a,
                                        ),
                                      ),
                                    );
                                    await _reload();
                                  } else {
                                    await TwitterStore.instance.follow(a);
                                  }
                                },
                                child: Text(
                                  a.kind == TwitterAccountKind.user
                                      ? 'Editar perfil'
                                      : a.following
                                      ? 'Seguindo'
                                      : 'Seguir',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            a.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '@${a.handle}',
                            style: TextStyle(color: xColors(context).muted),
                          ),
                          if (a.bio.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(a.bio),
                            ),
                          Text(
                            '${shortSocialCount(a.followers + (a.following ? 1 : 0))} seguidores',
                            style: TextStyle(color: xColors(context).muted),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        for (final (index, name) in [
                          (0, 'Posts'),
                          (1, 'Respostas'),
                          if (a.kind == TwitterAccountKind.user)
                            (2, 'Curtidas'),
                        ])
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _tab = index;
                                  _limit = 40;
                                });
                                _reload();
                              },
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _tab == index
                                            ? xColors(context).text
                                            : xColors(context).muted,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    height: 3,
                                    color: _tab == index
                                        ? xColors(context).accent
                                        : Colors.transparent,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_posts.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Nenhum post por aqui ainda.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: xColors(context).muted),
                        ),
                      ),
                    for (final post in _posts)
                      TwitterPostTile(person: widget.person, row: post),
                    if (_posts.length == _limit)
                      TextButton(
                        onPressed: () {
                          _limit += 40;
                          _reload();
                        },
                        child: const Text('Carregar mais'),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
