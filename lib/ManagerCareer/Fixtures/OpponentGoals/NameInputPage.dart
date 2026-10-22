import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class NameInputPage extends StatefulWidget {
  const NameInputPage({super.key, this.initialValue});
  final String? initialValue;

  @override
  State<NameInputPage> createState() => _NameInputPageState();
}

class _NameInputPageState extends State<NameInputPage> {
  late final _name = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('players.player'.tr())),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: 'common.name'.tr()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _name.text.trim()),
          child: Text('common.save'.tr()),
        ),
      ],
    ),
  );
}
