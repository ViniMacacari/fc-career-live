import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/ManagerFixturePlayerPerformance.dart';

const addedTimeMinutes = {45, 90, 105, 120};

String formatEventMinute(int? minute, int? added, {bool isPenalty = false}) {
  if (minute == null) return '';
  final suffix = isPenalty ? ' (${'fixtures.penaltyShort'.tr()})' : '';
  if ((added ?? 0) > 0) return "$minute+$added'$suffix";
  return "$minute'$suffix";
}

int eventSortValue(int? minute, int? added) =>
    minute == null ? 999999 : minute * 100 + (added ?? 0);

List<T> getSortedDetails<T extends PerformanceTimeDetails>(Iterable<T> items) {
  final timed = items.where((item) => item.minute != null).toList()
    ..sort(
      (a, b) => eventSortValue(
        a.minute,
        a.addedMinute,
      ).compareTo(eventSortValue(b.minute, b.addedMinute)),
    );
  return [...timed, ...items.where((item) => item.minute == null)];
}

class EventTimeValue {
  const EventTimeValue(this.minute, this.addedMinute);
  final int? minute;
  final int addedMinute;
}

Future<EventTimeValue?> getEventTime(
  BuildContext context,
  String title,
  int? minute,
  int? added, {
  int maxValue = 140,
  int minValue = 0,
}) {
  var selectedMinute = (minute ?? minValue).clamp(minValue, maxValue);
  var selectedAdded = addedTimeMinutes.contains(selectedMinute)
      ? (added ?? 0).clamp(0, 15)
      : 0;
  return showDialog<EventTimeValue>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final showAdded = addedTimeMinutes.contains(selectedMinute);
        Widget wheel({
          required int count,
          required int initial,
          required String Function(int) label,
          required ValueChanged<int> onChanged,
        }) => SizedBox(
          width: 80,
          height: 160,
          child: CupertinoPicker(
            scrollController: FixedExtentScrollController(initialItem: initial),
            itemExtent: 40,
            onSelectedItemChanged: onChanged,
            children: [
              for (var index = 0; index < count; index++)
                Center(child: Text(label(index))),
            ],
          ),
        );
        return AlertDialog(
          title: Text(title),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              wheel(
                count: maxValue - minValue + 1,
                initial: selectedMinute - minValue,
                label: (index) =>
                    index + minValue == 0 ? '-' : '${index + minValue}',
                onChanged: (index) => setState(() {
                  selectedMinute = index + minValue;
                  if (!addedTimeMinutes.contains(selectedMinute)) {
                    selectedAdded = 0;
                  }
                }),
              ),
              if (showAdded) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('+', style: TextStyle(fontSize: 22)),
                ),
                wheel(
                  count: 16,
                  initial: selectedAdded,
                  label: (index) => index == 0 ? '-' : '+$index',
                  onChanged: (index) => setState(() => selectedAdded = index),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                EventTimeValue(
                  selectedMinute == 0 ? null : selectedMinute,
                  selectedMinute == 0 ? 0 : selectedAdded,
                ),
              ),
              child: Text('common.ok'.tr()),
            ),
          ],
        );
      },
    ),
  );
}
