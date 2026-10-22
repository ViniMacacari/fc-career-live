import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../utils/GameCatalog.dart';
import '../utils/Components/TeamLogo.dart';

class SelectTrophy extends StatefulWidget {
  const SelectTrophy({super.key});
  @override
  State<SelectTrophy> createState() => _SelectTrophyState();
}

class _SelectTrophyState extends State<SelectTrophy> {
  String _query = '';
  late final _awards = GameCatalog.load().then((catalog) => catalog.awards());
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('trophies.selectTrophy'.tr())),
    body: FutureBuilder<List<AwardCatalogItem>>(
      future: _awards,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final awards =
            snapshot.data!
                .where(
                  (award) =>
                      award.label.toLowerCase().contains(_query.toLowerCase()),
                )
                .toList()
              ..sort((a, b) => a.label.compareTo(b.label));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'customConfiguration.searchByName'.tr(),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: awards.length,
                itemBuilder: (context, index) {
                  final award = awards[index];
                  return ListTile(
                    leading: TeamLogo(
                      imagePath: award.imagePath,
                      imageUrl: award.imageUrl,
                      localAsset: award.imageName == null
                          ? null
                          : 'assets/images/cupsLogos/${award.imageName}',
                      fallbackIcon: Icons.emoji_events_outlined,
                      width: 42,
                      height: 42,
                    ),
                    title: Text(award.label),
                    onTap: () => Navigator.pop(context, award),
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
