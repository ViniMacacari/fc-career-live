import '../utils/AppColors.dart';

import 'package:flutter/material.dart';

import '../utils/Components/CareerUiStyle.dart';
import '../utils/Components/TeamLogo.dart';
import '../utils/GameCatalog.dart';
import 'FcScoreApi.dart';
import 'FcScoreCompetitionStructure.dart';
import 'FcScoreWidgets.dart';
import 'FcScoreStandingZones.dart';

Widget careerCompetitionLogo(CatalogItem? item, {double size = 40}) => TeamLogo(
  localAsset: item?.assetPath,
  imageUrl: item?.imageUrl,
  imagePath: item?.imagePath,
  width: size,
  height: size,
);

class CareerCompetitionSurface extends StatelessWidget {
  const CareerCompetitionSurface({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: CareerUiColors(context).panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: CareerUiColors(context).line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

typedef CareerTeamName = String Function(String);
typedef CareerTeamLogo = Widget Function(String, double);

class CareerCompetitionMatchCard extends StatelessWidget {
  const CareerCompetitionMatchCard({
    super.key,
    required this.fixture,
    required this.name,
    required this.logo,
    this.onTap,
  });
  final FcJson fixture;
  final CareerTeamName name;
  final CareerTeamLogo logo;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    final home = fcObject(fixture['home']), away = fcObject(fixture['away']);
    final played = fixture['played'] == true || fixture['played'] == 1;
    Widget club(FcJson side) {
      final id = fcId(fcObject(side['team'])['id']);
      return Expanded(
        child: Column(
          children: [
            logo(id, 36),
            const SizedBox(height: 8),
            Text(
              name(id),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
        ),
      );
    }

    return CareerCompetitionSurface(
      onTap: onTap,
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 13, color: c.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${fcDay(fixture['date'])}${fcId(fixture['time']).isEmpty ? '' : ' · ${fixture['time']}'}',
                  style: TextStyle(color: c.muted, fontSize: 11),
                ),
              ),
              Text(
                played ? 'Encerrada' : 'A disputar',
                style: TextStyle(
                  fontSize: 10,
                  color: played ? c.green : c.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              club(home),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  played
                      ? '${fcValue(home['goals'])} – ${fcValue(away['goals'])}'
                      : '×',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              club(away),
            ],
          ),
          if (fcInt(home['penalties']) != null &&
              fcInt(away['penalties']) != null) ...[
            const SizedBox(height: 10),
            Text(
              'Pênaltis ${home['penalties']} – ${away['penalties']}',
              style: TextStyle(
                color: c.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            '${fcStageLabel(fcName(fixture['stage'], 'Partida'))}'
            '${fcInt(fixture['round']) == null ? '' : ' · Rodada ${fixture['round']}'}',
            style: TextStyle(color: c.muted, fontSize: 11),
          ),
          if (onTap != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Ver partida',
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: c.accent),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class CareerStandingsTable extends StatefulWidget {
  const CareerStandingsTable({
    super.key,
    required this.rows,
    required this.name,
    required this.logo,
    required this.onTeam,
    required this.isOwn,
    this.zones = const [],
    this.zoneLabel,
  });
  final List<FcJson> rows, zones;
  final CareerTeamName name;
  final CareerTeamLogo logo;
  final ValueChanged<String> onTeam;
  final bool Function(String) isOwn;
  final String Function(FcStandingZone)? zoneLabel;
  @override
  State<CareerStandingsTable> createState() => _CareerStandingsTableState();
}

class _CareerStandingsTableState extends State<CareerStandingsTable> {
  final _scroll = ScrollController();
  static const _columns = [
    ('PTS', 'points'),
    ('PJ', 'played'),
    ('V', 'wins'),
    ('E', 'draws'),
    ('D', 'losses'),
    ('GP', 'goalsFor'),
    ('GC', 'goalsAgainst'),
    ('SG', 'goalDifference'),
  ];
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _label(FcStandingZone zone) =>
      widget.zoneLabel?.call(zone) ?? zone.label();
  static const _tierColors = [
    (AppColors.internationalTier1Dark, AppColors.internationalTier1Light),
    (AppColors.internationalTier2Dark, AppColors.internationalTier2Light),
    (AppColors.internationalTier3Dark, AppColors.internationalTier3Light),
  ];

  Color _color(
    FcStandingZone zone,
    CareerUiColors c,
    Map<String, int> tiers,
    bool dark,
  ) {
    final tier = _tierColors[((tiers[zone.key] ?? 1) - 1).clamp(0, 2)];
    final base = switch (zone.type) {
      'champion' => c.amber,
      'promotion' || 'promotionPlayoff' => c.green,
      'relegation' || 'relegationPlayoff' => c.red,
      _ => dark ? tier.$1 : tier.$2,
    };
    return zone.type.endsWith('Playoff') || (zone.entry ?? 1) > 1
        ? base.withValues(alpha: .55)
        : base;
  }

  Widget _form(Object? value, CareerUiColors c, double scale) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final result in value is List ? value : const [])
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Container(
            width: 18 * scale,
            height: 22 * scale,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color:
                  (result == 'W'
                          ? c.green
                          : result == 'L'
                          ? c.red
                          : c.amber)
                      .withValues(alpha: .14),
            ),
            child: Text(
              result == 'W'
                  ? 'V'
                  : result == 'L'
                  ? 'D'
                  : 'E',
              style: TextStyle(
                fontSize: 9,
                color: result == 'W'
                    ? c.green
                    : result == 'L'
                    ? c.red
                    : c.amber,
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final zones = fcStandingZones(widget.rows, widget.zones);
    final tiers = fcContinentalTiers(widget.rows, zones);
    final legend = [...zones]
      ..sort(
        (a, b) => (fcZoneStart(widget.rows, a) ?? 999).compareTo(
          fcZoneStart(widget.rows, b) ?? 999,
        ),
      );
    final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final textScale = scale < 1 ? 1.0 : scale;
    final rowHeight = 32 * textScale + 24;
    Widget cell(Object? value, double width, {bool points = false}) => SizedBox(
      width: width,
      child: Text(
        fcValue(value),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: points ? c.accent : c.text,
          fontWeight: points ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
    return CareerCompetitionSurface(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.swipe_left_rounded, size: 15, color: c.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Deslize para ver todas as colunas',
                  style: TextStyle(fontSize: 10, color: c.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final positionWidth = 30 * textScale,
                  columnWidth = 38 * textScale;
              final teamWidth =
                  (constraints.maxWidth - positionWidth - 2 * columnWidth)
                      .clamp(160 * textScale, 240 * textScale)
                      .toDouble();
              final formWidth = 120 * textScale, zoneWidth = 230 * textScale;
              final totalWidth =
                  positionWidth +
                  teamWidth +
                  _columns.length * columnWidth +
                  formWidth +
                  (zones.isEmpty ? 0 : zoneWidth);
              return Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  key: const Key('competition-table-horizontal'),
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    width: totalWidth,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 38 * textScale,
                          child: Row(
                            children: [
                              cell('#', positionWidth),
                              SizedBox(
                                width: teamWidth,
                                child: Text(
                                  'Equipe',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: c.muted,
                                  ),
                                ),
                              ),
                              for (final column in _columns)
                                cell(
                                  column.$1,
                                  columnWidth,
                                  points: column.$2 == 'points',
                                ),
                              cell('Forma', formWidth),
                              if (zones.isNotEmpty)
                                cell('Classificação', zoneWidth),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: c.line),
                        for (final row in widget.rows)
                          Builder(
                            builder: (context) {
                              final id = fcId(fcObject(row['team'])['id']),
                                  own = widget.isOwn(id);
                              final rowZones = fcRowZones(row, zones);
                              final qualification = rowZones
                                  .map(_label)
                                  .join(' · ');
                              return InkWell(
                                key: ValueKey('competition-standing-$id'),
                                onTap: () => widget.onTeam(id),
                                child: Container(
                                  height: rowHeight,
                                  decoration: BoxDecoration(
                                    color: own
                                        ? c.accent.withValues(alpha: .1)
                                        : null,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: c.line,
                                        width: .5,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: positionWidth,
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 5,
                                              child: Column(
                                                children: [
                                                  for (final zone in rowZones)
                                                    Expanded(
                                                      child: Tooltip(
                                                        message: _label(zone),
                                                        child: Container(
                                                          key: ValueKey(
                                                            'competition-zone-$id-${zone.key}',
                                                          ),
                                                          margin:
                                                              const EdgeInsets.symmetric(
                                                                vertical: 3,
                                                              ),
                                                          width: 3,
                                                          color: _color(
                                                            zone,
                                                            c,
                                                            tiers,
                                                            dark,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                fcValue(row['position']),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: c.text,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: teamWidth,
                                        child: Row(
                                          children: [
                                            widget.logo(id, 24),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: Text(
                                                  widget.name(id),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    height: 1.3,
                                                    color: c.text,
                                                    fontWeight: own
                                                        ? FontWeight.w800
                                                        : FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      for (final column in _columns)
                                        cell(
                                          row[column.$2],
                                          columnWidth,
                                          points: column.$2 == 'points',
                                        ),
                                      SizedBox(
                                        width: formWidth,
                                        child: _form(row['form'], c, textScale),
                                      ),
                                      if (zones.isNotEmpty)
                                        SizedBox(
                                          width: zoneWidth,
                                          child: Text(
                                            qualification.isEmpty
                                                ? '—'
                                                : qualification,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: c.text,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'PTS Pontos · PJ Jogos · V Vitórias · E Empates · D Derrotas\nGP Gols marcados · GC Gols sofridos · SG Saldo de gols',
            style: TextStyle(color: c.muted, fontSize: 9, height: 1.5),
          ),
          if (zones.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                for (final zone in legend)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _color(zone, c, tiers, dark),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _label(zone),
                          style: TextStyle(fontSize: 10, color: c.text),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Faixas de classificação conforme a posição atual.',
              style: TextStyle(fontSize: 9, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class CareerKnockoutCard extends StatelessWidget {
  const CareerKnockoutCard({
    super.key,
    required this.tie,
    required this.name,
    required this.logo,
    required this.onTeam,
  });
  final FcKnockoutTie tie;
  final CareerTeamName name;
  final CareerTeamLogo logo;
  final ValueChanged<String> onTeam;
  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    final multiple =
        tie.games.length > 1 ||
        tie.rows.any((r) => (fcInt(r['played']) ?? 0) > 1);
    final started =
        tie.played.isNotEmpty ||
        tie.rows.any((r) => (fcInt(r['played']) ?? 0) > 0);
    return CareerCompetitionSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            multiple
                ? !started
                      ? 'IDA E VOLTA'
                      : 'AGREGADO${tie.games.any((g) => g['played'] != true && g['played'] != 1) ? ' PARCIAL' : ''}'
                : 'CONFRONTO',
            style: TextStyle(
              color: c.muted,
              fontSize: 9,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final id in tie.teams)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: InkWell(
                onTap: () => onTeam(id),
                child: Row(
                  children: [
                    logo(id, 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name(id),
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${tie.score(id) ?? '—'}',
                      style: TextStyle(
                        color: c.accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 21,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (tie.penalties(tie.teams.first) != null &&
              tie.penalties(tie.teams.last) != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Pênaltis ${tie.penalties(tie.teams.first)} – ${tie.penalties(tie.teams.last)}',
                style: TextStyle(
                  color: c.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (tie.games.isNotEmpty) ...[
            Divider(height: 24, color: c.line),
            for (final (index, f) in tie.games.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${tie.games.length == 2
                            ? index == 0
                                  ? 'Ida'
                                  : 'Volta'
                            : 'Partida ${index + 1}'} · ${fcDay(f['date'])}',
                        style: TextStyle(color: c.muted, fontSize: 10),
                      ),
                    ),
                    logo(fcId(fcObject(fcObject(f['home'])['team'])['id']), 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        f['played'] == true || f['played'] == 1
                            ? '${fcValue(fcObject(f['home'])['goals'])} – ${fcValue(fcObject(f['away'])['goals'])}'
                            : '×',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: c.text,
                        ),
                      ),
                    ),
                    logo(fcId(fcObject(fcObject(f['away'])['team'])['id']), 18),
                  ],
                ),
              ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Detalhes das partidas ainda indisponíveis.',
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}
