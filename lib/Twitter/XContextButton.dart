import 'package:flutter/material.dart';

import 'TwitterStore.dart';
import 'TwitterStyle.dart';

class XContextButton extends StatefulWidget {
  const XContextButton({
    super.key,
    required this.personId,
    this.store,
    this.showPanel = false,
  });
  final String personId;
  final TwitterStore? store;
  final bool showPanel;
  @override
  State<XContextButton> createState() => _XContextButtonState();
}

class _XContextButtonState extends State<XContextButton> {
  TwitterStore get store => widget.store ?? TwitterStore.instance;
  String text = '';
  String? error;
  bool _busy = false;
  int _loadRequest = 0;
  @override
  void initState() {
    super.initState();
    store.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    store.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    final personId = widget.personId, source = store;
    try {
      final value = await source.customContext(personId);
      if (mounted &&
          request == _loadRequest &&
          personId == widget.personId &&
          source == store) {
        setState(() {
          text = value;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && request == _loadRequest) {
        setState(() => error = 'Não foi possível ler o contexto salvo.');
      }
    }
  }

  @override
  void didUpdateWidget(covariant XContextButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId != widget.personId ||
        oldWidget.store != widget.store) {
      (oldWidget.store ?? TwitterStore.instance).removeListener(_load);
      store.addListener(_load);
      text = '';
      error = null;
      _load();
    }
  }

  Future<void> _edit() async {
    final personId = widget.personId, source = store;
    String initial;
    try {
      initial = await source.customContext(personId);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'Não foi possível ler o contexto salvo. Tente novamente.',
        );
      }
      return;
    }
    if (!mounted || personId != widget.personId || source != store) return;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => XTheme(builder: (_) => _ContextDialog(initial: initial)),
    );
    if (result == null) return;
    await _save(personId, source, result);
  }

  Future<void> _save(
    String personId,
    TwitterStore source,
    String result,
  ) async {
    if (mounted) setState(() => _busy = true);
    try {
      await source.saveCustomContext(personId, result);
      if (mounted && personId == widget.personId && source == store) {
        ++_loadRequest;
        setState(() {
          text = result.trim();
          error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.trim().isEmpty
                  ? 'Contexto removido.'
                  : 'Contexto salvo para as próximas gerações.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível salvar o contexto. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showPanel) {
      final colors = xColors(context);
      return Container(
        key: const ValueKey('x-ai-context-panel'),
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contexto da IA',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              error ??
                  (text.isEmpty
                      ? 'Adicione informações para orientar os próximos posts e respostas.'
                      : text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: const ValueKey('x-ai-context-edit'),
                  onPressed: _busy ? null : _edit,
                  icon: Icon(
                    text.isEmpty ? Icons.add : Icons.edit_outlined,
                    size: 16,
                  ),
                  label: Text(text.isEmpty ? 'Adicionar contexto' : 'Editar'),
                ),
                if (text.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('x-ai-context-clear'),
                    onPressed: _busy
                        ? null
                        : () => _save(widget.personId, store, ''),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Remover'),
                  ),
                if (error != null)
                  TextButton(
                    onPressed: _load,
                    child: const Text('Tentar novamente'),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    return IconButton(
      key: const ValueKey('x-ai-context'),
      tooltip: text.isEmpty
          ? 'Adicionar contexto para a IA'
          : 'Contexto ativo · editar ou remover',
      onPressed: _busy ? null : _edit,
      icon: Badge(
        isLabelVisible: text.isNotEmpty,
        backgroundColor: xColors(context).accent,
        child: const Icon(Icons.edit_note_rounded),
      ),
    );
  }
}

class _ContextDialog extends StatefulWidget {
  const _ContextDialog({required this.initial});
  final String initial;
  @override
  State<_ContextDialog> createState() => _ContextDialogState();
}

class _ContextDialogState extends State<_ContextDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => XAlertDialog(
    title: const Text('Contexto para a IA'),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Conte o que a IA precisa saber: uma conquista antecipada, a despedida de um ídolo ou o último jogo da temporada.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('x-ai-context-input'),
              controller: controller,
              minLines: 4,
              maxLines: 8,
              maxLength: 4000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Contexto personalizado',
                alignLabelWithHint: true,
                hintText: 'Ex.: Já garantimos o título na rodada anterior. Hoje é o último jogo da temporada.',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Vale para esta carreira até você editar ou remover. Ajuda nos novos posts e respostas; não publica nada nem altera os registros da carreira.',
              style: TextStyle(
                color: xColors(context).muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.initial.isNotEmpty)
        TextButton(
          key: const ValueKey('x-ai-context-remove'),
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Remover contexto'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const ValueKey('x-ai-context-save'),
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: const Text('Salvar'),
      ),
    ],
  );
}
