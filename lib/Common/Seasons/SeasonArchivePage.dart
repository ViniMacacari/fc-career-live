import 'package:flutter/material.dart';

import '../../RootPage/DrawerWidget.dart';
import '../../models/Person.dart';
import '../../models/Season.dart';
import '../../utils/Components/CareerPageWidgets.dart';
import '../../utils/Components/CareerUiStyle.dart';
import '../../utils/SeasonClosureService.dart';
import '../../utils/SqlService.dart';
import 'SeasonClosingPage.dart';
import 'SeasonRecapPage.dart';

class SeasonArchivePage extends StatefulWidget {
  const SeasonArchivePage({
    super.key,
    required this.person,
    this.loader,
    this.service,
  });
  final Person person;
  final Future<List<Season>> Function()? loader;
  final SeasonClosureService? service;
  @override
  State<SeasonArchivePage> createState() => _SeasonArchivePageState();
}

class _SeasonArchivePageState extends State<SeasonArchivePage> {
  late final _service = widget.service ?? SeasonClosureService();
  late Future<List<Season>> _seasons = _load();
  int _filter = 0;
  String? _opening;
  Future<List<Season>> _load() async => [
    ...await (widget.loader?.call() ??
        SqlService.instance.getSeasons(widget.person.id)),
  ]..sort((a, b) => b.startDate.compareTo(a.startDate));
  Future<void> _open(Season season) async {
    if (_opening != null) return;
    setState(() => _opening = season.id);
    try {
      if (season.isClosed) {
        final review = await _service.load(widget.person, season);
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => SeasonRecapPage(
              person: widget.person,
              review: review,
              service: _service,
            ),
          ),
        );
      } else {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => SeasonClosingPage(
              person: widget.person,
              season: season,
              service: _service,
            ),
          ),
        );
      }
      if (mounted) setState(() => _seasons = _load());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir esta temporada. $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    return Scaffold(
      appBar: AppBar(
        leading: RootDrawerScope.leading(context),
        title: const Text('Temporadas'),
      ),
      body: FutureBuilder<List<Season>>(
        future: _seasons,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!,
              closed = all.where((s) => s.isClosed).length;
          final seasons = all
              .where(
                (s) =>
                    _filter == 0 || (_filter == 1 ? !s.isClosed : s.isClosed),
              )
              .toList();
          return RefreshIndicator(
            onRefresh: () async {
              final f = _load();
              setState(() => _seasons = f);
              await f;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(18),
              children: [
                CareerPageHeader(
                  title: 'Cada temporada,\num novo capítulo.',
                  subtitle:
                      '$closed retrospectiva${closed == 1 ? '' : 's'} guardada${closed == 1 ? '' : 's'}. Encerre também temporadas antigas e registre suas classificações finais.',
                  icon: Icons.auto_awesome_outlined,
                  eyebrow: 'A memória da sua carreira',
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Todas')),
                    ButtonSegment(value: 1, label: Text('Abertas')),
                    ButtonSegment(value: 2, label: Text('Encerradas')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.single),
                ),
                const SizedBox(height: 22),
                if (seasons.isEmpty)
                  const CareerEmptyState(
                    title: 'Nenhuma temporada neste filtro',
                    subtitle:
                        'Suas temporadas e retrospectivas ficam reunidas aqui.',
                    icon: Icons.calendar_month_outlined,
                  ),
                for (final (i, season) in seasons.indexed)
                  TweenAnimationBuilder<double>(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : Duration(milliseconds: 300 + mathDelay(i)),
                    tween: Tween(begin: 0, end: 1),
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - value)),
                        child: child,
                      ),
                    ),
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: _opening != null ? null : () => _open(season),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              CareerIconBadge(
                                icon: season.isClosed
                                    ? Icons.auto_awesome_outlined
                                    : Icons.calendar_month_outlined,
                                color: season.isClosed ? c.amber : c.accent,
                                size: 48,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      season.startDate.year ==
                                              season.endDate.year
                                          ? '${season.startDate.year}'
                                          : '${season.startDate.year}/${season.endDate.year}',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${_date(season.startDate)} – ${_date(season.endDate)}',
                                      style: TextStyle(
                                        color: c.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      season.isClosed
                                          ? 'Ver retrospectiva →'
                                          : 'Encerrar e registrar tabela →',
                                      style: TextStyle(
                                        color: season.isClosed
                                            ? c.amber
                                            : c.accent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_opening == season.id)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  int mathDelay(int i) => i < 6 ? i * 45 : 270;
  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
