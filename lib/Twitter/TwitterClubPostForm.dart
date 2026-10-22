import '../utils/AppColors.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'TwitterModels.dart';
import 'TwitterStyle.dart';

class TwitterClubPostForm extends StatefulWidget {
  const TwitterClubPostForm({
    super.key,
    required this.club,
    required this.version,
    required this.initialDate,
    required this.onSubmit,
  });
  final TwitterAccount club;
  final String version;
  final DateTime initialDate;
  final void Function(String context, DateTime date) onSubmit;

  @override
  State<TwitterClubPostForm> createState() => _TwitterClubPostFormState();
}

class _TwitterClubPostFormState extends State<TwitterClubPostForm>
    with AutomaticKeepAliveClientMixin {
  final _context = TextEditingController();
  late DateTime _date = DateUtils.dateOnly(widget.initialDate);
  @override
  bool get wantKeepAlive => true;
  @override
  void dispose() {
    _context.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TwitterAvatar(
                account: widget.club,
                version: widget.version,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.club.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          Icons.verified,
                          color: AppColors.of(context).accent,
                          size: 18,
                        ),
                      ],
                    ),
                    Text(
                      '@${widget.club.handle}',
                      style: TextStyle(color: AppColors.of(context).muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'O que o clube vai anunciar?',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Conte os fatos e a IA escreve um post de até 280 caracteres '
            'na voz do clube. Ele será publicado no feed pela conta oficial acima.',
            style: TextStyle(color: AppColors.of(context).muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(1900),
                lastDate: DateTime(2200, 12, 31),
              );
              if (selected != null && mounted) setState(() => _date = selected);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Dia da publicação',
                suffixIcon: Icon(Icons.calendar_month_outlined),
                helperText: 'O contexto da carreira considera esse dia.',
              ),
              child: Text(DateFormat('dd/MM/yyyy').format(_date)),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _context,
            minLines: 4,
            maxLines: 7,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Contexto do anúncio',
              alignLabelWithHint: true,
              hintText:
                  'Ex.: renovamos com o capitão por mais duas temporadas. '
                  'Quero um anúncio comemorando a permanência dele.',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _context.text.trim().isEmpty
                ? null
                : () => widget.onSubmit(_context.text.trim(), _date),
            icon: const Icon(Icons.auto_awesome_outlined, size: 19),
            label: const Text('Gerar e publicar pelo clube'),
          ),
        ],
      ),
    );
  }
}
