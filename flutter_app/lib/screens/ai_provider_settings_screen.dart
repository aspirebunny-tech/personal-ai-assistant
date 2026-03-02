import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AiProviderSettingsScreen extends StatefulWidget {
  const AiProviderSettingsScreen({super.key});

  @override
  State<AiProviderSettingsScreen> createState() => _AiProviderSettingsScreenState();
}

class _AiProviderSettingsScreenState extends State<AiProviderSettingsScreen> {
  final List<String> _providers = ['openrouter', 'openai', 'ollama'];

  bool _loading = true;
  bool _saving = false;
  bool _useFallback = true;

  String _primaryProvider = 'openrouter';
  String _primaryModel = '';
  String _primaryBaseUrl = '';
  String _primaryMaskedKey = '';
  final TextEditingController _primaryKeyCtrl = TextEditingController();

  String _fallbackProvider = '';
  String _fallbackModel = '';
  String _fallbackBaseUrl = '';
  String _fallbackMaskedKey = '';
  final TextEditingController _fallbackKeyCtrl = TextEditingController();

  bool _fetchingPrimary = false;
  bool _fetchingFallback = false;
  List<dynamic> _primaryModels = [];
  List<dynamic> _fallbackModels = [];
  String _status = '';
  List<dynamic> _statusChain = [];
  List<dynamic> _configuredChain = [];
  Map<String, dynamic> _providerStatusMap = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _primaryKeyCtrl.dispose();
    _fallbackKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cfgRes = await ApiService.getAiProviderConfig();
    final localCfgRes = await ApiService.getLocalAiProviderConfig();
    final statusRes = await ApiService.getAiStatus();
    if (!mounted) return;

    if (cfgRes['success'] == true) {
      final cfg = Map<String, dynamic>.from(cfgRes['config'] ?? {});
      final p = Map<String, dynamic>.from(cfg['primary'] ?? {});
      final f = Map<String, dynamic>.from(cfg['fallback'] ?? {});
      setState(() {
        _primaryProvider = (p['provider'] ?? 'openrouter').toString();
        _primaryModel = (p['model'] ?? '').toString();
        _primaryBaseUrl = (p['base_url'] ?? '').toString();
        _primaryMaskedKey = (p['api_key'] ?? '').toString();

        _fallbackProvider = (f['provider'] ?? '').toString();
        _fallbackModel = (f['model'] ?? '').toString();
        _fallbackBaseUrl = (f['base_url'] ?? '').toString();
        _fallbackMaskedKey = (f['api_key'] ?? '').toString();

        _useFallback = cfg['use_fallback'] != false;
      });
    } else if (localCfgRes['success'] == true) {
      final cfg = Map<String, dynamic>.from(localCfgRes['config'] ?? {});
      final p = Map<String, dynamic>.from(cfg['primary'] ?? {});
      final f = Map<String, dynamic>.from(cfg['fallback'] ?? {});
      setState(() {
        _primaryProvider = (p['provider'] ?? 'openrouter').toString();
        _primaryModel = (p['model'] ?? '').toString();
        _primaryBaseUrl = (p['base_url'] ?? '').toString();
        _primaryMaskedKey = (p['api_key'] ?? '').toString();

        _fallbackProvider = (f['provider'] ?? '').toString();
        _fallbackModel = (f['model'] ?? '').toString();
        _fallbackBaseUrl = (f['base_url'] ?? '').toString();
        _fallbackMaskedKey = (f['api_key'] ?? '').toString();

        _useFallback = cfg['use_fallback'] != false;
      });
    }

    setState(() {
      _status = (statusRes['message'] ?? '').toString();
      _statusChain = (statusRes['chain'] as List<dynamic>? ?? <dynamic>[]);
      _configuredChain = (statusRes['configured_chain'] as List<dynamic>? ?? <dynamic>[]);
      _providerStatusMap = Map<String, dynamic>.from(statusRes['providers'] ?? {});
      _loading = false;
    });
  }

  Future<void> _fetchModels({required bool primary}) async {
    if (primary) {
      setState(() => _fetchingPrimary = true);
    } else {
      setState(() => _fetchingFallback = true);
    }
    final provider = primary ? _primaryProvider : _fallbackProvider;
    final res = await ApiService.getProviderModels(
      provider: provider,
      slot: primary ? 'primary' : 'fallback',
      apiKey: primary ? _primaryKeyCtrl.text.trim() : _fallbackKeyCtrl.text.trim(),
      baseUrl: primary ? _primaryBaseUrl.trim() : _fallbackBaseUrl.trim(),
    );
    if (!mounted) return;
    if (primary) {
      setState(() {
        _primaryModels = (res['models'] as List<dynamic>? ?? <dynamic>[]);
        _fetchingPrimary = false;
      });
    } else {
      setState(() {
        _fallbackModels = (res['models'] as List<dynamic>? ?? <dynamic>[]);
        _fetchingFallback = false;
      });
    }
    if (res['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model list failed: ${res['error'] ?? 'unknown'}')),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final payload = {
      'primary': {
        'provider': _primaryProvider,
        'api_key': _primaryKeyCtrl.text.trim(),
        'model': _primaryModel,
        'base_url': _primaryBaseUrl.trim(),
      },
      'fallback': {
        'provider': _fallbackProvider,
        'api_key': _fallbackKeyCtrl.text.trim(),
        'model': _fallbackModel,
        'base_url': _fallbackBaseUrl.trim(),
      },
      'use_fallback': _useFallback,
    };
    final localRes = await ApiService.saveAiProviderConfig(payload);
    final statusRes = await ApiService.getAiStatus();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _status = (statusRes['message'] ?? '').toString();
      _statusChain = (statusRes['chain'] as List<dynamic>? ?? <dynamic>[]);
      _configuredChain = (statusRes['configured_chain'] as List<dynamic>? ?? <dynamic>[]);
      _providerStatusMap = Map<String, dynamic>.from(statusRes['providers'] ?? {});
      if (localRes['success'] == true) {
        final cfg = Map<String, dynamic>.from(localRes['config'] ?? payload);
        _primaryMaskedKey = (cfg['primary']?['api_key'] ?? '').toString();
        _fallbackMaskedKey = (cfg['fallback']?['api_key'] ?? '').toString();
        _primaryKeyCtrl.clear();
        _fallbackKeyCtrl.clear();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          localRes['success'] == true
              ? ((localRes['local_only'] == true)
                  ? 'Saved locally (server unreachable)'
                  : 'Provider settings saved')
              : 'Save failed: ${localRes['error']}',
        ),
      ),
    );
  }

  Widget _modelList({
    required List<dynamic> models,
    required void Function(String) onPick,
    required String selected,
  }) {
    if (models.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('No models yet. Tap "Load Models".', style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: models.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF2A2A2A)),
        itemBuilder: (ctx, i) {
          final m = Map<String, dynamic>.from(models[i] as Map);
          final name = (m['model'] ?? '').toString();
          final rate = m['rate_per_1m'];
          final rateText = rate == null ? '-' : '\$${(rate as num).toStringAsFixed(2)}';
          final active = selected == name;
          return ListTile(
            dense: true,
            tileColor: active ? const Color(0x3328A745) : null,
            title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 12)),
            subtitle: Text('Rate / 1M tokens: $rateText', style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 11)),
            trailing: active
                ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16)
                : const Icon(Icons.chevron_right, color: Colors.grey, size: 16),
            onTap: () => onPick(name),
          );
        },
      ),
    );
  }

  Widget _providerDropdown({
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value.isEmpty ? null : value,
      dropdownColor: const Color(0xFF1A1A1A),
      decoration: const InputDecoration(
        labelText: 'Provider',
        border: OutlineInputBorder(),
      ),
      items: _providers
          .map((p) => DropdownMenuItem<String>(value: p, child: Text(p)))
          .toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Provider Settings'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8884A)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2E2E2E)),
                  ),
                  child: Text(_status.isEmpty ? 'Status loading...' : _status, style: const TextStyle(color: Color(0xFFE0E0E0))),
                ),
                if (_statusChain.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2E2E2E)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Chain',
                          style: TextStyle(
                            color: Color(0xFFE8884A),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                          ..._statusChain.map((c) {
                            final m = Map<String, dynamic>.from(c as Map);
                            final label = m['fallback'] == true ? 'Fallback' : 'Primary';
                            final key = m['fallback'] == true
                                ? '${m['provider']}_fallback'
                                : (m['provider'] ?? '').toString();
                            final providerState = Map<String, dynamic>.from(
                              _providerStatusMap[key] as Map? ?? const {},
                            );
                            final autoFallback =
                                (providerState['auto_fallback_models'] as List<dynamic>? ?? const <dynamic>[]);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$label: ${m['provider']}  |  model: ${m['model']}',
                                    style: const TextStyle(color: Color(0xFFBFC6D1), fontSize: 12),
                                  ),
                                  if (autoFallback.isNotEmpty)
                                    Text(
                                      'Auto fallback: ${autoFallback.map((e) => e.toString()).join(' -> ')}',
                                      style: const TextStyle(color: Color(0xFF8F9AAA), fontSize: 11),
                                    ),
                                ],
                              ),
                            );
                          }),
                        if (_configuredChain.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Configured Chain',
                            style: TextStyle(
                              color: Color(0xFFE8884A),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ..._configuredChain.map((c) {
                            final m = Map<String, dynamic>.from(c as Map);
                            final label = m['fallback'] == true ? 'Fallback' : 'Primary';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '$label: ${m['provider']}  |  model: ${m['model']}',
                                style: const TextStyle(color: Color(0xFF9AA2AF), fontSize: 12),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Text('Primary Provider', style: TextStyle(color: Color(0xFFE8884A), fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _providerDropdown(
                  value: _primaryProvider,
                  onChanged: (v) => setState(() {
                    _primaryProvider = (v ?? 'openrouter');
                    _primaryModels = [];
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _primaryKeyCtrl,
                  decoration: InputDecoration(
                    labelText: 'API Key (new)',
                    hintText: _primaryMaskedKey.isEmpty ? 'Paste key' : 'Current: $_primaryMaskedKey',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: _primaryBaseUrl,
                  onChanged: (v) => _primaryBaseUrl = v.trim(),
                  decoration: const InputDecoration(
                    labelText: 'Base URL (optional/manual)',
                    hintText: 'Leave empty for default',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _primaryModel,
                        onChanged: (v) => _primaryModel = v.trim(),
                        decoration: const InputDecoration(
                          labelText: 'Selected Model',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _fetchingPrimary ? null : () => _fetchModels(primary: true),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8884A)),
                      child: _fetchingPrimary
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Load Models'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _modelList(
                  models: _primaryModels,
                  selected: _primaryModel,
                  onPick: (m) => setState(() => _primaryModel = m),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  value: _useFallback,
                  onChanged: (v) => setState(() => _useFallback = v),
                  title: const Text('Enable Fallback Provider'),
                  subtitle: const Text('Primary fail ho to fallback use hoga'),
                ),
                if (_useFallback) ...[
                  const SizedBox(height: 6),
                  const Text('Fallback Provider', style: TextStyle(color: Color(0xFFE8884A), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _providerDropdown(
                    value: _fallbackProvider,
                    onChanged: (v) => setState(() {
                      _fallbackProvider = (v ?? '');
                      _fallbackModels = [];
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _fallbackKeyCtrl,
                    decoration: InputDecoration(
                      labelText: 'Fallback API Key (new)',
                      hintText: _fallbackMaskedKey.isEmpty ? 'Paste key' : 'Current: $_fallbackMaskedKey',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: _fallbackBaseUrl,
                    onChanged: (v) => _fallbackBaseUrl = v.trim(),
                    decoration: const InputDecoration(
                      labelText: 'Fallback Base URL (optional/manual)',
                      hintText: 'Leave empty for default',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _fallbackModel,
                          onChanged: (v) => _fallbackModel = v.trim(),
                          decoration: const InputDecoration(
                            labelText: 'Fallback Model',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _fetchingFallback || _fallbackProvider.isEmpty
                            ? null
                            : () => _fetchModels(primary: false),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8884A)),
                        child: _fetchingFallback
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Load Models'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _modelList(
                    models: _fallbackModels,
                    selected: _fallbackModel,
                    onPick: (m) => setState(() => _fallbackModel = m),
                  ),
                ],
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8884A),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _saving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Saving...' : 'Save Settings'),
                ),
              ],
            ),
    );
  }
}
