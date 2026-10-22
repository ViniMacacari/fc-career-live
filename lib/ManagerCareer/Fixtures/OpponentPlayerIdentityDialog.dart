import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../models/Person.dart';
import '../../utils/Components/PlayerAvatar.dart';
import '../../utils/databaseUtils.dart';

typedef OpponentPlayerIdentity = ({String name, String? photo});

class OpponentPlayerIdentityDialog extends StatefulWidget {
  const OpponentPlayerIdentityDialog({
    super.key,
    required this.person,
    required this.playerId,
    this.name = '',
    this.photo,
  });
  final Person person;
  final String playerId, name;
  final String? photo;

  @override
  State<OpponentPlayerIdentityDialog> createState() =>
      _OpponentPlayerIdentityDialogState();
}

class _OpponentPlayerIdentityDialogState
    extends State<OpponentPlayerIdentityDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.name);
  late String? _photo = widget.photo;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file != null && mounted) setState(() => _photo = file.path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir a foto: $error')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      var photo = _photo;
      if (photo != null &&
          photo != widget.photo &&
          photo != CustomImageFiles.absolute(widget.photo)) {
        photo = await CustomImageFiles.store(
          photo,
          'faces',
          '${widget.person.id}/opponents/${widget.playerId}/${const Uuid().v4()}',
        );
      }
      if (mounted) {
        Navigator.pop<OpponentPlayerIdentity>(context, (
          name: _name.text.trim(),
          photo: photo,
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível salvar o jogador: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('players.player'.tr()),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('opponent-player-name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'common.name'.tr()),
              validator: (value) =>
                  value?.trim().isNotEmpty == true ? null : 'Informe o nome.',
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                PlayerAvatar(
                  fifaVersion: widget.person.fifaVersion,
                  customAvatarFilePath: _photo,
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('opponent-player-photo'),
                    onPressed: _saving ? null : _pickPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text('Foto'),
                  ),
                ),
                if (_photo != null)
                  IconButton(
                    tooltip: 'Remover foto',
                    onPressed: _saving
                        ? null
                        : () => setState(() => _photo = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: Text('common.cancel'.tr()),
      ),
      FilledButton(
        key: const ValueKey('save-opponent-player'),
        onPressed: _saving ? null : _save,
        child: Text('common.save'.tr()),
      ),
    ],
  );
}
