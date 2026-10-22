import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../utils/GameCatalog.dart';

class SelectNationalityPage extends StatefulWidget {
  const SelectNationalityPage({super.key, this.title});

  final String? title;
  @override
  State<SelectNationalityPage> createState() => _SelectNationalityPageState();
}

class _SelectNationalityPageState extends State<SelectNationalityPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title ?? 'players.selectNationality'.tr()),
    ),
    body: FutureBuilder<GameCatalog>(
      future: GameCatalog.load(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items =
            snapshot.data!.nationalities
                .where(
                  (item) =>
                      item.label.toLowerCase().contains(_query.toLowerCase()),
                )
                .toList()
              ..sort((a, b) => a.label.compareTo(b.label));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'nationalities.searchNationality'.tr(),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(items[index].label),
                  onTap: () => Navigator.pop(context, items[index]),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
