import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/SqlService.dart';
import 'DrawerItem.dart';
import 'DrawerWidget.dart';
import 'managerCareerMenuItems.dart';
import 'playerCareerMenuItems.dart';

const appVersion = String.fromEnvironment(
  'FLUTTER_BUILD_NAME',
  defaultValue: '0.7.1',
);

class RootPage extends StatefulWidget {
  const RootPage({
    super.key,
    required this.person,
    required this.onCreateManager,
    required this.onCreatePlayer,
    required this.onSelectManager,
    required this.onSelectPlayer,
    required this.onActivate,
    this.onOpenSettings,
  });
  final Person person;
  final VoidCallback onCreateManager,
      onCreatePlayer,
      onSelectManager,
      onSelectPlayer;
  final ValueChanged<Person> onActivate;
  final VoidCallback? onOpenSettings;

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  String _selected = 'fixtures';

  List<DrawerEntry> get _items =>
      widget.person.category == PersonCategory.manager
      ? managerCareerMenuItems(widget.person)
      : playerCareerMenuItems(widget.person);

  @override
  void didUpdateWidget(RootPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.person.id != widget.person.id) _selected = 'fixtures';
  }

  DrawerItem? _find(Iterable<DrawerEntry> entries, String id) {
    for (final entry in entries) {
      if (entry is! DrawerItem) continue;
      if (entry.id == id && entry.page != null) return entry;
      final child = _find(entry.children, id);
      if (child != null) return child;
    }
    return null;
  }

  void _select(DrawerItem item) {
    Navigator.pop(context);
    if (item.onPress != null) {
      item.onPress!(context);
    } else if (item.page != null) {
      setState(() => _selected = item.id);
    }
  }

  Future<void> _swapMode() async {
    Navigator.pop(context);
    final target = widget.person.category == PersonCategory.manager
        ? PersonCategory.player
        : PersonCategory.manager;
    final persons = await SqlService.instance.getPersons(target);
    if (persons.isEmpty) {
      target == PersonCategory.manager
          ? widget.onCreateManager()
          : widget.onCreatePlayer();
      return;
    }
    await SqlService.instance.setActivePersonId(persons.first.id);
    widget.onActivate(persons.first);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final page = _find(items, _selected) ?? _find(items, 'fixtures')!;
    return Scaffold(
      key: _scaffold,
      drawer: DrawerWidget(
        person: widget.person,
        items: items,
        selected: page.id,
        onSelect: _select,
        onChangeCareer: () {
          Navigator.pop(context);
          widget.person.category == PersonCategory.manager
              ? widget.onSelectManager()
              : widget.onSelectPlayer();
        },
        onSwapMode: _swapMode,
        onOpenSettings: widget.onOpenSettings == null
            ? null
            : () {
                Navigator.pop(context);
                widget.onOpenSettings!();
              },
        version: appVersion,
      ),
      body: RootDrawerScope(
        openDrawer: () => _scaffold.currentState?.openDrawer(),
        child: KeyedSubtree(
          key: ValueKey('${widget.person.id}/${page.id}'),
          child: page.page!(context),
        ),
      ),
    );
  }
}
