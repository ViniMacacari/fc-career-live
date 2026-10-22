import '../../utils/AppColors.dart';
import '../../utils/themes.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../Twitter/TwitterGenerationService.dart';
import '../../models/Person.dart';
import '../../models/PressConference.dart';
import '../../utils/SqlService.dart';
import '../../utils/ai/AIModelService.dart';
import '../../utils/ai/PressConferenceService.dart';

class PressConferencePage extends StatefulWidget {
  const PressConferencePage({
    super.key,
    required this.person,
    required this.fixtureId,
    this.publishOnFinish = true,
  });
  final Person person;
  final String fixtureId;
  final bool publishOnFinish;

  @override
  State<PressConferencePage> createState() => _PressConferencePageState();
}

class _PressConferencePageState extends State<PressConferencePage> {
  Map<String, Object?>? _fixture;
  PressConference? _conference;
  final _answers = <TextEditingController>[];
  bool _loading = true, _generating = false, _saving = false, _aiReady = false;
  bool _share = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _answers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final fixture = await SqlService.instance.getFixture(
      PersonCategory.manager,
      widget.person.id,
      widget.fixtureId,
    );
    final conference = PressConference.decode(fixture?['pressConference']);
    var ready = false;
    try {
      ready = await AIModelService.isReady();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _fixture = fixture;
      _aiReady = ready;
      _loading = false;
      _show(conference);
    });
    if (fixture != null && ready && (conference?.questions.isEmpty ?? true)) {
      await _generate();
    }
  }

  void _show(PressConference? conference) {
    for (final controller in _answers) {
      controller.dispose();
    }
    _answers
      ..clear()
      ..addAll([
        for (final q in conference?.questions ?? const <PressQuestion>[])
          TextEditingController(text: q.answer),
      ]);
    _conference = conference;
    if (conference != null && conference.done) _share = conference.shared;
  }

  Future<void> _generate() async {
    final fixture = _fixture;
    if (fixture == null) return;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final started = await PressConferenceService.start(
        widget.person,
        fixture,
      );
      await SqlService.instance.savePressConference(
        widget.person.id,
        widget.fixtureId,
        started,
      );
      if (mounted) setState(() => _show(started));
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException ? error.message : '$error',
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _regenerate() async {
    final done = _conference?.done == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(done ? 'Gerar nova coletiva?' : 'Gerar outras perguntas?'),
        content: Text(
          done
              ? 'Os jornalistas fazem perguntas novas e você responde de novo. '
                    'As perguntas e respostas atuais são substituídas; os posts '
                    'que já estão no X continuam no feed.'
              : 'Os jornalistas fazem perguntas novas e as respostas escritas '
                    'são descartadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gerar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _generate();
  }

  PressConference _withAnswers(PressConferenceStatus status, {bool? shared}) {
    final conference = _conference!;
    for (var i = 0; i < conference.questions.length; i++) {
      conference.questions[i].answer = _answers[i].text.trim();
    }
    return conference.copyWith(status: status, shared: shared);
  }

  Future<void> _saveDraft() async {
    final conference = _conference;
    if (conference == null || conference.done || conference.questions.isEmpty) {
      return;
    }
    await SqlService.instance.savePressConference(
      widget.person.id,
      widget.fixtureId,
      _withAnswers(PressConferenceStatus.started),
    );
  }

  Future<void> _finish() async {
    if (_answers.every((a) => a.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Responda pelo menos uma pergunta.')),
      );
      return;
    }
    setState(() => _saving = true);
    final done = _withAnswers(PressConferenceStatus.done, shared: _share);
    try {
      await SqlService.instance.savePressConference(
        widget.person.id,
        widget.fixtureId,
        done,
      );
      if (done.shared && widget.publishOnFinish) {
        await TwitterGenerationService.instance.sharePressConference(
          widget.person,
          widget.fixtureId,
        );
      }
      _conference = done;
      if (mounted) Navigator.pop(context, done);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar a coletiva: $error')),
        );
      }
    }
  }

  Future<void> _shareLater() async {
    final shared = _conference!.copyWith(shared: true);
    setState(() => _saving = true);
    await SqlService.instance.savePressConference(
      widget.person.id,
      widget.fixtureId,
      shared,
    );
    await TwitterGenerationService.instance.sharePressConference(
      widget.person,
      widget.fixtureId,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _show(shared);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coletiva enviada. As reações aparecem no X.'),
      ),
    );
  }

  Widget _header() {
    final conference = _conference;
    final date = DateTime.tryParse('${_fixture?['date']}');
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.of(context).panel,
              shape: BoxShape.circle,
            ),
            child: Icon(
              TablerIcons.microphone,
              color: AppColors.of(context).accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conference?.headline ?? 'Coletiva pós-jogo',
                  style: TextStyle(
                    color: AppColors.of(context).text,
                    fontSize: 16,
                  ),
                ),
                if (date != null)
                  Text(
                    DateFormat('dd/MM/yyyy').format(date),
                    style: TextStyle(
                      color: AppColors.of(context).muted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _question(int index, PressQuestion question, {required bool open}) {
    final reporter = [
      question.reporter,
      question.outlet,
    ].where((part) => part.isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.of(context).panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.of(context).line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${index + 1}. ${reporter.isEmpty ? 'Jornalista' : reporter}',
            style: TextStyle(color: AppColors.of(context).muted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            question.question,
            style: TextStyle(
              color: AppColors.of(context).text,
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (open)
            TextField(
              controller: _answers[index],
              minLines: 3,
              maxLines: null,
              maxLength: 600,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: AppColors.of(context).text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Sua resposta (pode deixar sem responder)',
                hintStyle: TextStyle(
                  color: AppColors.of(context).muted,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: AppColors.of(context).field,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.of(context).field,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                question.answer.trim().isEmpty
                    ? 'Sem resposta.'
                    : question.answer.trim(),
                style: TextStyle(
                  color: question.answer.trim().isEmpty
                      ? AppColors.of(context).muted
                      : AppColors.of(context).text,
                  fontSize: 14,
                  height: 1.35,
                  fontStyle: question.answer.trim().isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _message(IconData icon, String text, {Widget? action}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.of(context).muted),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.of(context).text),
          ),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    ),
  );

  Widget _failure(String error) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
    decoration: BoxDecoration(
      color: AppColors.negativeTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            TablerIcons.alertCircle,
            size: 20,
            color: AppColors.of(context).text,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Não foi possível gerar novas perguntas; as anteriores foram '
            'mantidas.\n$error',
            style: TextStyle(
              color: AppColors.of(context).text,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Fechar aviso',
          onPressed: () => setState(() => _error = null),
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    ),
  );

  Widget _body() {
    final conference = _conference;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_fixture == null) {
      return _message(TablerIcons.alertCircle, 'A partida foi removida.');
    }
    if (_generating) {
      return _message(
        TablerIcons.microphone,
        'Os jornalistas estão preparando as perguntas…',
        action: const CircularProgressIndicator(),
      );
    }
    if (conference == null || conference.questions.isEmpty) {
      if (!_aiReady) {
        return _message(
          TablerIcons.robotOff,
          'Configure a chave e o modelo em Configurações > Inteligência '
          'artificial para participar da coletiva.',
        );
      }
      return _message(
        TablerIcons.alertCircle,
        _error ?? 'Não foi possível preparar as perguntas.',
        action: FilledButton(
          onPressed: _generate,
          child: const Text('Tentar novamente'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _header(),
        if (_error != null) _failure(_error!),
        for (final (index, question) in conference.questions.indexed)
          _question(index, question, open: !conference.done),
        if (!conference.done)
          SwitchListTile(
            value: _share,
            onChanged: (value) => setState(() => _share = value),
            title: Text(
              'Enviar ao X',
              style: TextStyle(color: AppColors.of(context).text),
            ),
            subtitle: Text(
              'Jornais, páginas e torcedores repercutem suas respostas.',
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 12,
              ),
            ),
          )
        else if (conference.shared)
          ListTile(
            leading: Icon(
              TablerIcons.brandX,
              color: AppColors.of(context).accent,
            ),
            title: Text(
              'Enviada ao X',
              style: TextStyle(color: AppColors.of(context).text),
            ),
            subtitle: Text(
              'As respostas fazem parte do assunto da partida no feed.',
              style: TextStyle(
                color: AppColors.of(context).muted,
                fontSize: 12,
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _saving ? null : _shareLater,
            icon: const Icon(TablerIcons.brandX),
            label: const Text('Enviar ao X'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final conference = _conference;
    final open =
        conference != null &&
        !conference.done &&
        conference.questions.isNotEmpty &&
        !_generating;
    return Theme(
      data: careerDetailTheme(context),
      child: PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _saveDraft();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Coletiva de imprensa'),
            actions: [
              if (_aiReady &&
                  !_generating &&
                  !_saving &&
                  (conference?.questions.isNotEmpty ?? false))
                IconButton(
                  tooltip: conference!.done
                      ? 'Gerar nova coletiva'
                      : 'Gerar outras perguntas',
                  onPressed: _regenerate,
                  icon: const Icon(TablerIcons.refresh),
                ),
            ],
          ),
          body: _body(),
          bottomNavigationBar: open
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _finish,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(TablerIcons.check),
                      label: const Text('Encerrar coletiva'),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
