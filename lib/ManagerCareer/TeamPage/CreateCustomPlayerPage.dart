import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/Components/CareerUiStyle.dart';
import '../../utils/Components/ManagerFormStyle.dart';
import '../../utils/GameCatalog.dart';
import '../../utils/SqlService.dart';
import '../../utils/databaseUtils.dart';
import 'CustomPlayerPreview.dart';

class CreateCustomPlayerPage extends StatefulWidget {
  const CreateCustomPlayerPage({
    super.key,
    this.person,
    this.season,
    this.template,
    this.service,
    this.addToRoster = true,
    this.onCreated,
  }) : assert(!addToRoster || (person != null && season != null));
  final Person? person;
  final Season? season;
  final Map<String, Object?>? template;
  final SqlService? service;
  final bool addToRoster;
  final ValueChanged<Map<String, Object?>>? onCreated;

  @override
  State<CreateCustomPlayerPage> createState() => _CreateCustomPlayerPageState();
}

class _CreateCustomPlayerPageState extends State<CreateCustomPlayerPage>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _name = TextEditingController();
  final _overall = TextEditingController();
  final _potential = TextEditingController();
  final _shirt = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _positionLabel = TextEditingController();
  final _nationalityLabel = TextEditingController();
  final _birthdayLabel = TextEditingController();
  late final AnimationController _tabAnimation;
  late Future<({GameCatalog catalog, int starters})> _initialization;
  String? _positionId, _nationalityId, _avatar;
  String _foot = 'Right';
  bool _bench = false, _saving = false, _showErrors = false;
  DateTime? _birthdate;
  int _tab = 0;
  int get _lastTab => widget.addToRoster ? 2 : 1;
  bool get _shared => widget.person == null;
  bool get _editing => widget.template != null;
  SqlService get _sql => widget.service ?? SqlService.instance;
  DateTime get _referenceDate => widget.season?.startDate ?? DateTime.now();
  String get _fifaVersion =>
      widget.person?.fifaVersion ?? GameCatalog.fifaVersions.last;

  List<TextEditingController> get _controllers => [
    _name,
    _overall,
    _potential,
    _shirt,
    _height,
    _weight,
    _positionLabel,
    _nationalityLabel,
    _birthdayLabel,
  ];

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    if (template != null) {
      _name.text = template['name']?.toString() ?? '';
      for (final (controller, key) in [
        (_overall, 'overall'),
        (_potential, 'potential'),
        (_height, 'height'),
        (_weight, 'weight'),
      ]) {
        controller.text = template[key]?.toString() ?? '';
      }
      _positionId = template['positionId'] as String?;
      _nationalityId = template['nationalityId'] as String?;
      _avatar = template['customAvatarFilePath'] as String?;
      _foot = template['foot'] as String? ?? 'Right';
      if (template['birthdate'] case final num value) {
        _birthdate = DateTime.fromMillisecondsSinceEpoch(value.toInt());
        _birthdayLabel.text = DateFormat('dd/MM/yyyy').format(_birthdate!);
      }
    }
    _tabAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1,
    );
    for (final controller in _controllers) {
      controller.addListener(_updatePreview);
    }
    _initialization = _load();
  }

  Future<({GameCatalog catalog, int starters})> _load() async {
    if (!widget.addToRoster) {
      final catalog = await GameCatalog.load();
      final position = catalog.positions
          .where((p) => p.id == _positionId)
          .firstOrNull;
      final country = catalog.nationalities
          .where((p) => p.id == _nationalityId)
          .firstOrNull;
      if (position != null) _positionLabel.text = _label(position, false);
      if (country != null) _nationalityLabel.text = _label(country, true);
      return (catalog: catalog, starters: 0);
    }
    final data = await Future.wait<Object>([
      GameCatalog.load(),
      _sql.getTeamPlayers(widget.person!.id, widget.season!.id),
    ]);
    return (
      catalog: data[0] as GameCatalog,
      starters: (data[1] as List<Map<String, Object?>>)
          .where((row) => row['isBench'] != 1)
          .length,
    );
  }

  void _updatePreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_updatePreview);
      controller.dispose();
    }
    _scroll.dispose();
    _tabAnimation.dispose();
    super.dispose();
  }

  void _selectTab(int tab) {
    if (_saving || tab == _tab) return;
    FocusScope.of(context).unfocus();
    setState(() => _tab = tab);
    if (MediaQuery.disableAnimationsOf(context)) {
      _tabAnimation.value = 1;
    } else {
      _tabAnimation.forward(from: 0);
    }
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String? _nameError(String? value) => value == null || value.trim().isEmpty
      ? 'Informe o nome do jogador.'
      : null;

  String? _numberError(
    String? value, {
    bool required = false,
    int minimum = 0,
    int? maximum,
  }) {
    if (value == null || value.isEmpty) {
      return required ? 'Preencha este campo.' : null;
    }
    final number = int.tryParse(value);
    if (number == null) return 'Informe um número válido.';
    if (number < minimum || (maximum != null && number > maximum)) {
      return maximum == null
          ? 'Use um valor a partir de $minimum.'
          : 'Use um valor de $minimum a $maximum.';
    }
    return null;
  }

  int? get _invalidTab {
    if (_nameError(_name.text) != null || _positionId == null) return 0;
    if (_numberError(_overall.text, required: true, maximum: 99) != null ||
        _numberError(_potential.text, required: true, maximum: 99) != null ||
        _numberError(_height.text, minimum: 1) != null ||
        _numberError(_weight.text, minimum: 1) != null) {
      return 1;
    }
    if (widget.addToRoster && _numberError(_shirt.text, maximum: 999) != null) {
      return 2;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final invalidTab = _invalidTab;
    if (invalidTab != null) {
      _selectTab(invalidTab);
      setState(() => _showErrors = true);
      return;
    }
    setState(() => _saving = true);
    final playerId = widget.template?['id'] as String? ?? const Uuid().v4();
    String? copiedAvatar;
    var saved = false;
    try {
      final currentRoster = widget.addToRoster
          ? await _sql.getTeamPlayers(widget.person!.id, widget.season!.id)
          : const <Map<String, Object?>>[];
      final lineupFull =
          currentRoster.where((row) => row['isBench'] != 1).length >= 11;
      if (_avatar != null) {
        final previous = widget.template?['customAvatarFilePath'] as String?;
        if (_shared &&
            (_avatar == previous ||
                _avatar == CustomImageFiles.absolute(previous))) {
          copiedAvatar = previous;
        } else {
          await CustomImageFiles.docsDir();
          copiedAvatar = await CustomImageFiles.store(
            CustomImageFiles.absolute(_avatar) ?? _avatar!,
            'faces',
            _shared
                ? 'library/$playerId/${const Uuid().v4()}'
                : '${widget.person!.id}/$playerId',
          );
        }
      }
      final player = <String, Object?>{
        'id': playerId,
        'personId': widget.person?.id,
        'realPlayerId': null,
        'name': _name.text.trim(),
        'positionId': _positionId,
        'overall': int.parse(_overall.text),
        'potential': int.parse(_potential.text),
        'birthdate': _birthdate?.millisecondsSinceEpoch,
        'firstSeasonAge': widget.template?['firstSeasonAge'],
        'height': int.tryParse(_height.text),
        'weight': int.tryParse(_weight.text),
        'nationalityId': _nationalityId,
        'realFace': 0,
        'fromRealPlayer': 0,
        'customAvatarFilePath': copiedAvatar,
        'foot': _foot,
      };
      if (_shared) {
        await _sql.saveSharedPlayer(player);
      } else if (widget.addToRoster) {
        await _sql.createCustomTeamPlayer(player, {
          'id': const Uuid().v4(),
          'personId': widget.person!.id,
          'playerId': playerId,
          'seasonId': widget.season!.id,
          'x': null,
          'y': null,
          'overall': int.parse(_overall.text),
          'shirtNumber': int.tryParse(_shirt.text),
          'loanStatus': null,
          'wage': null,
          'yearlyWage': null,
          'marketValue': null,
          'isBench': _bench || lineupFull ? 1 : 0,
        });
      } else {
        await _sql.createCustomPlayer(player);
      }
      saved = true;
      final previousAvatar =
          widget.template?['customAvatarFilePath'] as String?;
      if (_shared &&
          previousAvatar != copiedAvatar &&
          (previousAvatar?.startsWith('/faces/library/$playerId/') ?? false)) {
        await CustomImageFiles.deleteFile(previousAvatar);
      }
      if (mounted) {
        widget.onCreated?.call(player);
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (!saved &&
          copiedAvatar != null &&
          copiedAvatar != widget.template?['customAvatarFilePath']) {
        await CustomImageFiles.deleteFile(copiedAvatar);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível criar o jogador. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    FocusScope.of(context).unfocus();
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (image != null && mounted) setState(() => _avatar = image.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível abrir a galeria. Tente novamente.'),
          ),
        );
      }
    }
  }

  Future<void> _pickBirthdate() async {
    FocusScope.of(context).unfocus();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: _referenceDate,
      initialDate: _birthdate ?? DateTime(_referenceDate.year - 20),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Nascimento do jogador',
    );
    if (date != null && mounted) {
      setState(() {
        _birthdate = date;
        _birthdayLabel.text = DateFormat('dd/MM/yyyy').format(date);
      });
    }
  }

  String _label(CatalogItem item, bool nationality) {
    final label = item.label.replaceAll(r"\'", "'");
    return (nationality ? 'countries.$label' : 'positions.positionsList.$label')
        .tr();
  }

  Future<void> _pickCatalog(GameCatalog catalog, bool nationality) async {
    FocusScope.of(context).unfocus();
    final items = nationality ? catalog.nationalities : catalog.positions;
    var query = '';
    final selected = await showModalBottomSheet<CatalogItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .8,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: StatefulBuilder(
            builder: (context, update) {
              final colors = CareerUiColors(context);
              final filtered = items
                  .where(
                    (item) => _label(
                      item,
                      nationality,
                    ).toLowerCase().contains(query.trim().toLowerCase()),
                  )
                  .toList();
              if (nationality) {
                filtered.sort(
                  (a, b) => _label(a, true).compareTo(_label(b, true)),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nationality ? 'Nacionalidade' : 'Posição do jogador',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          decoration: managerFieldDecoration(
                            context,
                            nationality ? 'Buscar país' : 'Buscar posição',
                            icon: Icons.search_rounded,
                          ),
                          onChanged: (value) => update(() => query = value),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        if (nationality && query.trim().isEmpty)
                          ListTile(
                            title: const Text('Não informar'),
                            onTap: () => Navigator.pop(
                              sheetContext,
                              const CatalogItem('', ''),
                            ),
                          ),
                        for (final item in filtered)
                          ListTile(
                            leading: Icon(
                              nationality
                                  ? Icons.flag_outlined
                                  : Icons.sports_soccer_rounded,
                              color: colors.accent,
                            ),
                            title: Text(_label(item, nationality)),
                            trailing:
                                (nationality ? _nationalityId : _positionId) ==
                                    item.id
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: colors.accent,
                                  )
                                : null,
                            onTap: () => Navigator.pop(sheetContext, item),
                          ),
                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Nenhum resultado encontrado.'),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (nationality) {
        _nationalityId = selected.id.isEmpty ? null : selected.id;
        _nationalityLabel.text = selected.id.isEmpty
            ? ''
            : _label(selected, true);
      } else {
        _positionId = selected.id;
        _positionLabel.text = _label(selected, false);
      }
    });
  }

  Widget _number(
    String label,
    TextEditingController controller, {
    required String fieldKey,
    bool required = false,
    int minimum = 0,
    int? maximum,
    String? hint,
    String? unit,
  }) => TextFormField(
    key: ValueKey(fieldKey),
    controller: controller,
    decoration: managerFieldDecoration(
      context,
      label,
      hint: hint,
    ).copyWith(suffixText: unit, errorMaxLines: 2),
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.next,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    validator: (value) => _numberError(
      value,
      required: required,
      minimum: minimum,
      maximum: maximum,
    ),
  );

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) =>
        constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) > 20
        ? Column(children: [first, const SizedBox(height: 16), second])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 12),
              Expanded(child: second),
            ],
          ),
  );

  Widget _section(String title, String subtitle, List<Widget> children) {
    final colors = CareerUiColors(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: colors.surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(color: colors.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 22),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _identity(GameCatalog catalog) => _section(
    'Identidade do jogador',
    'Dê um nome e uma posição ao seu novo talento.',
    [
      TextFormField(
        key: const ValueKey('custom-player-name'),
        controller: _name,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        maxLength: 80,
        decoration: managerFieldDecoration(
          context,
          'Nome do jogador',
          icon: Icons.badge_outlined,
          hint: 'Como ele será conhecido?',
        ),
        validator: _nameError,
      ),
      TextFormField(
        key: const ValueKey('custom-player-position'),
        controller: _positionLabel,
        readOnly: true,
        decoration: managerFieldDecoration(
          context,
          'Posição principal',
          icon: Icons.sports_soccer_rounded,
          hint: 'Selecione a posição',
          suffix: const Icon(Icons.expand_more_rounded),
        ),
        onTap: () => _pickCatalog(catalog, false),
        validator: (_) => _positionId == null ? 'Escolha uma posição.' : null,
      ),
      TextFormField(
        key: const ValueKey('custom-player-nationality'),
        controller: _nationalityLabel,
        readOnly: true,
        decoration: managerFieldDecoration(
          context,
          'Nacionalidade (opcional)',
          icon: Icons.flag_outlined,
          hint: 'Selecione o país',
          suffix: const Icon(Icons.expand_more_rounded),
        ),
        onTap: () => _pickCatalog(catalog, true),
      ),
      TextFormField(
        key: const ValueKey('custom-player-birthday'),
        controller: _birthdayLabel,
        readOnly: true,
        decoration: managerFieldDecoration(
          context,
          'Nascimento (opcional)',
          icon: Icons.calendar_month_outlined,
          hint: 'Escolha a data',
          suffix: _birthdate == null
              ? const Icon(Icons.expand_more_rounded)
              : IconButton(
                  tooltip: 'Remover data',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() {
                    _birthdate = null;
                    _birthdayLabel.clear();
                  }),
                ),
        ),
        onTap: _pickBirthdate,
      ),
      Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: CareerUiColors(context).muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nome e posição são obrigatórios. Os demais dados são opcionais.',
              style: TextStyle(
                color: CareerUiColors(context).muted,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _ratingBar(String label, String raw, Color color) {
    final value = int.tryParse(raw);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: CareerUiColors(context).muted,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              value == null ? '—' : '$value',
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(end: ((value ?? 0) / 99).clamp(0.0, 1.0)),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => LinearProgressIndicator(
            value: value,
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: color.withValues(alpha: .12),
          ),
        ),
      ],
    );
  }

  Widget _attributes() {
    final colors = CareerUiColors(context);
    return _section(
      'Atributos e evolução',
      'Defina o nível inicial e o potencial do jogador.',
      [
        _pair(
          _number(
            'Overall inicial',
            _overall,
            fieldKey: 'custom-player-overall',
            required: true,
            maximum: 99,
            hint: '0 a 99',
          ),
          _number(
            'Potencial',
            _potential,
            fieldKey: 'custom-player-potential',
            required: true,
            maximum: 99,
            hint: '0 a 99',
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _ratingBar('Nível atual', _overall.text, colors.accent),
              const SizedBox(height: 16),
              _ratingBar(
                'Potencial de evolução',
                _potential.text,
                colors.green,
              ),
            ],
          ),
        ),
        Text(
          'Pé preferido',
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
        _pair(
          _choice(
            'Direito',
            Icons.directions_walk_rounded,
            _foot == 'Right',
            () => setState(() => _foot = 'Right'),
          ),
          _choice(
            'Esquerdo',
            Icons.directions_walk_rounded,
            _foot == 'Left',
            () => setState(() => _foot = 'Left'),
          ),
        ),
        _pair(
          _number(
            'Altura',
            _height,
            fieldKey: 'custom-player-height',
            minimum: 1,
            hint: 'Opcional',
            unit: 'cm',
          ),
          _number(
            'Peso',
            _weight,
            fieldKey: 'custom-player-weight',
            minimum: 1,
            hint: 'Opcional',
            unit: 'kg',
          ),
        ),
        if (!widget.addToRoster)
          Text(
            'Ao criar, o jogador fica selecionado na transferência. A entrada no elenco acontece quando a transferência é concluída, respeitando a data de liberação.',
            style: TextStyle(color: colors.muted, fontSize: 12, height: 1.5),
          ),
      ],
    );
  }

  Widget _choice(
    String title,
    IconData icon,
    bool selected,
    VoidCallback onTap, {
    String? subtitle,
    bool enabled = true,
  }) {
    final colors = CareerUiColors(context);
    final foreground = enabled ? colors.text : colors.muted;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: selected ? colors.accent.withValues(alpha: .1) : colors.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? colors.accent : colors.line),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 21,
                    color: selected ? colors.accent : colors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: colors.muted,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(width: 10),
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20,
                      color: selected ? colors.accent : colors.muted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roster(GameCatalog catalog, bool lineupFull) {
    final colors = CareerUiColors(context);
    final team = catalog.team(
      widget.person!.fifaVersion,
      widget.person!.teamId,
      leagueId: widget.person!.leagueId,
    );
    return _section(
      'Lugar no elenco',
      'Escolha como o jogador chega ao seu time.',
      [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: colors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team?.label ?? widget.person!.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Temporada ${widget.season!.startDate.year} / ${widget.season!.endDate.year}',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _number(
          'Número da camisa (opcional)',
          _shirt,
          fieldKey: 'custom-player-shirt',
          maximum: 999,
          hint: 'Ex.: 10',
        ),
        _choice(
          'Titular',
          Icons.sports_soccer_rounded,
          !_bench && !lineupFull,
          () => setState(() => _bench = false),
          enabled: !lineupFull,
          subtitle: 'Adicionar aos 11 jogadores do time principal.',
        ),
        _choice(
          'Reserva',
          Icons.event_seat_outlined,
          _bench || lineupFull,
          () => setState(() => _bench = true),
          subtitle: 'Adicionar ao banco de reservas da temporada.',
        ),
        if (lineupFull)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: colors.amber, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Os 11 titulares já estão preenchidos. O jogador será criado como reserva; depois você pode movê-lo no elenco.',
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _tabs() {
    final labels = [
      'Identidade',
      'Atributos',
      if (widget.addToRoster) 'Elenco',
    ];
    const icons = [
      Icons.badge_outlined,
      Icons.tune_rounded,
      Icons.groups_outlined,
    ];
    final colors = CareerUiColors(context);
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: colors.surface(radius: 18),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                selected: i == _tab,
                button: true,
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: i == _tab
                        ? colors.accent.withValues(alpha: .15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.circular(13),
                    child: InkWell(
                      onTap: () => _selectTab(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 2,
                        ),
                        child: Column(
                          children: [
                            Icon(
                              icons[i],
                              size: 20,
                              color: i == _tab ? colors.accent : colors.muted,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              labels[i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: i == _tab ? colors.accent : colors.muted,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions() {
    final colors = CareerUiColors(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  if (_tab > 0) ...[
                    OutlinedButton(
                      onPressed: _saving ? null : () => _selectTab(_tab - 1),
                      child: const Text('Voltar'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : _tab == _lastTab
                          ? _save
                          : () => _selectTab(_tab + 1),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _tab == _lastTab
                                  ? Icons.person_add_alt_1_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 20,
                            ),
                      label: Text(
                        _saving
                            ? 'Salvando...'
                            : _tab == _lastTab
                            ? (_editing ? 'Salvar alterações' : 'Criar jogador')
                            : 'Continuar',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          _editing
              ? 'Editar jogador personalizado'
              : 'players.createPlayer'.tr(),
          maxLines: _shared ? 2 : 1,
          style: _shared ? const TextStyle(fontSize: 18, height: 1.15) : null,
        ),
      ),
      bottomNavigationBar: FutureBuilder<({GameCatalog catalog, int starters})>(
        future: _initialization,
        builder: (context, snapshot) =>
            snapshot.hasData ? _actions() : const SizedBox.shrink(),
      ),
      body: FutureBuilder<({GameCatalog catalog, int starters})>(
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
                      'Não foi possível carregar o elenco.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(() {
                        _initialization = _load();
                      }),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final lineupFull = data.starters >= 11;
          return Column(
            children: [
              Expanded(
                child: SafeArea(
                  bottom: false,
                  child: AbsorbPointer(
                    absorbing: _saving,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: ListView(
                          controller: _scroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            CustomPlayerPreview(
                              name: _name.text.trim(),
                              position: _positionId == null
                                  ? null
                                  : positionShortName(_positionId),
                              nationality: _nationalityLabel.text,
                              overall: int.tryParse(_overall.text),
                              potential: int.tryParse(_potential.text),
                              shirt: int.tryParse(_shirt.text),
                              avatar: _avatar,
                              fifaVersion: _fifaVersion,
                              onPickImage: _pickImage,
                              onRemoveImage: _avatar == null
                                  ? null
                                  : () => setState(() => _avatar = null),
                            ),
                            if (_shared)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  _editing
                                      ? 'Todos os FIFAs · Todas as carreiras. As alterações valem para as próximas adições; os históricos já registrados continuam preservados.'
                                      : 'Disponível em todos os FIFAs e em todas as suas carreiras.',
                                  style: TextStyle(
                                    color: CareerUiColors(context).muted,
                                    height: 1.5,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 18),
                            _tabs(),
                            const SizedBox(height: 18),
                            FadeTransition(
                              opacity: _tabAnimation.drive(
                                CurveTween(curve: Curves.easeOut),
                              ),
                              child: SlideTransition(
                                position: _tabAnimation.drive(
                                  Tween(
                                    begin: const Offset(0, .04),
                                    end: Offset.zero,
                                  ).chain(
                                    CurveTween(curve: Curves.easeOutCubic),
                                  ),
                                ),
                                child: Form(
                                  autovalidateMode: _showErrors
                                      ? AutovalidateMode.always
                                      : AutovalidateMode.onUserInteraction,
                                  child: KeyedSubtree(
                                    key: ValueKey(_tab),
                                    child: switch (_tab) {
                                      0 => _identity(data.catalog),
                                      1 => _attributes(),
                                      _ => _roster(data.catalog, lineupFull),
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
