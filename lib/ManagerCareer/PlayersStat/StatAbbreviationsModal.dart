import '../../utils/AppColors.dart';

import 'package:flutter/material.dart';

import 'PlayersStatData.dart';

Future<void> showStatAbbreviations(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: ListView(
            children: [
              const ListTile(
                title: Text('Abreviações', style: TextStyle(fontSize: 18)),
              ),
              for (final metric in PlayersStatMetric.values)
                ListTile(
                  leading: SizedBox(
                    width: 52,
                    child: Text(
                      metric.shortLabel,
                      style: TextStyle(color: AppColors.of(context).accent),
                    ),
                  ),
                  title: Text(metric.label),
                ),
            ],
          ),
        ),
      ),
    );
