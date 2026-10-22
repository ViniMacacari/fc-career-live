import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/Person.dart';
import '../Settings/AISettingsPage.dart';
import '../utils/databaseUtils.dart';
import 'TwitterGenerationService.dart';
import 'TwitterModels.dart';
import 'TwitterStore.dart';
import 'TwitterStyle.dart';

class TwitterSettingsPage extends StatefulWidget {
  const TwitterSettingsPage({super.key, required this.person});
  final Person person;
  @override
  State<TwitterSettingsPage> createState() => _TwitterSettingsPageState();
}

class _TwitterSettingsPageState extends State<TwitterSettingsPage> {
  bool _opponentPost = false;
  late final _ready = _load();
  bool _enabled = true,
      _profanity = true,
      _saving = false,
      _initialReplies = true,
      _transfers = true,
      _createPages = true;
  String _trigger = 'everyMatch';
  String? _usage;
  final _posts = TextEditingController(), _interval = TextEditingController();
  final _pages = TextEditingController(),
      _journals = TextEditingController(),
      _rivals = TextEditingController();
  Future<void> _load() async {
    await CustomImageFiles.docsDir();
    await TwitterStore.instance.initialize(widget.person);
    final p = await TwitterStore.instance.preferences(widget.person.id);
    _enabled = p.enabled;
    _profanity = p.allowProfanity;
    _trigger = p.triggerMode;
    _posts.text = '${p.postCount}';
    _pages.text = '${p.pagePosts}';
    _journals.text = '${p.journalPosts}';
    _rivals.text = '${p.rivalPosts}';
    _initialReplies = p.replyCount > 0;
    _transfers = p.generateTransfers;
    _opponentPost = p.generateOpponentPost;
    _createPages = p.createPages;
    _interval.text = '${p.matchInterval}';
    final last = (await TwitterGenerationService.instance.jobs(
      widget.person.id,
    )).where((j) => j['status'] == 'done').firstOrNull;
    if (last != null) {
      _usage =
          'Última geração: ${last['promptTokens'] ?? 0} tokens de entrada + ${last['completionTokens'] ?? 0} de saída.';
    }
  }

  @override
  void dispose() {
    _posts.dispose();
    _interval.dispose();
    _pages.dispose();
    _journals.dispose();
    _rivals.dispose();
    super.dispose();
  }

  int? get _fans {
    final posts = int.tryParse(_posts.text);
    final others = [
      _pages,
      _journals,
      _rivals,
    ].map((c) => int.tryParse(c.text.isEmpty ? '0' : c.text));
    if (posts == null || others.any((n) => n == null || n < 0)) return null;
    return posts - others.fold<int>(0, (total, n) => total + n!);
  }

  Future<void> _save() async {
    final posts = int.tryParse(_posts.text),
        interval = int.tryParse(_interval.text);
    final fans = _fans;
    if (fans == null || fans < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Páginas, jornais e rivais somados não podem passar dos posts por geração.',
          ),
        ),
      );
      return;
    }
    if (posts == null ||
        posts < 1 ||
        posts > TwitterPreferences.maxPosts ||
        interval == null ||
        interval < 1 ||
        interval > 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use 1–100 posts e um intervalo de 1–30 partidas.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await TwitterStore.instance.savePreferences(
        widget.person.id,
        TwitterPreferences(
          enabled: _enabled,
          triggerMode: _trigger,
          matchInterval: interval,
          postCount: posts,
          replyCount: _initialReplies ? 2 : 0,
          allowProfanity: _profanity,
          generateTransfers: _transfers,
          generateOpponentPost: _opponentPost,
          pagePosts: int.tryParse(_pages.text) ?? 0,
          journalPosts: int.tryParse(_journals.text) ?? 0,
          rivalPosts: int.tryParse(_rivals.text) ?? 0,
          createPages: _createPages,
        ),
      );
      unawaited(TwitterGenerationService.instance.runPending(widget.person));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('X configurado.')));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao salvar configuração.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => XTheme(
    builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('Configurações do X')),
      body: FutureBuilder<void>(
        future: _ready,
        builder: (_, s) {
          if (s.hasError) {
            return Center(
              child: Text(TwitterGenerationService.errorText(s.error!)),
            );
          }
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Geração de posts',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Geração automática por IA'),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              Text(
                'A IA escreve o post oficial do clube, os posts de outras contas e as respostas. Os textos ficam salvos na carreira.',
                style: TextStyle(color: xColors(context).muted),
              ),
              if (_usage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _usage!,
                    style: TextStyle(
                      fontSize: 12,
                      color: xColors(context).muted,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _trigger,
                decoration: const InputDecoration(
                  labelText: 'Quando gerar posts',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'everyMatch',
                    child: Text('Após cada partida'),
                  ),
                  DropdownMenuItem(
                    value: 'everyNMatches',
                    child: Text('A cada N partidas'),
                  ),
                  DropdownMenuItem(
                    value: 'manual',
                    child: Text('Somente quando eu pedir'),
                  ),
                ],
                onChanged: (v) => setState(() => _trigger = v!),
              ),
              if (_trigger == 'everyNMatches') ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Intervalo em partidas (1–30)',
                  ),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _transfers,
                onChanged: (value) => setState(() => _transfers = value),
                title: const Text('Posts sobre transferências'),
                subtitle: const Text(
                  'Anúncio do clube e reações ao registrar uma negociação. No modo manual, escolha a transferência pelo botão de geração.',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _posts,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Posts por geração (1–100)',
                  helperText: 'Além do post oficial do clube.',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final (controller, label) in [
                    (_pages, 'Páginas'),
                    (_journals, 'Jornais'),
                    (_rivals, 'Rivais'),
                  ]) ...[
                    Expanded(
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(labelText: label),
                      ),
                    ),
                    if (label != 'Rivais') const SizedBox(width: 12),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  switch (_fans) {
                    null => 'Use números inteiros.',
                    < 0 => 'A soma passa dos posts por geração.',
                    final fans =>
                      'Torcedores do clube: $fans. Puxar o feed gera só torcedores e páginas. Jornais nunca respondem posts.',
                  },
                  style: TextStyle(
                    fontSize: 12,
                    color: (_fans ?? -1) < 0
                        ? Colors.redAccent
                        : xColors(context).muted,
                  ),
                ),
              ),
              SwitchListTile(
                key: const ValueKey('x-opponent-post-setting'),
                contentPadding: EdgeInsets.zero,
                value: _opponentPost,
                onChanged: (value) => setState(() => _opponentPost = value),
                title: const Text('Post oficial do adversário'),
                subtitle: const Text(
                  'Uma publicação por partida, na perspectiva do outro clube e de acordo com o resultado.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _createPages,
                onChanged: (value) => setState(() => _createPages = value),
                title: const Text('IA cria novas páginas e jornais'),
                subtitle: const Text(
                  'Desligado, a IA usa só as páginas e jornais que já existem. Torcedores e rivais novos continuam aparecendo.',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _initialReplies,
                onChanged: (value) => setState(() => _initialReplies = value),
                title: const Text('Gerar duas respostas iniciais'),
                subtitle: const Text(
                  'A repercussão define o limite de respostas. A conversa mostra todas as respostas já publicadas; carregar mais gera até cinco novas por vez. O post oficial recebe as duas iniciais.',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _profanity,
                title: const Text('Linguagem de arquibancada'),
                subtitle: const Text(
                  'Permitir palavrões e críticas de torcedores às atuações.',
                ),
                onChanged: (v) => setState(() => _profanity = v),
              ),
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.people_outline),
                title: const Text('Contas (opcional)'),
                subtitle: const Text(
                  'A IA também cria jornais, páginas e torcedores',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TwitterAccountsPage(person: widget.person),
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Inteligência artificial'),
                subtitle: const Text(
                  'Chave, modelo, idioma e limite de tokens',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AISettingsPage()),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Salvando...' : 'Salvar configurações'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class TwitterAccountsPage extends StatefulWidget {
  const TwitterAccountsPage({super.key, required this.person});
  final Person person;
  @override
  State<TwitterAccountsPage> createState() => _TwitterAccountsPageState();
}

class _TwitterAccountsPageState extends State<TwitterAccountsPage> {
  late Future<List<TwitterAccount>> _accounts = TwitterStore.instance.accounts(
    widget.person.id,
  );
  Future<void> _edit({
    TwitterAccount? account,
    TwitterAccountKind? kind,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TwitterAccountForm(
          person: widget.person,
          account: account,
          kind: kind,
        ),
      ),
    );
    if (mounted) {
      setState(
        () => _accounts = TwitterStore.instance.accounts(widget.person.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) => XTheme(
    builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('Contas do X')),
      body: FutureBuilder<List<TwitterAccount>>(
        future: _accounts,
        builder: (_, s) {
          if (s.hasError) {
            return Center(
              child: Text(TwitterGenerationService.errorText(s.error!)),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Não é necessário cadastrar contas: a IA cria nomes e @ durante as conversas e reutiliza os perfis existentes. Os clubes vêm automaticamente dos dados da carreira. Você pode cadastrar ou ajustar contas aqui; desativar preserva os posts anteriores.',
                  style: TextStyle(color: xColors(context).muted),
                ),
              ),
              for (final kind in TwitterAccountKind.values.where(
                (kind) => kind != TwitterAccountKind.club,
              )) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          kind.label,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (kind != TwitterAccountKind.club &&
                          kind != TwitterAccountKind.user)
                        IconButton(
                          onPressed: () => _edit(kind: kind),
                          icon: const Icon(Icons.add),
                          tooltip: 'Adicionar conta',
                        ),
                    ],
                  ),
                ),
                for (final a in s.data!.where(
                  (a) => a.kind == kind && !TwitterStore.isLegacyExample(a),
                ))
                  ListTile(
                    leading: TwitterAvatar(
                      account: a,
                      version: widget.person.fifaVersion,
                    ),
                    title: Text(a.name),
                    subtitle: Text(
                      '@${a.handle} • ${a.enabled ? 'Ativa' : 'Desativada'}\n'
                      '${a.averageLikes == null ? 'Likes aleatórios' : 'Média: ${a.averageLikes} likes'}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _edit(account: a),
                  ),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class TwitterAccountForm extends StatefulWidget {
  const TwitterAccountForm({
    super.key,
    required this.person,
    this.account,
    this.kind,
  });
  final Person person;
  final TwitterAccount? account;
  final TwitterAccountKind? kind;
  @override
  State<TwitterAccountForm> createState() => _TwitterAccountFormState();
}

class _TwitterAccountFormState extends State<TwitterAccountForm> {
  late final _id = widget.account?.id ?? const Uuid().v4();
  late final _name = TextEditingController(text: widget.account?.name);
  late final _handle = TextEditingController(text: widget.account?.handle);
  late final _bio = TextEditingController(text: widget.account?.bio);
  late final _likes = TextEditingController(
    text: widget.account?.averageLikes?.toString(),
  );
  late TwitterAccountKind _kind =
      widget.account?.kind ?? widget.kind ?? TwitterAccountKind.fan;
  late bool _enabled = widget.account?.enabled ?? true;
  late String? _avatar = widget.account?.avatarPath;
  bool _saving = false;
  @override
  void dispose() {
    for (final c in [_name, _handle, _bio, _likes]) {
      c.dispose();
    }
    super.dispose();
  }

  TwitterAccount _value({String? avatar}) => TwitterAccount(
    id: _id,
    personId: widget.person.id,
    name: _name.text.trim(),
    handle: normalizeTwitterHandle(
      _handle.text,
      club: _kind == TwitterAccountKind.club,
    ),
    kind: _kind,
    bio: _bio.text.trim(),
    avatarPath: avatar ?? _avatar,
    teamId: widget.account?.teamId,
    leagueId: widget.account?.leagueId,
    supportedTeamId: widget.account?.supportedTeamId,
    averageLikes: int.tryParse(_likes.text),
    followers: widget.account?.followers ?? 250,
    following: widget.account?.following ?? false,
    enabled:
        _kind == TwitterAccountKind.club ||
        _kind == TwitterAccountKind.user ||
        _enabled,
  );
  Future<void> _save() async {
    final avg = int.tryParse(_likes.text);
    final handle = _value().handle;
    if (_name.text.trim().isEmpty ||
        handle.isEmpty ||
        (_likes.text.trim().isNotEmpty &&
            (avg == null || avg < 0 || avg > 1000000000))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confira nome, @ e média de likes.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final duplicate = (await TwitterStore.instance.accounts(widget.person.id))
          .any(
            (a) =>
                a.id != _id && a.handle.toLowerCase() == handle.toLowerCase(),
          );
      if (duplicate) {
        throw const FormatException('Este @ já pertence a outra conta.');
      }
      _avatar = await CustomImageFiles.resolveForSave(
        previous: widget.account?.avatarPath,
        selected: _avatar,
        folder: 'twitter_faces',
        id: _id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_'),
      );
      await TwitterStore.instance.saveAccount(_value());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TwitterGenerationService.errorText(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => XTheme(
    builder: (context) => Scaffold(
      appBar: AppBar(
        title: Text(
          widget.account == null ? 'Adicionar conta' : 'Editar conta',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: InkWell(
              onTap: () async {
                final image = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 600,
                  imageQuality: 85,
                );
                if (mounted && image != null) {
                  setState(() => _avatar = image.path);
                }
              },
              child: Stack(
                children: [
                  TwitterAvatar(
                    account: _value(),
                    version: widget.person.fifaVersion,
                    size: 84,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Icon(
                      Icons.add_a_photo,
                      color: xColors(context).accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_avatar != null)
            TextButton(
              onPressed: () => setState(() => _avatar = null),
              child: const Text('Remover foto'),
            ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _handle,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '@usuário',
              prefixText: '@',
              helperText: 'Letras sem acentos, números e _ • até 15 caracteres',
            ),
          ),
          const SizedBox(height: 20),
          if (_kind != TwitterAccountKind.club &&
              _kind != TwitterAccountKind.user) ...[
            DropdownButtonFormField<TwitterAccountKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Grupo'),
              items: TwitterAccountKind.values
                  .take(4)
                  .map((k) => DropdownMenuItem(value: k, child: Text(k.label)))
                  .toList(),
              onChanged: (v) => setState(() => _kind = v!),
            ),
            const SizedBox(height: 20),
          ],
          TextField(
            controller: _bio,
            maxLength: 180,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Bio / personalidade'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _likes,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Média de likes por post (opcional)',
              helperText:
                  'Vazio: aleatório. A repercussão da partida altera os likes.',
            ),
          ),
          if (_kind != TwitterAccountKind.club &&
              _kind != TwitterAccountKind.user)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ativa nas gerações'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Salvando...' : 'Salvar conta'),
          ),
        ],
      ),
    ),
  );
}
