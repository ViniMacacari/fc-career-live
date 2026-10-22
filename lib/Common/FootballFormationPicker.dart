import 'package:flutter/material.dart';

import '../utils/FootballFormations.dart';

Future<String?> showFootballFormationPicker(
  BuildContext context,
  String current,
) async {
  final selected = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      var query = '';
      return StatefulBuilder(
        builder: (context, update) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SizedBox(
            height:
                (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom) *
                .8,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                children: [
                  const Text(
                    'Escolher formação',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    autocorrect: false,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar formação',
                    ),
                    onChanged: (text) =>
                        update(() => query = text.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final label in footballFormations.keys.where(
                          (label) => label.toLowerCase().contains(query),
                        ))
                          ListTile(
                            title: Text(label),
                            leading: const Icon(Icons.sports_soccer_rounded),
                            trailing: current == label
                                ? const Icon(Icons.check_circle_rounded)
                                : null,
                            onTap: () => Navigator.pop(context, label),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const ValueKey('custom-formation'),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Montar outra formação'),
                    onPressed: () => Navigator.pop(context, 'custom'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  if (selected != 'custom' || !context.mounted) return selected;
  final form = GlobalKey<FormState>();
  var value = current.split(' ').first;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Formação personalizada'),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Digite as linhas da defesa para o ataque, somando 10 jogadores. O goleiro é incluído.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                initialValue: value,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Ex.: 4-2-3-1'),
                onChanged: (text) => value = text,
                validator: (text) => customFootballFormation(text ?? '') == null
                    ? 'As linhas precisam somar 10 jogadores.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(
                context,
                value.trim().replaceAll('–', '-').replaceAll(' ', ''),
              );
            }
          },
          child: const Text('Aplicar'),
        ),
      ],
    ),
  );
}
