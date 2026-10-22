import 'package:flutter/material.dart';

sealed class DrawerEntry {
  const DrawerEntry();
}

class DrawerSeparator extends DrawerEntry {
  const DrawerSeparator();
}

class DrawerItem extends DrawerEntry {
  const DrawerItem({
    required this.id,
    required this.titleKey,
    required this.icon,
    this.page,
    this.onPress,
    this.image,
    this.children = const [],
  });
  final String id, titleKey;
  final IconData icon;
  final WidgetBuilder? page;
  final void Function(BuildContext context)? onPress;
  final String? image;
  final List<DrawerItem> children;
}
