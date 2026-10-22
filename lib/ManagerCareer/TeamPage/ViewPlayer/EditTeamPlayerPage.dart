import '../../../utils/AppColors.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../models/Person.dart';
import '../../../models/Season.dart';
import '../../../utils/ManagerStatService.dart';
import '../../../utils/GameCatalog.dart';
import '../../../utils/GamePlayers.dart';
import '../../../utils/SqlService.dart';
import '../../../utils/ThousandsSeparatorInputFormatter.dart';
import '../../../utils/databaseUtils.dart';
import '../../OtherPlayers/OtherPlayersData.dart';
import 'PlayerProfileVisuals.dart';

class EditTeamPlayerPage extends StatefulWidget {
  const EditTeamPlayerPage({
    super.key,
    required this.person,
    required this.row,
    this.realPlayer,
    this.initialSeasonId,
    this.sql,
    this.otherPlayers,
  });
  final Person person;
  final Map<String, Object?> row;
  final GamePlayer? realPlayer;
  final String? initialSeasonId;
  @visibleForTesting
  final SqlService? sql;

  final OtherPlayersRepository? otherPlayers;
  @override
  State<EditTeamPlayerPage> createState() => _EditTeamPlayerPageState();
}

class _EditTeamPlayerPageState extends State<EditTeamPlayerPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _potential = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _initialAge = TextEditingController();
  final _clubOverall = TextEditingController();
  final _clubShirt = TextEditingController();
  final _clubMarket = TextEditingController();
  Map<String, Object?> _clubOriginal = const {};
  bool get _other => widget.otherPlayers != null;
  final _drafts = <String, _SeasonPlayerDraft>{};
  late Future<void> _initialization;
  late GameCatalog _catalog;
  Map<String, Object?> _player = {};
  List<Season> _seasons = [];
  String? _seasonId, _positionId, _nationalityId, _avatar;
  String _foot = 'Right';
  DateTime? _birthdate;
  bool _birthdateChanged = false, _saving = false;
  String get playerId => widget.row['playerId']?.toString() ?? '';
  int get initialYear =>
      getInitialSeasonDefaultDate(widget.person.fifaVersion)?.year ??
      (_seasons.isEmpty ? DateTime.now().year : _seasons.last.startDate.year);
  _SeasonPlayerDraft? get _draft => _drafts[_seasonId];
  String get currency => switch (widget.person.currency?.toUpperCase()) {
    'BRL' => r'R$',
    'USD' => r'$',
    'EUR' || 'EURO' || null => '€',
    final String value => value,
  };

  @override
  void initState() {
    super.initState();
    _initialization = _load();
  }

  Future<void> _load() async {
    final db = widget.sql ?? SqlService.instance;
    final result = await Future.wait<Object?>([
      db.getCustomPlayerById(widget.person.id, playerId),
      db.getPlayerSeasonRows(widget.person.id, playerId),
      db.getSeasons(widget.person.id),
      GameCatalog.load(),
    ]);
    if (!mounted) return;
    final player = result[0] as Map<String, Object?>?;
    if (player == null) {
      throw StateError('Jogador não encontrado nesta carreira.');
    }
    _player = player;
    _catalog = result[3] as GameCatalog;
    _seasons = result[2] as List<Season>;
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    _drafts.clear();
    for (final row in result[1] as List<Map<String, Object?>>) {
      _drafts[row['seasonId'].toString()] = _SeasonPlayerDraft(row);
    }
    final requested =
        widget.initialSeasonId ?? widget.row['seasonId']?.toString();
    _seasonId = _seasons.any((s) => s.id == requested)
        ? requested
        : _seasons.where((s) => _drafts.containsKey(s.id)).firstOrNull?.id ??
              _seasons.firstOrNull?.id;
    _name.text = player['name']?.toString() ?? widget.realPlayer?.name ?? '';
    _potential.text =
        (player['potential'] ?? widget.realPlayer?.potential)?.toString() ?? '';
    _height.text = player['height']?.toString() ?? '';
    _weight.text = player['weight']?.toString() ?? '';
    _positionId =
        player['positionId']?.toString() ?? widget.realPlayer?.mainPositionId;
    _foot = (player['foot'] ?? widget.realPlayer?.foot) == 'Left'
        ? 'Left'
        : 'Right';
    _avatar = player['customAvatarFilePath']?.toString();
    final rawBirthdate = player['birthdate'];
    _birthdate = rawBirthdate is num
        ? DateTime.fromMillisecondsSinceEpoch(rawBirthdate.toInt())
        : DateTime.tryParse(rawBirthdate?.toString() ?? '') ??
              widget.realPlayer?.birthdate;
    final initialDate =
        getInitialSeasonDefaultDate(widget.person.fifaVersion) ??
        _seasons.lastOrNull?.startDate;
    final age =
        player['firstSeasonAge'] ??
        widget.realPlayer?.age ??
        (initialDate == null
            ? null
            : calcPlayerAge(
                fifaVersion: widget.person.fifaVersion,
                seasonStart: initialDate,
                seasonEnd: DateTime(
                  initialDate.year + 1,
                  initialDate.month,
                  initialDate.day - 1,
                ),
                birthdate: _birthdate,
              ));
    _initialAge.text = age?.toString() ?? '';
    _nationalityId = player['nationalityId']?.toString();
    if (_other) {
      final world = await widget.otherPlayers!.worldRow(
        widget.person,
        playerId,
      );
      final market = await db.getPlayerHistory(
        widget.person.id,
        playerId,
        'MarketValue',
      );
      _clubOriginal = {
        'overall': player['overall'],
        'shirtNumber': world?['shirtNumber'],
        'value': market.firstOrNull?['value'],
      };
      _clubOverall.text = player['overall']?.toString() ?? '';
      _clubShirt.text = world?['shirtNumber']?.toString() ?? '';
      _clubMarket.text = ThousandsSeparatorInputFormatter.format(
        market.firstOrNull?['value']?.toString() ?? '',
      );
    }
  }

  Future<void> _saveClub(SqlService db) async {
    final date = (await db.getCareerDate(widget.person.id) ?? DateTime.now())
        .toIso8601String();
    final now = DateTime.now().toIso8601String();
    for (final (table, field, text) in [
      ('Overall', 'overall', _clubOverall.text),
      ('MarketValue', 'value', _clubMarket.text),
    ]) {
      final value = int.tryParse(_digits(text));
      if (value == null || value == _clubOriginal[field]) continue;
      await db.addPlayerHistory(table, {
        'id': const Uuid().v4(),
        'personId': widget.person.id,
        'customPlayerId': playerId,
        'date': date,
        'createdAt': now,
        field: value,
      });
    }
    final shirt = int.tryParse(_digits(_clubShirt.text));
    if (shirt != _clubOriginal['shirtNumber']) {
      await widget.otherPlayers!.setShirtNumber(widget.person, playerId, shirt);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _potential,
      _weight,
      _height,
      _initialAge,
      _clubOverall,
      _clubShirt,
      _clubMarket,
    ]) {
      controller.dispose();
    }
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_positionId == null || _positionId!.isEmpty) {
      _message('Selecione a posição do jogador.');
      return;
    }
    for (final entry in _drafts.entries.where((entry) => entry.value.changed)) {
      final error = entry.value.error;
      if (error != null) {
        final season = _seasons.where((s) => s.id == entry.key).firstOrNull;
        _message('${season?.startDate.year ?? 'Temporada'}: $error');
        setState(() => _seasonId = entry.key);
        return;
      }
    }
    setState(() => _saving = true);
    String? copiedAvatar;
    var saved = false;
    try {
      final previous = _player['customAvatarFilePath']?.toString();
      String? avatarPath = _avatar;
      if (_avatar != null &&
          _avatar != previous &&
          _avatar != CustomImageFiles.absolute(previous)) {
        copiedAvatar = await CustomImageFiles.store(
          _avatar!,
          'faces',
          '${widget.person.id}/$playerId/${const Uuid().v4()}',
        );
        avatarPath = copiedAvatar;
      } else if (_avatar != null) {
        avatarPath = previous;
      }
      final db = widget.sql ?? SqlService.instance;
      await db.updatePlayerConfiguration(
        personId: widget.person.id,
        playerId: playerId,
        general: {
          'name': _name.text.trim(),
          'positionId': _positionId,
          'potential': int.parse(_potential.text),
          'height': int.tryParse(_height.text),
          'weight': int.tryParse(_weight.text),
          'foot': _foot,
          'firstSeasonAge': int.tryParse(_initialAge.text),
          'nationalityId': _nationalityId,
          'customAvatarFilePath': avatarPath,
          if (_birthdateChanged)
            'birthdate': _birthdate?.millisecondsSinceEpoch,
        },
        seasons: [
          if (!_other)
            for (final draft in _drafts.values)
              if (draft.changed) draft.toMap(),
        ],
      );
      if (_other) await _saveClub(db);
      saved = true;
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!saved && copiedAvatar != null) {
        await CustomImageFiles.deleteFile(copiedAvatar);
      }
      if (mounted) _message('Erro ao salvar jogador: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image != null && mounted) setState(() => _avatar = image.path);
    } catch (error) {
      if (mounted) _message('Não foi possível abrir a imagem: $error');
    }
  }

  String _catalogLabel(CatalogItem item, bool nationality) => nationality
      ? 'countries.${item.label}'.tr()
      : 'positions.positionsList.${item.label}'.tr();

  Future<void> _pickCatalog(bool nationality) async {
    var query = '';
    final items = nationality ? _catalog.nationalities : _catalog.positions;
    final selected = await showModalBottomSheet<CatalogItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.of(context).background,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final filtered =
              items
                  .where(
                    (item) => _catalogLabel(
                      item,
                      nationality,
                    ).toLowerCase().contains(query.toLowerCase()),
                  )
                  .toList()
                ..sort(
                  (a, b) => _catalogLabel(
                    a,
                    nationality,
                  ).compareTo(_catalogLabel(b, nationality)),
                );
          final height = (MediaQuery.sizeOf(context).height * .65).clamp(
            0.0,
            (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom -
                    100)
                .clamp(0.0, double.infinity),
          );
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: height,
                child: Column(
                  children: [
                    Text(
                      nationality
                          ? 'Selecionar Nacionalidade'
                          : 'Selecionar Posição',
                      style: const TextStyle(fontSize: 18),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: nationality
                              ? 'Buscar Nacionalidade'
                              : 'Buscar Posição',
                        ),
                        onChanged: (value) =>
                            update(() => query = value.trim()),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          if (nationality)
                            ListTile(
                              title: const Text('Não informado'),
                              onTap: () => Navigator.pop(
                                context,
                                const CatalogItem('', ''),
                              ),
                            ),
                          for (final item in filtered)
                            ListTile(
                              leading: nationality && item.imageUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: item.imageUrl!,
                                      width: 24,
                                      height: 18,
                                      errorWidget: (_, _, _) =>
                                          const SizedBox(width: 24),
                                    )
                                  : null,
                              title: Text(_catalogLabel(item, nationality)),
                              trailing:
                                  (nationality
                                          ? _nationalityId
                                          : _positionId) ==
                                      item.id
                                  ? Icon(
                                      Icons.check,
                                      color: AppColors.of(context).accent,
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, item),
                            ),
                          if (filtered.isEmpty)
                            const ListTile(title: Text('Nenhum resultado.')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (nationality) {
        _nationalityId = selected.id.isEmpty ? null : selected.id;
      } else {
        _positionId = selected.id;
      }
    });
  }

  InputDecoration _decoration(String label, {String? suffix}) =>
      InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(color: AppColors.of(context).muted, fontSize: 12),
        filled: true,
        fillColor: AppColors.of(context).raised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 17,
        ),
        suffixText: suffix,
        suffixStyle: TextStyle(color: AppColors.of(context).line, fontSize: 24),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: AppColors.of(context).line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: AppColors.of(context).line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: AppColors.of(context).accent),
        ),
      );

  Widget _number(
    String label,
    TextEditingController controller, {
    int minimum = 0,
    int? maximum,
    bool required = false,
    bool money = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.next,
    style: TextStyle(color: AppColors.of(context).text, fontSize: 15),
    decoration: _decoration(label, suffix: money ? currency : null),
    inputFormatters: money
        ? [ThousandsSeparatorInputFormatter()]
        : [FilteringTextInputFormatter.digitsOnly],
    validator: (value) => _validateNumber(
      value,
      minimum: minimum,
      maximum: maximum,
      required: required,
    ),
  );

  Widget _catalogField(bool nationality) {
    final id = nationality ? _nationalityId : _positionId;
    final items = nationality ? _catalog.nationalities : _catalog.positions;
    final item = items.where((item) => item.id == id).firstOrNull;
    return InkWell(
      onTap: () => _pickCatalog(nationality),
      borderRadius: BorderRadius.circular(15),
      child: InputDecorator(
        decoration: _decoration(
          nationality ? 'Nacionalidade (opcional)' : 'Posição',
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item == null
                    ? (id ?? 'Não informado')
                    : _catalogLabel(item, nationality),
                style: TextStyle(
                  color: AppColors.of(context).text,
                  fontSize: 15,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 22,
              color: AppColors.of(context).muted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pair(Widget left, Widget right) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: left),
      const SizedBox(width: 10),
      Expanded(child: right),
    ],
  );

  Widget _ageField() {
    if (widget.person.fifaVersion != 'FC24') {
      return _number('Idade inicial ($initialYear)', _initialAge, maximum: 100);
    }
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime(1940),
          lastDate: DateTime(2100),
          initialDate: _birthdate ?? DateTime(2000),
        );
        if (picked != null && mounted) {
          setState(() {
            _birthdate = picked;
            _birthdateChanged = true;
          });
        }
      },
      child: InputDecorator(
        decoration: _decoration('Aniversário'),
        child: Text(
          _birthdate == null
              ? 'Não informado'
              : DateFormat('dd/MM/yyyy').format(_birthdate!),
          style: TextStyle(fontSize: 15, color: AppColors.of(context).text),
        ),
      ),
    );
  }

  Widget _seasonFields() {
    final draft = _draft;
    if (draft == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'O jogador não faz parte do elenco nesta temporada.',
          style: TextStyle(color: AppColors.of(context).muted),
        ),
      );
    }
    return Column(
      key: ValueKey(_seasonId),
      children: [
        _pair(
          _number(
            'Avaliação no início da temporada',
            draft.overall,
            maximum: 99,
            required: true,
          ),
          _number('Número da Camisa (opcional)', draft.shirt, maximum: 999),
        ),
        const SizedBox(height: 16),
        _pair(
          _number('Valor de mercado (opcional)', draft.market, money: true),
          DropdownButtonFormField<String>(
            initialValue: draft.loanStatus ?? '',
            isExpanded: true,
            dropdownColor: AppColors.of(context).panel,
            style: TextStyle(color: AppColors.of(context).text, fontSize: 15),
            decoration: _decoration('Status do empréstimo'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Nenhum')),
              const DropdownMenuItem(
                value: 'inLoan',
                child: Text('Emprestado'),
              ),
              const DropdownMenuItem(
                value: 'outLoan',
                child: Text('Empréstimo'),
              ),
              if (draft.loanStatus != null &&
                  !const ['inLoan', 'outLoan'].contains(draft.loanStatus))
                DropdownMenuItem(
                  value: draft.loanStatus,
                  child: Text(draft.loanStatus!),
                ),
            ],
            onChanged: (value) => setState(
              () => draft.loanStatus = value == null || value.isEmpty
                  ? null
                  : value,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).background,
    appBar: AppBar(
      backgroundColor: AppColors.of(context).background,
      title: const Text('Editar Jogador'),
    ),
    body: SafeArea(
      child: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Não foi possível carregar a configuração do jogador.',
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _initialization = _load()),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return AbsorbPointer(
            absorbing: _saving,
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration('Nome'),
                    style: TextStyle(
                      color: AppColors.of(context).text,
                      fontSize: 15,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Informe o nome.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _catalogField(false),
                  const SizedBox(height: 16),
                  _number('Potencial', _potential, maximum: 99, required: true),
                  const SizedBox(height: 16),
                  _pair(
                    _number('Peso (opcional)', _weight, minimum: 1),
                    _number('Altura (opcional)', _height, minimum: 1),
                  ),
                  const SizedBox(height: 16),
                  _pair(
                    DropdownButtonFormField<String>(
                      initialValue: _foot,
                      isExpanded: true,
                      dropdownColor: AppColors.of(context).panel,
                      decoration: _decoration('Pé'),
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: 15,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Right',
                          child: Text('Direita'),
                        ),
                        DropdownMenuItem(
                          value: 'Left',
                          child: Text('Esquerda'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _foot = value ?? 'Right'),
                    ),
                    _ageField(),
                  ),
                  const SizedBox(height: 16),
                  _catalogField(true),
                  const SizedBox(height: 24),
                  Center(
                    child: InkWell(
                      onTap: _pickImage,
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ProfilePortrait(
                            version: widget.person.fifaVersion,
                            realPlayerId: _player['realPlayerId']?.toString(),
                            customAvatarFilePath: _avatar,
                            width: 72,
                            height: 88,
                          ),
                          Positioned(
                            bottom: 0,
                            right: -14,
                            child: Icon(
                              Icons.camera_alt,
                              size: 21,
                              color: AppColors.of(context).text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Toque para adicionar uma imagem personalizada do jogador. A imagem acima só está associada a um jogador da carreira atual. Pode alterá-la ou apagá-la em qualquer altura. Se o jogador tiver uma fotografia padrão, ao apagar a imagem personalizada, a fotografia padrão será novamente apresentada.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: FilledButton.icon(
                      onPressed: () => setState(() => _avatar = null),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remover imagem'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.of(context).accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  if (_other) ...[
                    Text(
                      'No clube',
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _pair(
                      _number(
                        'Overall atual',
                        _clubOverall,
                        maximum: 99,
                        required: true,
                      ),
                      _number(
                        'Número da Camisa (opcional)',
                        _clubShirt,
                        maximum: 999,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _number(
                      'Valor de mercado (opcional)',
                      _clubMarket,
                      money: true,
                    ),
                  ] else ...[
                    Text(
                      'Dados Específicos da Temporada',
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _seasonId,
                      key: ValueKey('season:$_seasonId'),
                      isExpanded: true,
                      dropdownColor: AppColors.of(context).panel,
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontSize: 15,
                      ),
                      decoration: _decoration('Temporada'),
                      items: [
                        for (final season in _seasons)
                          DropdownMenuItem(
                            value: season.id,
                            child: Text(
                              '${season.startDate.year} - ${season.endDate.year}',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        FocusScope.of(context).unfocus();
                        setState(() => _seasonId = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    _seasonFields(),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.of(context).accent,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    child: Text(_saving ? 'Salvando...' : 'Salvar'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

String _digits(String text) => text.replaceAll(RegExp(r'\D'), '');

String? _validateNumber(
  String? text, {
  int minimum = 0,
  int? maximum,
  bool required = false,
}) {
  final digits = _digits(text ?? '');
  if (digits.isEmpty) return required ? 'Informe um valor.' : null;
  final number = int.tryParse(digits);
  if (number == null) return 'Número inválido.';
  if (number < minimum || (maximum != null && number > maximum)) {
    return maximum == null ? 'Mínimo: $minimum.' : 'Use $minimum a $maximum.';
  }
  return null;
}

class _SeasonPlayerDraft {
  _SeasonPlayerDraft(this.original)
    : overall = TextEditingController(
        text: original['overall']?.toString() ?? '',
      ),
      shirt = TextEditingController(
        text: original['shirtNumber']?.toString() ?? '',
      ),
      market = TextEditingController(
        text: ThousandsSeparatorInputFormatter.format(
          original['marketValue']?.toString() ?? '',
        ),
      ),
      loanStatus = original['loanStatus']?.toString();
  final Map<String, Object?> original;
  final TextEditingController overall, shirt, market;
  String? loanStatus;
  Map<String, Object?> toMap() => {
    'id': original['id'],
    'seasonId': original['seasonId'],
    'overall': int.tryParse(_digits(overall.text)),
    'shirtNumber': int.tryParse(_digits(shirt.text)),
    'marketValue': int.tryParse(_digits(market.text)),
    'loanStatus': loanStatus,
  };
  bool get changed =>
      toMap().entries.any((entry) => original[entry.key] != entry.value);
  String? get error =>
      _validateNumber(overall.text, maximum: 99, required: true) ??
      _validateNumber(shirt.text, maximum: 999) ??
      _validateNumber(market.text);
  void dispose() {
    overall.dispose();
    shirt.dispose();
    market.dispose();
  }
}
