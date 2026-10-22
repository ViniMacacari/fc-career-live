import 'package:flutter/material.dart';

import '../models/Person.dart';
import 'FcScoreApi.dart';
import 'FcScoreConnectionPage.dart';
import 'FcScoreModels.dart';
import 'FcScoreRepository.dart';
import 'FcScoreSyncProgress.dart';
import 'FcScoreWorldImportPage.dart';
import 'FcScoreUpdateOptions.dart';

class FcScoreCareerUpdateButton extends StatefulWidget {
  const FcScoreCareerUpdateButton({
    super.key,
    required this.person,
    required this.onUpdated,
    this.repository,
    this.apiFactory,
    this.refreshToken,
  });
  final Person person;
  final Future<void> Function() onUpdated;
  final FcScoreRepository? repository;
  final FcScoreApi Function(Uri)? apiFactory;
  final Object? refreshToken;
  @override
  State<FcScoreCareerUpdateButton> createState() =>
      _FcScoreCareerUpdateButtonState();
}

class _FcScoreCareerUpdateButtonState extends State<FcScoreCareerUpdateButton> {
  late final _repo = widget.repository ?? FcScoreRepository();
  late Future<FcScoreLink?> _link = _repo.linkFor(widget.person.id);
  bool _busy = false;
  @override
  void didUpdateWidget(FcScoreCareerUpdateButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.person.id != widget.person.id ||
        oldWidget.refreshToken != widget.refreshToken) {
      _link = _repo.linkFor(widget.person.id);
    }
  }

  Future<void> _update() async {
    setState(() => _busy = true);
    try {
      final link = await _repo.linkFor(widget.person.id);
      if (!mounted || link == null) return;
      final previous = link.worldSync.values.toList()
        ..sort((a, b) => (b.importedAt ?? '').compareTo(a.importedAt ?? ''));
      final options = await showDialog<FcScoreUpdateOptions>(
        context: context,
        builder: (_) => FcScoreUpdateOptionsDialog(
          initial:
              link.updateOptions ??
              FcScoreUpdateOptions(
                ownSquad: previous.firstOrNull?.bringOwnSquad ?? false,
                overalls: previous.firstOrNull?.updateOveralls ?? true,
              ),
        ),
      );
      if (!mounted || options == null) return;
      await _repo.rememberUpdateOptions(widget.person.id, options);
      if (!mounted) return;
      await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => FcScoreCareerUpdateDialog(
          person: widget.person,
          repository: _repo,
          apiFactory: widget.apiFactory,
          options: options,
        ),
      );
      if (mounted) await widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _link = _repo.linkFor(widget.person.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FcScoreLink?>(
    future: _link,
    builder: (context, snapshot) => snapshot.hasData
        ? IconButton(
            key: const Key('fc-career-update'),
            tooltip: 'Atualizar carreira pelo FC Score',
            onPressed: _busy ? null : _update,
            icon: const Icon(Icons.sync_rounded),
          )
        : const SizedBox.shrink(),
  );
}

class FcScoreCareerUpdateDialog extends StatefulWidget {
  const FcScoreCareerUpdateDialog({
    super.key,
    required this.person,
    required this.repository,
    this.apiFactory,
    this.options,
  });
  final Person person;
  final FcScoreRepository repository;
  final FcScoreApi Function(Uri)? apiFactory;
  final FcScoreUpdateOptions? options;
  @override
  State<FcScoreCareerUpdateDialog> createState() =>
      _FcScoreCareerUpdateDialogState();
}

class _FcScoreCareerUpdateDialogState extends State<FcScoreCareerUpdateDialog> {
  final _progress = FcScoreSyncProgress();
  FcScoreApi? _api;
  FcScoreLink? _link;
  FcScoreRemoteCareer? _remote;
  String? _error;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _api?.close();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      final repo = widget.repository;
      final link = await repo.linkFor(widget.person.id);
      if (!mounted) return;
      if (link == null) {
        throw const FcScoreException(
          'Conecte esta carreira ao FC Score primeiro.',
        );
      }
      final address =
          link.connectionAddress ?? (await repo.recentAddresses()).firstOrNull;
      if (!mounted) return;
      if (address == null) {
        throw const FcScoreException(
          'Escolha o endereço do PC para atualizar esta carreira.',
        );
      }
      final uri = fcScoreAddress(address);
      _api = widget.apiFactory?.call(uri) ?? FcScoreApi(uri);
      final meta = await _api!.connect();
      if (!mounted) return;
      _progress.advance(.08, 'Localizando o save da carreira');
      if (fcVersion(fcId(meta['gameVersion'])) != link.gameVersion) {
        throw const FcScoreException(
          'O PC está conectado a outra versão do jogo. Confira a conexão.',
        );
      }
      final save = repo.currentSave(
        await _api!.list('careers'),
        link,
        widget.person,
      );
      if (save == null) {
        throw const FcScoreException(
          'O save vinculado não foi encontrado. Selecione a carreira na conexão.',
        );
      }
      final remote = await FcScoreRemoteCareer.load(
        _api!,
        fcId(save['id']),
        link.gameVersion,
      );
      if (!mounted) return;
      if (!link.belongsTo(remote, widget.person)) {
        throw const FcScoreException(
          'Este save pertence a outro clube ou tipo de carreira. Revise a conexão.',
        );
      }
      final moved = await repo.moveLink(
        link,
        remote.saveId,
        saveName: remote.saveName,
      );
      final connected = await repo.rememberCareerAddress(moved, uri);
      if (!mounted) return;
      _progress.advance(.15, 'Conferindo o calendário');
      setState(() {
        _link = connected;
        _remote = remote;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _customize() {
    final api = _api!, remote = _remote!, link = _link!;
    final navigator = Navigator.of(context);
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (_) => FcScoreWorldImportPage(
              api: api,
              remote: remote,
              repository: widget.repository,
              person: widget.person,
              link: link,
              personalize: true,
            ),
          ),
        )
        .then((_) {
          if (mounted) navigator.pop('updated');
        });
  }

  void _reconnect() {
    final navigator = Navigator.of(context);
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (_) => FcScoreConnectionPage(initialPerson: widget.person),
          ),
        )
        .then((_) {
          if (mounted) navigator.pop('updated');
        });
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: _remote == null
        ? FcScoreSyncProgressView(
            progress: _progress,
            error: _error,
            onClose: () => Navigator.pop(context),
            onReconnect: _error == null ? null : _reconnect,
          )
        : FcScoreWorldImportPage(
            api: _api!,
            remote: _remote!,
            repository: widget.repository,
            person: widget.person,
            link: _link!,
            automatic: true,
            syncProgress: _progress,
            onCustomize: _customize,
            updateOptions: widget.options,
          ),
  );
}

class FcScoreUpdateOptionsDialog extends StatefulWidget {
  const FcScoreUpdateOptionsDialog({super.key, required this.initial});
  final FcScoreUpdateOptions initial;
  @override
  State<FcScoreUpdateOptionsDialog> createState() =>
      _FcScoreUpdateOptionsDialogState();
}

class _FcScoreUpdateOptionsDialogState
    extends State<FcScoreUpdateOptionsDialog> {
  late bool _competitions = widget.initial.competitions;
  late bool _calendar = widget.initial.calendar;
  late bool _squads = widget.initial.squads;
  late bool _ownSquad = widget.initial.ownSquad;
  late bool _overalls = widget.initial.overalls;
  FcScoreUpdateOptions get options => FcScoreUpdateOptions(
    competitions: _competitions,
    calendar: _calendar,
    squads: _squads,
    ownSquad: _ownSquad,
    overalls: _overalls,
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: const Text('Atualizar carreira'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escolha o que puxar da API. Vamos lembrar sua seleção nesta carreira.',
            ),
            const SizedBox(height: 12),
            _choice(
              'competitions',
              'Classificação e artilharia',
              _competitions,
              (v) => _competitions = v,
            ),
            _choice(
              'calendar',
              'Calendário das competições',
              _calendar,
              (v) => _calendar = v,
            ),
            _choice(
              'squads',
              'Elencos dos outros clubes',
              _squads,
              (v) => _squads = v,
            ),
            _choice(
              'own-squad',
              'Completar meu elenco',
              _ownSquad,
              (v) => _ownSquad = v,
              subtitle: 'Adicionar os jogadores que faltam.',
            ),
            _choice(
              'overalls',
              'Atualizar overall',
              _overalls,
              (v) => _overalls = v,
              enabled: _squads || _ownSquad,
            ),
            const SizedBox(height: 12),
            Text(
              'Novas partidas não serão adicionadas à aba Partidas. Para importar jogos, use Personalizar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('fc-update-options-confirm'),
        onPressed: options.hasSelection
            ? () => Navigator.pop(context, options)
            : null,
        child: const Text('Atualizar'),
      ),
    ],
  );
  Widget _choice(
    String key,
    String title,
    bool value,
    void Function(bool) change, {
    bool enabled = true,
    String? subtitle,
  }) => CheckboxListTile(
    key: ValueKey('fc-update-option-$key'),
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    value: value,
    onChanged: enabled ? (v) => setState(() => change(v!)) : null,
  );
}
