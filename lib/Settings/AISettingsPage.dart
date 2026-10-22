import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/SecureStorageService.dart';
import '../utils/Components/CareerPageWidgets.dart';
import '../utils/ai/AIModelService.dart';
import '../Twitter/TwitterGenerationService.dart';

class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});
  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
  final _key = TextEditingController(), _model = TextEditingController();
  final _instructions = TextEditingController(),
      _tokens = TextEditingController();
  late final _ready = _load();
  String _language = 'Português brasileiro';
  bool _hasKey = false, _busy = false, _obscure = true;
  Future<void> _load() async {
    final config = await AIConfiguration.load();
    _model.text = config.model;
    _instructions.text = config.instructions;
    _tokens.text = '${config.maxTokens}';
    _language = config.language;
    _hasKey =
        (await SecureStorageService.readOpenRouterApiKey())?.isNotEmpty == true;
  }

  @override
  void dispose() {
    for (final c in [_key, _model, _instructions, _tokens]) {
      c.dispose();
    }
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<bool> _save({bool notify = true}) async {
    final limit = int.tryParse(_tokens.text);
    if (_model.text.trim().isEmpty ||
        limit == null ||
        limit < 512 ||
        limit > 24000) {
      _message('Informe o modelo e um limite entre 512 e 24000 tokens.');
      return false;
    }
    setState(() => _busy = true);
    try {
      if (_key.text.trim().isNotEmpty) {
        await SecureStorageService.writeOpenRouterApiKey(_key.text);
        _hasKey = true;
        _key.clear();
      }
      await AIConfiguration(
        model: _model.text.trim(),
        language: _language,
        instructions: _instructions.text.trim(),
        maxTokens: limit,
      ).save();
      if (notify) _message('Configuração de IA salva.');
      return true;
    } catch (error) {
      _message('Não foi possível salvar a configuração de IA.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (!await _save(notify: false) || !mounted) return;
    setState(() => _busy = true);
    try {
      await AIModelService.complete(
        'Responda somente OK.',
        'Teste de conexão.',
        maxTokens: 64,
      );
      _message('Conexão e modelo funcionando.');
    } catch (error) {
      _message(TwitterGenerationService.errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickModel() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ModelPicker()),
    );
    if (mounted && result != null) setState(() => _model.text = result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inteligência artificial')),
    body: FutureBuilder<void>(
      future: _ready,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Falha ao ler as configurações de IA.'),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const CareerPageHeader(
              title: 'Criatividade na carreira',
              eyebrow: 'Inteligência artificial',
              subtitle: 'Configure o modelo e o estilo dos posts, respostas e entrevistas.',
              icon: Icons.auto_awesome_outlined,
            ),
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Chave de API',
                hintText: _hasKey
                    ? 'Chave salva. Preencha para substituir.'
                    : 'Cole sua chave do OpenRouter',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://openrouter.ai/settings/keys'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Obter chave'),
                ),
                const Spacer(),
                if (_hasKey)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            await SecureStorageService.deleteOpenRouterApiKey();
                            if (mounted) {
                              setState(() {
                                _hasKey = false;
                                _key.clear();
                              });
                            }
                          },
                    child: const Text('Remover chave'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'ID do modelo',
                hintText: 'provedor/modelo',
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _pickModel,
              icon: const Icon(Icons.search),
              label: const Text('Buscar modelos disponíveis'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _language,
              decoration: const InputDecoration(labelText: 'Idioma dos posts'),
              items: {
                'Português brasileiro',
                'Português',
                'English',
                'Español',
                _language,
              }.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setState(() => _language = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokens,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Limite de tokens por geração',
                helperText:
                    'Posts e respostas são gerados juntos numa chamada.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _instructions,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Estilo adicional (opcional)',
                hintText: 'Ex.: humor, gírias, estilo dos torcedores...',
              ),
            ),
            const Text(
              'A chave fica no armazenamento seguro do aparelho. Preços e limites dependem do modelo selecionado no OpenRouter.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Aguarde...' : 'Salvar configuração'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _test,
              child: const Text('Testar conexão e modelo'),
            ),
          ],
        );
      },
    ),
  );
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker();
  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  Future<List<Map<String, dynamic>>> _models = AIModelService.models();
  String _search = '';
  bool _free = false;
  bool _isFree(Map<String, dynamic> m) {
    final pricing = m['pricing'] as Map? ?? {};
    return double.tryParse(pricing['prompt']?.toString() ?? '') == 0 &&
        double.tryParse(pricing['completion']?.toString() ?? '') == 0;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Selecionar modelo')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar nome ou ID',
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        FilterChip(
          label: const Text('Somente gratuitos'),
          selected: _free,
          onSelected: (v) => setState(() => _free = v),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _models,
            builder: (_, s) {
              if (s.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(TwitterGenerationService.errorText(s.error!)),
                      TextButton(
                        onPressed: () =>
                            setState(() => _models = AIModelService.models()),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                );
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = s.data!
                  .where(
                    (m) =>
                        (!_free || _isFree(m)) &&
                        '${m['id']} ${m['name']}'.toLowerCase().contains(
                          _search,
                        ),
                  )
                  .toList();
              return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final m = rows[i];
                  return ListTile(
                    title: Text(m['name']?.toString() ?? m['id'].toString()),
                    subtitle: Text(
                      '${m['id']}\n${_isFree(m) ? 'Gratuito' : 'Pago'} • Contexto ${m['context_length']} tokens',
                    ),
                    isThreeLine: true,
                    onTap: () => Navigator.pop(context, m['id'].toString()),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
