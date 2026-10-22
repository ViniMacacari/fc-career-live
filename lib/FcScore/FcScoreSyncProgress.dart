import 'package:flutter/material.dart';

class FcScoreSyncProgress extends ChangeNotifier {
  double value = 0;
  String status = 'Conectando ao PC';
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void advance(double fraction, String message) {
    if (_disposed) return;
    value = fraction.clamp(value, 1);
    status = message;
    notifyListeners();
  }
}

class FcScoreSyncProgressView extends StatelessWidget {
  const FcScoreSyncProgressView({
    super.key,
    required this.progress,
    this.complete = false,
    this.error,
    this.summary,
    this.onClose,
    this.onCustomize,
    this.onReconnect,
  });
  final FcScoreSyncProgress progress;
  final bool complete;
  final String? error, summary;
  final VoidCallback? onClose, onCustomize, onReconnect;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    builder: (context, _) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            complete ? 'Carreira atualizada' : 'Atualizar carreira',
            style: Theme.of(context).dialogTheme.titleTextStyle
                ?.copyWith(fontFamily: 'Manrope'),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              key: const Key('fc-sync-progress'),
              value: progress.value,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            error ??
                (complete
                    ? summary ?? 'Atualização concluída.'
                    : progress.status),
            style: Theme.of(context).dialogTheme.contentTextStyle
                ?.copyWith(fontFamily: 'Manrope'),
          ),
          const SizedBox(height: 20),
          if (onCustomize != null)
            TextButton(
              onPressed: onCustomize,
              child: const Text('Personalizar atualização'),
            ),
          if (onReconnect != null)
            TextButton(
              onPressed: onReconnect,
              child: const Text('Alterar conexão'),
            ),
          if (onClose != null)
            FilledButton(
              onPressed: onClose,
              child: Text(complete || error != null ? 'Fechar' : 'Cancelar'),
            ),
        ],
      ),
    ),
  );
}
