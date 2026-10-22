import 'package:flutter/material.dart';

import 'SqlService.dart';

Future<DateTime?> showCareerDatePicker({
  required BuildContext context,
  required String personId,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  final latestDate = await SqlService.instance.getLatestFixtureDate(personId);
  if (!context.mounted) return null;

  final firstDay = DateUtils.dateOnly(firstDate);
  final lastDay = DateUtils.dateOnly(lastDate);
  final preferredDay = DateUtils.dateOnly(latestDate ?? initialDate);
  final selectedDay = preferredDay.isBefore(firstDay)
      ? firstDay
      : preferredDay.isAfter(lastDay)
      ? lastDay
      : preferredDay;

  return showDatePicker(
    context: context,
    initialDate: selectedDay,
    firstDate: firstDay,
    lastDate: lastDay,
  );
}
