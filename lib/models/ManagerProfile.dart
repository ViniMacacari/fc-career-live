import 'dart:convert';

class ManagerProfile {
  const ManagerProfile({
    this.name = '',
    this.nationality = '',
    this.birthdate = '',
    this.style = '',
    this.biography = '',
  });

  final String name, nationality, birthdate, style, biography;
  String get displayName => name.trim().isEmpty ? 'Técnico' : name.trim();

  Map<String, Object?> toMap() => {
    'name': name.trim(),
    'nationality': nationality.trim(),
    'birthdate': birthdate.trim(),
    'style': style.trim(),
    'biography': biography.trim(),
  };

  Map<String, Object?> get context => {
    'name': displayName,
    for (final entry in toMap().entries)
      if (entry.key != 'name' && entry.value != '') entry.key: entry.value,
  };

  static ManagerProfile decode(Object? value) {
    if (value is! String || value.isEmpty) return const ManagerProfile();
    try {
      final row = jsonDecode(value) as Map<String, dynamic>;
      return ManagerProfile(
        name: row['name'] as String? ?? '',
        nationality: row['nationality'] as String? ?? '',
        birthdate: row['birthdate'] as String? ?? '',
        style: row['style'] as String? ?? '',
        biography: row['biography'] as String? ?? '',
      );
    } catch (_) {
      return const ManagerProfile();
    }
  }
}
