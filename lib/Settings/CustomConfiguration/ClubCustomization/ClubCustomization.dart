import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../models/ClubCustomizationModel.dart';
import '../../../utils/Components/TeamLogo.dart';
import '../../../utils/GameCatalog.dart';
import '../CustomConfigurationComponents.dart';
import 'ClubCustomizationFormPage.dart';

class ClubCustomization extends StatefulWidget {
  const ClubCustomization({super.key});
  @override
  State<ClubCustomization> createState() => _ClubCustomizationState();
}

class _ClubCustomizationState extends State<ClubCustomization> {
  final Future<GameCatalog> _catalog = GameCatalog.load();
  String _version = availableFifaVersions().first;
  String _query = '';

  Future<void> _open({ClubCustomizationModel? customization}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ClubCustomizationFormPage(
            customization: customization,
            initialFifaVersion: _version,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => CustomConfigurationTheme(
    child: Scaffold(
      appBar: AppBar(title: Text('customConfiguration.clubCustomization'.tr())),
      floatingActionButton: FloatingActionButton(
        onPressed: _open,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            CustomSearchField(
              hint: 'teams.searchByText'.tr(),
              onChanged: (value) => setState(() => _query = value),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final version in availableFifaVersions())
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(version),
                        selected: version == _version,
                        onSelected: (_) => setState(() => _version = version),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<GameCatalog>(
                future: _catalog,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return ValueListenableBuilder<int>(
                    valueListenable: GameCatalog.customDataRevision,
                    builder: (context, _, _) => _list(snapshot.data!),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _list(GameCatalog catalog) {
    final all = catalog.customizationsFor(_version);
    if (all.isEmpty) return const CustomEmptyState();
    final query = _query.trim().toLowerCase();
    final groups = <String, List<(ClubCustomizationModel, CatalogItem?)>>{};
    for (final item in all) {
      final original = catalog.team(
        _version,
        item.originalTeamId,
        leagueId: item.originalLeagueId,
        ignoreCustomizations: true,
      );
      final matches =
          item.clubName.toLowerCase().contains(query) ||
          (original?.label.toLowerCase().contains(query) ?? false);
      if (!matches) continue;
      (groups[item.originalLeagueId ?? 'nat'] ??= []).add((item, original));
    }
    if (groups.isEmpty) {
      return const CustomEmptyState(textKey: 'common.noItems');
    }
    String label(String leagueId) => leagueId == 'nat'
        ? 'nationalities.nationalTeams'.tr()
        : catalog.leagueLabel(_version, leagueId);
    final keys = groups.keys.toList()
      ..sort(
        (a, b) => label(a).toLowerCase().compareTo(label(b).toLowerCase()),
      );
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final leagueId = keys[index];
        final items = groups[leagueId]!
          ..sort(
            (a, b) => a.$1.clubName.toLowerCase().compareTo(
              b.$1.clubName.toLowerCase(),
            ),
          );
        final league = leagueId == 'nat'
            ? null
            : catalog.league(_version, leagueId);
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('customizations-$_version-$leagueId'),
            initiallyExpanded: true,
            leading: league == null
                ? const Icon(Icons.flag_outlined)
                : TeamLogo.fromItem(league, size: 30),
            title: Text(label(leagueId)),
            children: [
              for (final (item, original) in items) _card(item, original),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _card(ClubCustomizationModel item, CatalogItem? original) {
    final small = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).hintColor);
    Widget side(Widget logo, String caption, String name) => Expanded(
      child: Row(
        children: [
          logo,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caption, style: small),
                Text(name, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
    return CustomListCard(
      onTap: () => _open(customization: item),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            side(
              Opacity(
                opacity: 0.5,
                child: TeamLogo.fromItem(original, size: 36),
              ),
              'customConfiguration.originalName'.tr(),
              original?.label ?? item.originalTeamId,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.arrow_forward, size: 18),
            ),
            side(
              TeamLogo(
                imageUrl: item.imageUrl ?? original?.imageUrl,
                imagePath: item.imagePath ?? original?.imagePath,
                width: 36,
                height: 36,
              ),
              'customConfiguration.newName'.tr(),
              item.clubName,
            ),
          ],
        ),
      ),
    );
  }
}
