import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/Person.dart';
import '../RootPage/DrawerWidget.dart';
import '../utils/Components/CareerPageWidgets.dart';
import 'FcScoreApi.dart';
import 'FcScoreModels.dart';
import 'FcScoreRepository.dart';
import 'FcScoreMappingPage.dart';
import 'FcScoreHubPage.dart';
import 'FcScoreWidgets.dart';

class FcScoreConnectionPage extends StatefulWidget {
  const FcScoreConnectionPage({
    super.key,
    this.initialPerson,
    this.repository,
    this.apiFactory,
  });
  final Person? initialPerson;
  final FcScoreRepository? repository;
  final FcScoreApi Function(Uri)? apiFactory;
  @override
  State<FcScoreConnectionPage> createState() => _FcScoreConnectionPageState();
}

class _FcScoreConnectionPageState extends State<FcScoreConnectionPage> {
  late final _repo = widget.repository ?? FcScoreRepository();
  final _ip = TextEditingController(),
      _port = TextEditingController(text: '38291');
  List<String> _recent = [];
  List<FcJson>? _careers;
  FcScoreApi? _api;
  String? _error;
  String _version = '';
  bool _usb = false, _busy = false;
  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final recent = await _repo.recentAddresses();
    if (mounted) setState(() => _recent = recent);
  }

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _api?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    FcScoreApi? pending;
    try {
      final port = int.tryParse(_port.text.trim());
      if (port == null) {
        throw const FcScoreException('Informe uma porta válida.');
      }
      final address = fcScoreAddress(_usb ? '127.0.0.1' : _ip.text, port: port);
      pending = widget.apiFactory?.call(address) ?? FcScoreApi(address);
      final meta = await pending.connect();
      final careers = await pending.list('careers');
      await _repo.rememberAddress(address);
      if (!mounted) {
        pending.close();
        return;
      }
      _api?.close();
      setState(() {
        _api = pending;
        _version = fcId(meta['gameVersion']);
        _careers = careers;
      });
      await _loadRecent();
    } catch (error) {
      pending?.close();
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCareer(FcJson save) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final remote = await FcScoreRemoteCareer.load(
        _api!,
        fcId(save['id']),
        _version,
      );
      final saved = await _repo.linkedCareerFor(
        remote,
        person: widget.initialPerson,
      );
      FcBoundCareer? selection;
      final existing = saved == null
          ? null
          : await _repo.moveLink(
              saved,
              remote.saveId,
              saveName: remote.saveName,
            );
      if (existing != null &&
          existing.remoteClubId == fcId(remote.club['id'])) {
        final persons = await _repo.sql.getPersons();
        final person = persons
            .where((p) => p.id == existing.personId)
            .firstOrNull;
        if (person != null) selection = FcBoundCareer(person, existing);
      }
      if (!mounted) return;
      selection ??= await Navigator.push<FcBoundCareer>(
        context,
        MaterialPageRoute(
          builder: (_) => FcScoreMappingPage(
            remote: remote,
            repository: _repo,
            initialPerson: widget.initialPerson,
          ),
        ),
      );
      if (!mounted || selection == null) return;
      final chosen = selection;
      final connectedLink = await _repo.rememberCareerAddress(
        chosen.link,
        _api!.address,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => FcScoreHubPage(
            api: _api!,
            repository: _repo,
            remote: remote,
            person: chosen.person,
            link: connectedLink,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _disconnect() {
    _api?.close();
    _api = null;
    setState(() {
      _careers = null;
      _error = null;
      _ip.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: RootDrawerScope.leading(context),
      title: const Text('FC Score'),
      actions: [
        if (_careers != null)
          IconButton(
            tooltip: 'Desconectar',
            onPressed: _busy ? null : _disconnect,
            icon: const Icon(Icons.link_off),
          ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CareerPageHeader(
            title: _careers == null ? 'Conecte seu PC' : 'Escolha o save',
            subtitle: _careers == null
                ? 'Consulte a carreira do jogo e importe partidas para o aplicativo.'
                : '$_version · ${_api!.address.host}:${_api!.address.port}',
            icon: Icons.connected_tv_rounded,
            eyebrow: 'FC Score API',
          ),
          if (_careers == null) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ChoiceChip(
                  label: const Text('Mesma rede'),
                  selected: !_usb,
                  avatar: const Icon(Icons.wifi, size: 18),
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _usb = false),
                ),
                ChoiceChip(
                  label: const Text('Cabo USB'),
                  selected: _usb,
                  avatar: const Icon(Icons.usb, size: 18),
                  onSelected: _busy ? null : (_) => setState(() => _usb = true),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FcPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_usb) ...[
                    const FcNotice(
                      'Abra a API no PC. Conecte os dois aparelhos à mesma rede e informe o IP mostrado no computador.',
                    ),
                    TextField(
                      key: const Key('fc-ip'),
                      controller: _ip,
                      enabled: !_busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: fcInput(
                        'IP do computador',
                        hint: '192.168.0.20',
                        icon: Icons.computer,
                      ),
                      onSubmitted: (_) => _connect(),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    const FcNotice(
                      'No Android, ative as opções do desenvolvedor e a depuração USB. Conecte o cabo e autorize o PC. Com o ADB instalado, execute no PC:',
                    ),
                    SelectableText(
                      'adb reverse tcp:${_port.text} tcp:${_port.text}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(
                          text:
                              'adb reverse tcp:${_port.text} tcp:${_port.text}',
                        ),
                      ),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar comando'),
                    ),
                    const FcNotice(
                      'Abra a API no PC e toque em conectar. Repita o comando ao reconectar o cabo. O app acessará 127.0.0.1.',
                    ),
                  ],
                  TextField(
                    key: const Key('fc-port'),
                    controller: _port,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    onChanged: _usb ? (_) => setState(() {}) : null,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: fcInput('Porta', icon: Icons.settings_ethernet),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('fc-connect'),
                      onPressed: _busy ? null : _connect,
                      icon: const Icon(Icons.link),
                      label: Text(_busy ? 'Conectando…' : 'Conectar'),
                    ),
                  ),
                ],
              ),
            ),
            if (!_usb && _recent.isNotEmpty) ...[
              const FcSection(
                'Conexões recentes',
                subtitle: 'Toque para preencher o endereço e depois conecte.',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final address in _recent)
                    ActionChip(
                      label: Text(
                        '${Uri.parse(address).host}:${Uri.parse(address).port}',
                      ),
                      onPressed: _busy
                          ? null
                          : () {
                              final uri = Uri.parse(address);
                              _ip.text =
                                  '${uri.scheme}://${uri.host.contains(':') ? '[${uri.host}]' : uri.host}';
                              _port.text = '${uri.port}';
                            },
                    ),
                ],
              ),
            ],
          ] else ...[
            if (_careers!.isEmpty)
              const FcNotice(
                'Nenhum save encontrado. Confira a pasta de saves configurada na API.',
              ),
            for (final save in _careers!)
              FcChoice(
                title: save['careerType'] == 'player'
                    ? 'Carreira de jogador'
                    : 'Carreira de técnico',
                value: fcName(save['inGameName'], fcId(save['id'])),
                icon: Icons.sports_soccer,
                onTap: _busy ? null : () => _openCareer(save),
              ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null) FcNotice(_error!, error: true),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}
