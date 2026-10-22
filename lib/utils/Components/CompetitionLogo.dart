import 'package:flutter/material.dart';

import '../GameCatalog.dart';
import '../databaseUtils.dart';
import 'CatalogLogoAssets.dart';
import 'TeamLogo.dart';

class CompetitionLogo extends StatefulWidget {
  const CompetitionLogo({
    super.key,
    required this.version,
    required this.competitionId,
    this.size = 30,
  });
  final String version, competitionId;
  final double size;
  @override
  State<CompetitionLogo> createState() => _CompetitionLogoState();
}

class _CompetitionLogoState extends State<CompetitionLogo> {
  static final _cache = <String, Future<CatalogItem?>>{};
  static int _revision = -1;
  late Future<CatalogItem?> _item = _resolve();
  @override
  void initState() {
    super.initState();
    GameCatalog.customDataRevision.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() => _item = _resolve());
  }

  @override
  void dispose() {
    GameCatalog.customDataRevision.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didUpdateWidget(CompetitionLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.version != widget.version ||
        oldWidget.competitionId != widget.competitionId) {
      _item = _resolve();
    }
  }

  Future<CatalogItem?> _resolve() {
    final revision = GameCatalog.customDataRevision.value;
    if (_revision != revision) {
      _cache.clear();
      _revision = revision;
    }
    final id = widget.competitionId, version = widget.version;
    return _cache.putIfAbsent('$version/$id', () => _load(id, version));
  }

  Future<CatalogItem?> _load(String id, String version) async {
    final catalog = await GameCatalog.load();
    if (id.startsWith('league:')) {
      return catalog.league(version, id.substring(7));
    }
    final item = (await catalog.tournaments(version))
        .where((t) => t.id == id)
        .firstOrNull;
    if (item != null) {
      return CatalogItem(
        id,
        item.label,
        assetPath:
            item.assetPath ?? await CatalogLogoAssets.tournament(id, version),
        imageUrl: item.imageUrl,
      );
    }
    final custom = (await CustomContentService.getAllCustomTournaments())
        .where((row) => row.tournament.id == id)
        .firstOrNull;
    return custom == null
        ? null
        : CatalogItem(
            id,
            custom.tournament.name,
            isCustom: true,
            imageUrl: custom.tournament.imageName,
            imagePath: custom.imagePath,
          );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CatalogItem?>(
    future: _item,
    builder: (context, snapshot) => TeamLogo.fromItem(
      snapshot.data,
      size: widget.size,
      placeholder: SizedBox.square(
        dimension: widget.size,
        child: Icon(
          Icons.emoji_events_outlined,
          size: widget.size * .8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
