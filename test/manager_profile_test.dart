import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcmanager/models/ManagerProfile.dart';
import 'package:mcmanager/RootPage/managerCareerMenuItems.dart';
import 'package:mcmanager/RootPage/DrawerItem.dart';
import 'package:mcmanager/models/Person.dart';

void main() {
  test('legacy careers have a neutral coach identity until configured', () {
    for (final value in [null, '', 'invalid', '[]', '{"name":123}']) {
      final profile = ManagerProfile.decode(value);
      expect(profile.displayName, 'Técnico');
      expect(profile.context, {'name': 'Técnico'});
    }
  });

  test('saved personal information supplies the AI identity and context', () {
    const profile = ManagerProfile(
      name: ' João Silva ',
      nationality: 'Brasileiro',
      birthdate: '12/05/1980',
      style: 'Pressão alta',
      biography: 'Ex-jogador.',
    );
    final restored = ManagerProfile.decode(jsonEncode(profile.toMap()));
    expect(restored.displayName, 'João Silva');
    expect(restored.context, {
      'name': 'João Silva',
      'nationality': 'Brasileiro',
      'birthdate': '12/05/1980',
      'style': 'Pressão alta',
      'biography': 'Ex-jogador.',
    });
    expect(const ManagerProfile(name: 'João').context, {'name': 'João'});
  });

  test('manager menu exposes the personal coach profile', () {
    final person = Person(
      id: 'career',
      name: 'Minha carreira no Milan',
      category: PersonCategory.manager,
      fifaVersion: 'FC26',
      leagueId: '1',
      teamId: '1',
      nationalityId: '54',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final item = managerCareerMenuItems(person)
        .whereType<DrawerItem>()
        .singleWhere((item) => item.id == 'myManager');
    expect(item.titleKey, 'Meu técnico');
    expect(item.page, isNotNull);
  });
}
