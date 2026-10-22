import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../Common/SelectTournamentPage.dart';
import '../../../models/Person.dart';
import '../../../models/Season.dart';
import '../../../utils/AppColors.dart';
import '../../../utils/GameCatalog.dart';
import '../../OtherPlayers/OtherPlayerWidgets.dart';
import '../../OtherPlayers/OtherPlayersData.dart';
import 'PlayerAnalysis.dart';
import 'PlayerProfileVisuals.dart';

String _number(int? value) => value?.toString() ?? '–';

class PlayerWorldSeasonPanel extends StatelessWidget {
  const PlayerWorldSeasonPanel({
    super.key,
    required this.version,
    required this.lines,
    required this.onEdit,
    required this.onAdd,
    this.onRefresh,
    this.syncing = false,
    this.syncError,
  });
  final String version;
  final List<CompetitionLine> lines;
  final ValueChanged<CompetitionLine> onEdit;
  final VoidCallback onAdd;
  final VoidCallback? onRefresh;
  final bool syncing;
  final String? syncError;

  Widget _row(
    BuildContext context,
    CompetitionLine line, {
    bool total = false,
    bool showTeam = false,
  }) {
    final c = AppColors.of(context);
    final style = TextStyle(
      color: c.text,
      fontSize: 13,
      fontWeight: total ? FontWeight.w800 : FontWeight.w600,
    );
    Widget cell(String text, double width) => SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.center, style: style),
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          if (!total) ...[
            SizedBox(
              width: 24,
              height: 24,
              child: line.tournamentId == null
                  ? Icon(Icons.emoji_events_outlined, size: 19, color: c.muted)
                  : TournamentBadge(
                      version: version,
                      tournamentId: line.tournamentId!,
                      size: 22,
                    ),
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        line.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                    if (!line.fromApi) ...[
                      const SizedBox(width: 6),
                      const SourceTag('Editado'),
                    ],
                  ],
                ),
                if (showTeam && line.teamName != null)
                  Text(
                    line.teamName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
          cell(_number(line.appearances), 30),
          cell(_number(line.goals), 30),
          cell(_number(line.assists), 30),
          SizedBox(
            width: 42,
            child: Align(
              alignment: Alignment.centerRight,
              child: line.rating == null
                  ? Text('–', style: style)
                  : ProfileRating(line.rating, small: true),
            ),
          ),
        ],
      ),
    );
    return total
        ? content
        : InkWell(
            key: ValueKey('world-line/${line.key}'),
            onTap: () => onEdit(line),
            child: content,
          );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final total = CompetitionLine.total(lines);
    final header = TextStyle(
      color: c.muted,
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: .4,
    );
    final minutes = total.minutes;
    final involvement = (total.goals ?? 0) + (total.assists ?? 0);
    final showTeam = {for (final l in lines) l.teamName}.length > 1;
    final note = syncing
        ? 'Buscando os números no FC Score…'
        : total.date != null
        ? 'Números do save em ${DateFormat('dd/MM/yyyy').format(total.date!)}${syncError == null ? '' : ' · $syncError'}'
        : syncError;
    return ProfilePanel(
      key: const ValueKey('player-world-season'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Por competição',
                    maxLines: 1,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (onRefresh != null)
                syncing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        key: const ValueKey('world-line-refresh'),
                        tooltip: 'Atualizar pela API',
                        onPressed: onRefresh,
                        icon: const Icon(Icons.sync_rounded, size: 20),
                      ),
              IconButton.filledTonal(
                key: const ValueKey('world-line-add'),
                tooltip: 'Adicionar competição',
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                note,
                key: const ValueKey('world-line-note'),
                style: TextStyle(
                  color: c.accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Text(
            lines.isEmpty
                ? 'Sem números nesta temporada. A importação pela API traz jogos, gols e notas, e você pode adicionar uma competição.'
                : 'Todos os jogos da temporada, por clubes e seleção, e os números que você editou. Toque numa competição para ajustar.',
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 14),
            AnalysisStrip(
              items: [
                (_number(total.appearances), 'Jogos'),
                (_number(total.goals), 'Gols'),
                (_number(total.assists), 'Assist.'),
                (analysisNumber(total.rating, decimals: 2), 'Nota média'),
              ],
            ),
            if (minutes != null && minutes > 0) ...[
              const SizedBox(height: 10),
              Text(
                [
                  '${analysisNumber(minutes)} minutos',
                  if (involvement > 0)
                    'participa de um gol a cada ${(minutes / involvement).round()}\'',
                  if ((total.yellowCards ?? 0) + (total.redCards ?? 0) > 0)
                    '${total.yellowCards ?? 0} amarelos · ${total.redCards ?? 0} vermelhos',
                ].join(' · '),
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('COMPETIÇÃO', style: header)),
                for (final label in ['J', 'G', 'A'])
                  SizedBox(
                    width: 30,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: header,
                    ),
                  ),
                SizedBox(
                  width: 42,
                  child: Text('NOTA', textAlign: TextAlign.end, style: header),
                ),
              ],
            ),
            for (final line in lines) ...[
              Divider(height: 1, color: c.line.withValues(alpha: .5)),
              _row(context, line, showTeam: showTeam),
            ],
            if (lines.length > 1) ...[
              Divider(height: 1, color: c.line),
              _row(context, total, total: true),
            ],
          ],
        ],
      ),
    );
  }
}

class PlayerWorldCareerPanel extends StatelessWidget {
  const PlayerWorldCareerPanel({
    super.key,
    required this.version,
    required this.seasons,
    required this.lines,
  });
  final String version;
  final List<Season> seasons;
  final Map<String, List<CompetitionLine>> lines;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final header = TextStyle(
      color: c.muted,
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
    );
    final rows = [
      for (final season in seasons)
        if (lines[season.id]?.isNotEmpty ?? false)
          (season, CompetitionLine.total(lines[season.id]!), lines[season.id]!),
    ];
    final all = CompetitionLine.total([for (final r in rows) r.$2]);
    Widget cell(String text, double width, {bool bold = false}) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.text,
          fontSize: 13,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
    return ProfilePanel(
      key: const ValueKey('player-world-career'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Temporadas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            rows.isEmpty
                ? 'Nenhuma temporada com números. Eles aparecem com a importação pela API ou ao adicionar uma competição na aba Temporada.'
                : 'Todas as competições de cada temporada, pelo clube em que jogou.',
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('TEMPORADA', style: header)),
                for (final label in ['J', 'G', 'A', 'NOTA'])
                  SizedBox(
                    width: label == 'NOTA' ? 40 : 30,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: header,
                    ),
                  ),
              ],
            ),
            for (final (season, total, seasonLines) in rows) ...[
              Divider(height: 1, color: c.line.withValues(alpha: .5)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            season.startDate.year == season.endDate.year
                                ? '${season.startDate.year}'
                                : '${season.startDate.year % 100}/${season.endDate.year % 100}',
                            style: TextStyle(
                              color: c.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          for (final team in {
                            for (final l in seasonLines)
                              if (l.teamId != null) l.teamId!: l.leagueId,
                          }.entries.take(2))
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: ClubLogo(
                                version: version,
                                club:
                                    GameCatalog.current?.team(
                                      version,
                                      team.key,
                                      leagueId: team.value,
                                    ) ??
                                    CatalogItem(team.key, ''),
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    ),
                    cell(_number(total.appearances), 30),
                    cell(_number(total.goals), 30),
                    cell(_number(total.assists), 30),
                    cell(analysisNumber(total.rating, decimals: 1), 40),
                  ],
                ),
              ),
            ],
            if (rows.length > 1) ...[
              Divider(height: 1, color: c.line),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    cell(_number(all.appearances), 30, bold: true),
                    cell(_number(all.goals), 30, bold: true),
                    cell(_number(all.assists), 30, bold: true),
                    cell(
                      analysisNumber(all.rating, decimals: 1),
                      40,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

enum CompetitionLineAction { save, restore, delete }

Future<(CompetitionLineAction, CompetitionLine)?> showCompetitionLineSheet(
  BuildContext context, {
  required Person person,
  CompetitionLine? line,
  CatalogItem? team,
  bool goalkeeper = false,
}) => showModalBottomSheet<(CompetitionLineAction, CompetitionLine)>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AppColors.of(context).background,
  builder: (_) => _LineSheet(
    person: person,
    line: line,
    team: team,
    goalkeeper: goalkeeper,
  ),
);

class _LineSheet extends StatefulWidget {
  const _LineSheet({
    required this.person,
    required this.line,
    required this.team,
    required this.goalkeeper,
  });
  final Person person;
  final CompetitionLine? line;
  final CatalogItem? team;
  final bool goalkeeper;
  @override
  State<_LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<_LineSheet> {
  late final l = widget.line;
  late String? _tournamentId = l?.tournamentId;
  late String _name = l?.name ?? '';
  late final _fields = {
    'appearances': TextEditingController(text: l?.appearances?.toString()),
    'goals': TextEditingController(text: l?.goals?.toString()),
    'assists': TextEditingController(text: l?.assists?.toString()),
    'minutes': TextEditingController(text: l?.minutes?.toString()),
    'rating': TextEditingController(
      text: l?.rating?.toStringAsFixed(2).replaceAll('.', ','),
    ),
    'yellowCards': TextEditingController(text: l?.yellowCards?.toString()),
    'redCards': TextEditingController(text: l?.redCards?.toString()),
    'cleanSheets': TextEditingController(text: l?.cleanSheets?.toString()),
  };
  String? _error;

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _int(String key) => int.tryParse(_fields[key]!.text.trim());

  Future<void> _pickCompetition() async {
    final item = await Navigator.push<CatalogItem>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SelectTournamentPage(fifaVersion: widget.person.fifaVersion),
      ),
    );
    if (item == null || !mounted) return;
    setState(() {
      _tournamentId = item.id;
      _name = item.label;
      _error = null;
    });
  }

  void _save() {
    if (_name.isEmpty) {
      setState(() => _error = 'Escolha a competição.');
      return;
    }
    final rating = double.tryParse(
      _fields['rating']!.text.trim().replaceAll(',', '.'),
    );
    if (rating != null && (rating < 0 || rating > 10)) {
      setState(() => _error = 'A nota vai de 0 a 10.');
      return;
    }
    Navigator.pop(context, (
      CompetitionLineAction.save,
      CompetitionLine(
        key: l?.key ?? _tournamentId!,
        name: _name,
        tournamentId: _tournamentId,
        teamId: l?.teamId ?? widget.team?.id,
        leagueId: l?.leagueId ?? widget.team?.leagueId,
        appearances: _int('appearances'),
        goals: _int('goals'),
        assists: _int('assists'),
        minutes: _int('minutes'),
        rating: rating,
        yellowCards: _int('yellowCards'),
        redCards: _int('redCards'),
        cleanSheets: _int('cleanSheets'),
        manualId: l?.manualId,
      ),
    ));
  }

  Widget _field(String key, String label, {bool decimal = false}) => TextField(
    key: ValueKey('world-line-field/$key'),
    controller: _fields[key],
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9,.]' : r'\d')),
    ],
    decoration: InputDecoration(isDense: true, labelText: label),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final pairs = [
      ('appearances', 'Jogos', 'minutes', 'Minutos'),
      ('goals', 'Gols', 'assists', 'Assistências'),
      ('rating', 'Nota média', 'yellowCards', 'Amarelos'),
      if (widget.goalkeeper)
        ('redCards', 'Vermelhos', 'cleanSheets', 'Sem sofrer gols'),
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l == null ? 'Adicionar competição' : 'Editar números',
                style: TextStyle(
                  color: c.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Material(
                color: c.panel,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  key: const ValueKey('world-line-competition'),
                  enabled: l == null,
                  onTap: _pickCompetition,
                  leading: _tournamentId == null
                      ? Icon(Icons.emoji_events_outlined, color: c.muted)
                      : TournamentBadge(
                          version: widget.person.fifaVersion,
                          tournamentId: _tournamentId!,
                        ),
                  title: Text(
                    _name.isEmpty ? 'Escolher competição' : _name,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: l == null
                      ? Icon(Icons.chevron_right_rounded, color: c.muted)
                      : null,
                ),
              ),
              const SizedBox(height: 14),
              for (final (a, la, b, lb) in pairs) ...[
                Row(
                  children: [
                    Expanded(child: _field(a, la, decimal: a == 'rating')),
                    const SizedBox(width: 10),
                    Expanded(child: _field(b, lb)),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (!widget.goalkeeper) ...[
                Row(
                  children: [
                    Expanded(child: _field('redCards', 'Vermelhos')),
                    const SizedBox(width: 10),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: c.danger, fontSize: 12.5),
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('world-line-save'),
                onPressed: _save,
                child: const Text('Salvar'),
              ),
              if (l?.manualId != null)
                TextButton(
                  key: const ValueKey('world-line-remove'),
                  onPressed: () => Navigator.pop(context, (
                    l!.overridesApi
                        ? CompetitionLineAction.restore
                        : CompetitionLineAction.delete,
                    l!,
                  )),
                  child: Text(
                    l!.overridesApi
                        ? 'Restaurar dados da API'
                        : 'Excluir competição',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
