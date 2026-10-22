import 'package:flutter/material.dart';

import '../../utils/CompetitionTrophies.dart';
import '../../utils/databaseUtils.dart';
import '../../utils/Components/TeamLogo.dart';
import 'CustomConfigurationComponents.dart';

class CompetitionTrophyDraft extends ChangeNotifier {
  CompetitionTrophyDraft({String? competitionId, String? version}) {
    ready = competitionId == null || version == null
        ? Future.value()
        : _load(competitionId, version);
  }
  final name = TextEditingController(), url = TextEditingController();
  String? imagePath, _previousPath;
  bool loading = false, _disposed = false;
  Object? error;
  late final Future<void> ready;

  Future<void> _load(String id, String version) async {
    loading = true;
    try {
      final trophy = await CompetitionTrophies.find(id, version);
      if (_disposed) return;
      name.text = trophy?.name ?? '';
      url.text = trophy?.imageUrl ?? '';
      imagePath = _previousPath = trophy?.imagePath;
    } catch (e) {
      error = e;
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  void selectImage(String? path) {
    imagePath = path;
    notifyListeners();
  }

  Future<CompetitionTrophy?> prepare(
    String id,
    String version,
    String competitionName,
  ) async {
    await ready;
    if (error != null) {
      throw StateError('Não foi possível carregar o troféu: $error');
    }
    if (name.text.trim().isEmpty &&
        url.text.trim().isEmpty &&
        imagePath == null) {
      return null;
    }
    final path = await CustomImageFiles.resolveForSave(
      previous: _previousPath,
      selected: imagePath,
      folder: CustomImageFiles.trophies,
      id: id.replaceAll(':', '_'),
    );
    return CompetitionTrophy(
      competitionId: id,
      version: version,
      name: name.text.trim().isEmpty ? competitionName : name.text.trim(),
      imagePath: path,
      imageUrl: url.text.trim().isEmpty ? null : url.text.trim(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    name.dispose();
    url.dispose();
    super.dispose();
  }
}

class CompetitionTrophyEditor extends StatelessWidget {
  const CompetitionTrophyEditor({super.key, required this.draft});
  final CompetitionTrophyDraft draft;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) => Card(
      margin: const EdgeInsets.only(top: 20),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: TeamLogo(
          imagePath: draft.imagePath,
          imageUrl: draft.url.text,
          fallbackIcon: Icons.emoji_events_outlined,
          width: 36,
          height: 36,
        ),
        title: const Text('Troféu da competição'),
        subtitle: Text(
          draft.loading
              ? 'Carregando…'
              : 'Nome e imagem da taça conquistada neste campeonato',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        children: draft.loading
            ? [const LinearProgressIndicator()]
            : [
                if (draft.error != null)
                  const Text(
                    'Não foi possível carregar o troféu. Reabra a competição para tentar novamente.',
                  ),
                TextField(
                  controller: draft.name,
                  decoration: const InputDecoration(
                    labelText: 'Nome do troféu (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: draft.url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'URL da imagem do troféu (opcional)',
                  ),
                ),
                const SizedBox(height: 8),
                CustomImagePicker(
                  path: draft.imagePath,
                  onChanged: draft.selectImage,
                ),
              ],
      ),
    ),
  );
}
