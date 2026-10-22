import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceRecognizerModal extends StatefulWidget {
  const VoiceRecognizerModal({super.key});

  @override
  State<VoiceRecognizerModal> createState() => _VoiceRecognizerModalState();
}

class _VoiceRecognizerModalState extends State<VoiceRecognizerModal> {
  final _speech = SpeechToText();
  final _text = TextEditingController();
  bool _busy = false, _listening = false;
  String? _error;

  @override
  void dispose() {
    _speech.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (mounted) setState(() => _listening = status == 'listening');
        },
        onError: (_) {
          if (mounted) {
            setState(() {
              _listening = false;
              _error = context.locale.languageCode == 'pt'
                  ? 'Não foi possível reconhecer a fala. Você pode editar o texto.'
                  : 'Speech could not be recognized. You can edit the text.';
            });
          }
        },
      );
      if (!mounted) return;
      if (!available) {
        final permitted = await _speech.hasPermission;
        if (!mounted) return;
        setState(
          () => _error = permitted
              ? (context.locale.languageCode == 'pt'
                    ? 'Reconhecimento de voz indisponível neste dispositivo.'
                    : 'Speech recognition is unavailable on this device.')
              : 'fixtures.voiceRecognition.microphonePermissionDescription'
                    .tr(),
        );
        return;
      }
      final previous = _text.text.trim();
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: context.locale.toString(),
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (result) {
          if (!mounted) return;
          final recognized = [
            if (previous.isNotEmpty) previous,
            result.recognizedWords,
          ].join(' ');
          _text.value = TextEditingValue(
            text: recognized,
            selection: TextSelection.collapsed(offset: recognized.length),
          );
        },
      );
      if (mounted) setState(() => _listening = _speech.isListening);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'fixtures.voiceRecognition.microphonePermissionDescription'.tr(),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'fixtures.voiceRecognition.help.primaryTitle'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text('fixtures.voiceRecognition.help.statDescription'.tr()),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(labelText: 'common.content'.tr()),
              readOnly: _listening,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _toggle,
                  icon: Icon(_listening ? Icons.stop : Icons.mic_none),
                  label: Text(
                    _listening
                        ? (context.locale.languageCode == 'pt'
                              ? 'Parar'
                              : 'Stop')
                        : 'fixtures.voiceRecognition.help.primaryTitle'.tr(),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _listening || _busy
                      ? null
                      : () => Navigator.pop(context, _text.text),
                  child: Text('common.apply'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
