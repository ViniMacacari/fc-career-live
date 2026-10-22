import '../utils/AppColors.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/Person.dart';
import '../utils/Components/CareerUiStyle.dart';
import '../utils/AppBrand.dart';
import 'DrawerHat.dart';
import 'DrawerItem.dart';

class RootDrawerScope extends InheritedWidget {
  const RootDrawerScope({
    super.key,
    required this.openDrawer,
    required super.child,
  });
  final VoidCallback openDrawer;

  static Widget? leading(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RootDrawerScope>();
    if (scope == null) return null;
    return IconButton(
      onPressed: scope.openDrawer,
      tooltip: 'Menu',
      icon: const Icon(Icons.menu),
    );
  }

  @override
  bool updateShouldNotify(RootDrawerScope oldWidget) =>
      oldWidget.openDrawer != openDrawer;
}

class DrawerWidget extends StatelessWidget {
  const DrawerWidget({
    super.key,
    required this.person,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.onChangeCareer,
    required this.onSwapMode,
    required this.version,
    this.onOpenSettings,
  });
  final Person person;
  final List<DrawerEntry> items;
  final String selected;
  final ValueChanged<DrawerItem> onSelect;
  final VoidCallback onChangeCareer, onSwapMode;
  final VoidCallback? onOpenSettings;
  final String version;

  String _title(DrawerItem item) =>
      item.titleKey.contains('.') ? item.titleKey.tr() : item.titleKey;

  Widget _tile(BuildContext context, DrawerItem item) {
    final c = CareerUiColors(context);
    final active = item.id == selected;
    final icon = Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active
            ? c.accent.withValues(alpha: .18)
            : c.accent.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(11),
      ),
      child: item.image == null
          ? Icon(
              item.icon,
              size: 20,
              color: item.id == 'twitter'
                  ? c.text
                  : active
                  ? c.accent
                  : c.muted,
            )
          : Image.asset(item.image!, width: 20, height: 20),
    );
    if (item.children.isNotEmpty) {
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: icon,
          title: Text(
            _title(item),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          iconColor: c.accent,
          collapsedIconColor: c.muted,
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          childrenPadding: const EdgeInsets.only(left: 18),
          children: [for (final child in item.children) _tile(context, child)],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: active ? c.accent.withValues(alpha: .12) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: active ? c.accent.withValues(alpha: .3) : Colors.transparent,
          ),
        ),
        child: ListTile(
          key: ValueKey('menu-${item.id}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: icon,
          minLeadingWidth: 36,
          horizontalTitleGap: 12,
          title: Text(
            _title(item),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: 1.3,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? c.accent : c.text,
            ),
          ),
          trailing: active
              ? Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
          selected: active,
          onTap: () => onSelect(item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = CareerUiColors(context);
    final entries = <Widget>[];
    var group = 0;
    Widget label(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 9),
      child: Text(
        title,
        style: TextStyle(
          color: c.muted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.7,
        ),
      ),
    );
    entries.add(label('NO DIA A DIA'));
    for (final entry in items) {
      if (entry is DrawerItem) {
        entries.add(_tile(context, entry));
      } else {
        group++;
        entries.add(
          label(
            group == 1 && person.category == PersonCategory.manager
                ? 'EVOLUÇÃO DA CARREIRA'
                : 'MAIS DA CARREIRA',
          ),
        );
      }
    }
    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(0, 420) * .86,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  DrawerHat(person: person, onChangeCareer: onChangeCareer),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: entries,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              padding: const EdgeInsets.all(12),
              decoration: c.surface(radius: 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (onOpenSettings != null) ...[
                        IconButton(
                          onPressed: onOpenSettings,
                          tooltip: 'settings.settings'.tr(),
                          icon: Icon(
                            Icons.settings_outlined,
                            color: c.muted,
                            size: 22,
                          ),
                        ),
                        Container(width: 1, height: 24, color: c.line),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: TextButton.icon(
                          onPressed: onSwapMode,
                          style: TextButton.styleFrom(
                            foregroundColor: c.accent,
                          ),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                          label: Text(
                            'rootPage.swapMode'.tr(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.logoBackdrop,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Image.asset(
                      AppBrand.horizontalAsset,
                      width: 180,
                      height: 42,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${AppBrand.name} · v$version',
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 10,
                      letterSpacing: .6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
