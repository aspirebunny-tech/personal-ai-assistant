import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/local_db.dart';

enum _DiagStatus { ok, warn, fail }

class _DiagItem {
  final String key;
  final String title;
  final _DiagStatus status;
  final String message;
  final String details;

  const _DiagItem({
    required this.key,
    required this.title,
    required this.status,
    required this.message,
    this.details = '',
  });
}

class SystemDiagnosticsScreen extends StatefulWidget {
  const SystemDiagnosticsScreen({super.key});

  @override
  State<SystemDiagnosticsScreen> createState() =>
      _SystemDiagnosticsScreenState();
}

class _SystemDiagnosticsScreenState extends State<SystemDiagnosticsScreen> {
  final TextEditingController _serverCtrl = TextEditingController();
  final TextEditingController _tailscaleHostCtrl = TextEditingController();
  final TextEditingController _tailscalePortCtrl =
      TextEditingController(text: '3000');

  bool _tailscaleHttps = false;
  bool _running = false;
  bool _savingUrl = false;
  String _token = '';
  DateTime? _lastRunAt;
  final List<_DiagItem> _checks = [];

  @override
  void initState() {
    super.initState();
    _loadConfigAndRun();
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _tailscaleHostCtrl.dispose();
    _tailscalePortCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfigAndRun() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token') ?? ApiService.token;
    final savedUrl = prefs.getString('server_url') ?? ApiService.baseUrl;
    final normalized = _normalizeServerUrl(savedUrl);
    _serverCtrl.text = normalized;
    _hydrateTailscaleFieldsFromUrl(normalized);

    if (_token.isNotEmpty && normalized.isNotEmpty) {
      ApiService.init(normalized, _token);
    }

    if (!mounted) return;
    setState(() {});
    await _runAllChecks();
  }

  String _normalizeServerUrl(String raw) {
    String serverUrl = raw.trim();
    serverUrl = serverUrl.replaceAll(RegExp(r'\s+'), '');
    if (serverUrl.startsWith('https://https://')) {
      serverUrl = serverUrl.replaceFirst('https://', '');
    }
    if (serverUrl.startsWith('http://http://')) {
      serverUrl = serverUrl.replaceFirst('http://', '');
    }

    final plainHost = serverUrl
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .toLowerCase();
    final looksTailscale = plainHost.contains('.ts.net');

    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      serverUrl = '${looksTailscale ? 'http' : 'https'}://$serverUrl';
    }

    final hasExplicitPort = RegExp(r'^https?://[^/]*:\d+').hasMatch(serverUrl);
    if (looksTailscale && !hasExplicitPort) {
      final uri = Uri.tryParse(serverUrl);
      if (uri != null && uri.host.isNotEmpty) {
        serverUrl = uri.replace(port: 3000).toString();
      }
    }

    return serverUrl;
  }

  void _hydrateTailscaleFieldsFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.host.toLowerCase().contains('.ts.net')) return;
    _tailscaleHostCtrl.text = uri.host;
    _tailscalePortCtrl.text = (uri.port == 0 ? 3000 : uri.port).toString();
    _tailscaleHttps = uri.scheme == 'https';
  }

  String _connectionMode(String url) {
    final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
    if (host.contains('.ts.net')) return 'Tailscale (MagicDNS)';
    if (host.contains('trycloudflare.com')) return 'Cloudflare Quick Tunnel';
    if (host.isEmpty) return 'Unknown';
    return 'Custom/Public URL';
  }

  List<String> _tailscaleHostVariants(String host) {
    final lower = host.toLowerCase();
    if (!lower.contains('.ts.net')) return <String>[host];
    final firstDot = host.indexOf('.');
    if (firstDot <= 0) return <String>[host];
    final label = host.substring(0, firstDot);
    final suffix = host.substring(firstDot);
    final variants = <String>[host];
    final hasNumericTail = RegExp(r'.*-\d+$').hasMatch(label);
    if (hasNumericTail) {
      final base = label.replaceFirst(RegExp(r'-\d+$'), '');
      variants.add('$base$suffix');
    } else {
      variants.add('$label-1$suffix');
      variants.add('$label-2$suffix');
    }
    return variants.toSet().toList();
  }

  Future<String> _resolveBestServerUrl(String normalized) async {
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return normalized;
    if (!uri.host.toLowerCase().contains('.ts.net')) return normalized;

    final candidates = <String>[normalized];
    for (final host in _tailscaleHostVariants(uri.host)) {
      final same = uri.replace(host: host).toString();
      candidates.add(same);
      if (same.startsWith('http://')) {
        candidates.add(same.replaceFirst('http://', 'https://'));
      } else if (same.startsWith('https://')) {
        candidates.add(same.replaceFirst('https://', 'http://'));
      }
    }

    for (final c in candidates.toSet()) {
      try {
        final parsed = Uri.parse(c);
        await InternetAddress.lookup(parsed.host)
            .timeout(const Duration(seconds: 4));
        final res = await http
            .get(Uri.parse('$c/api/health'))
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) return c;
      } catch (_) {}
    }
    return normalized;
  }

  void _upsertCheck(_DiagItem item) {
    final index = _checks.indexWhere((e) => e.key == item.key);
    if (index < 0) {
      _checks.add(item);
    } else {
      _checks[index] = item;
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveServerUrl() async {
    final normalized = _normalizeServerUrl(_serverCtrl.text);
    if (normalized.isEmpty ||
        normalized == 'https://' ||
        normalized == 'http://') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valid server URL daalo')),
      );
      return;
    }

    setState(() => _savingUrl = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', normalized);
      _serverCtrl.text = normalized;
      _hydrateTailscaleFieldsFromUrl(normalized);
      if (_token.isNotEmpty) {
        ApiService.init(normalized, _token);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server URL updated: $normalized')),
      );
      await _runAllChecks();
    } finally {
      if (mounted) setState(() => _savingUrl = false);
    }
  }

  void _fillTailscaleUrl() {
    final host = _tailscaleHostCtrl.text.trim();
    final port = int.tryParse(_tailscalePortCtrl.text.trim()) ?? 3000;
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Tailscale host daalo (example: macmini.tailnet.ts.net)')),
      );
      return;
    }
    final scheme = _tailscaleHttps ? 'https' : 'http';
    _serverCtrl.text = '$scheme://$host:$port';
    setState(() {});
  }

  Future<void> _runAllChecks() async {
    if (_running) return;
    setState(() {
      _running = true;
      _checks.clear();
    });

    final normalized = _normalizeServerUrl(_serverCtrl.text);
    _serverCtrl.text = normalized;
    final resolvedUrl = await _resolveBestServerUrl(normalized);
    if (resolvedUrl != normalized) {
      _serverCtrl.text = resolvedUrl;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', resolvedUrl);
      _upsertCheck(
        _DiagItem(
          key: 'auto-fix-host',
          title: 'Auto Host Fix',
          status: _DiagStatus.warn,
          message: 'Tailscale host auto-updated',
          details: '$normalized -> $resolvedUrl',
        ),
      );
    }

    if (_token.isNotEmpty && _serverCtrl.text.isNotEmpty) {
      ApiService.init(_serverCtrl.text, _token);
    }

    await _checkConnectivity();
    final uri = _checkServerUrl(_serverCtrl.text);
    if (uri != null) {
      await _checkDns(uri);
      await _checkServerHealth();
      await _checkAuth();
      await _checkAi();
      await _checkMedia();
      await _checkPendingSync();
      await _checkServerSideDiagnostics();
    }

    if (mounted) {
      setState(() {
        _running = false;
        _lastRunAt = DateTime.now();
      });
    }
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      final online = !result.contains(ConnectivityResult.none);
      _upsertCheck(
        _DiagItem(
          key: 'device-connectivity',
          title: 'Device Internet',
          status: online ? _DiagStatus.ok : _DiagStatus.fail,
          message: online ? 'Internet available' : 'No internet',
          details: 'interfaces: ${result.map((r) => r.name).join(', ')}',
        ),
      );
    } catch (e) {
      _upsertCheck(
        _DiagItem(
          key: 'device-connectivity',
          title: 'Device Internet',
          status: _DiagStatus.fail,
          message: 'Connectivity check failed',
          details: '$e',
        ),
      );
    }
  }

  Uri? _checkServerUrl(String normalized) {
    if (normalized.isEmpty) {
      _upsertCheck(
        const _DiagItem(
          key: 'server-url',
          title: 'Server URL',
          status: _DiagStatus.fail,
          message: 'Server URL missing',
        ),
      );
      return null;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) {
      _upsertCheck(
        _DiagItem(
          key: 'server-url',
          title: 'Server URL',
          status: _DiagStatus.fail,
          message: 'Invalid URL',
          details: normalized,
        ),
      );
      return null;
    }

    final host = uri.host.toLowerCase();
    if (host.contains('trycloudflare.com')) {
      _upsertCheck(
        _DiagItem(
          key: 'server-url',
          title: 'Server URL',
          status: _DiagStatus.warn,
          message: 'Quick tunnel URL in use',
          details: 'Temporary URL, restart par change ho sakta hai. host=$host',
        ),
      );
    } else if (host.contains('.ts.net')) {
      _upsertCheck(
        _DiagItem(
          key: 'server-url',
          title: 'Server URL',
          status: _DiagStatus.ok,
          message: 'Tailscale MagicDNS URL detected',
          details: normalized,
        ),
      );
    } else {
      _upsertCheck(
        _DiagItem(
          key: 'server-url',
          title: 'Server URL',
          status: _DiagStatus.ok,
          message: 'Custom/Public URL detected',
          details: normalized,
        ),
      );
    }

    return uri;
  }

  Future<void> _checkDns(Uri uri) async {
    try {
      final host = uri.host;
      if (InternetAddress.tryParse(host) != null) {
        _upsertCheck(
          _DiagItem(
            key: 'dns',
            title: 'DNS Resolve',
            status: _DiagStatus.ok,
            message: 'IP host used (DNS not needed)',
            details: host,
          ),
        );
        return;
      }
      final ips = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 6));
      final ip = ips.isNotEmpty ? ips.first.address : 'unknown';
      _upsertCheck(
        _DiagItem(
          key: 'dns',
          title: 'DNS Resolve',
          status: _DiagStatus.ok,
          message: 'Resolved successfully',
          details: '$host -> $ip',
        ),
      );
    } catch (e) {
      _upsertCheck(
        _DiagItem(
          key: 'dns',
          title: 'DNS Resolve',
          status: _DiagStatus.fail,
          message: 'DNS failed',
          details: '$e',
        ),
      );
    }
  }

  Future<void> _checkServerHealth() async {
    final res =
        await ApiService.getServerHealth(timeout: const Duration(seconds: 8));
    final healthy = res['healthy'] == true;
    _upsertCheck(
      _DiagItem(
        key: 'server-health',
        title: 'Server Health',
        status: healthy ? _DiagStatus.ok : _DiagStatus.fail,
        message: healthy ? 'Health endpoint OK' : 'Health check failed',
        details: (res['message'] ?? '').toString(),
      ),
    );
  }

  Future<void> _checkAuth() async {
    if (_token.trim().isEmpty) {
      _upsertCheck(
        const _DiagItem(
          key: 'auth',
          title: 'Auth Token',
          status: _DiagStatus.fail,
          message: 'Token missing',
          details: 'Login dubara required',
        ),
      );
      return;
    }
    try {
      final folders = await ApiService.getFolders();
      _upsertCheck(
        _DiagItem(
          key: 'auth',
          title: 'Auth + API Access',
          status: _DiagStatus.ok,
          message: 'Authorized requests working',
          details: 'folders=${folders.length}',
        ),
      );
    } catch (e) {
      _upsertCheck(
        _DiagItem(
          key: 'auth',
          title: 'Auth + API Access',
          status: _DiagStatus.fail,
          message: 'Authorized request failed',
          details: '$e',
        ),
      );
    }
  }

  Future<void> _checkAi() async {
    try {
      final status = await ApiService.getAiStatus();
      final available = status['ai_available'] == true;
      final msg = (status['message'] ?? '').toString();
      final chain = (status['chain'] as List<dynamic>? ?? <dynamic>[]).map((c) {
        final map = Map<String, dynamic>.from(c as Map);
        final p = (map['provider'] ?? '').toString();
        final m = (map['model'] ?? '').toString();
        final fb = map['fallback'] == true ? ' [fallback]' : '';
        return '$p/$m$fb';
      }).join(' -> ');

      _upsertCheck(
        _DiagItem(
          key: 'ai-status',
          title: 'AI Availability',
          status: available ? _DiagStatus.ok : _DiagStatus.warn,
          message: available ? 'AI available' : 'AI fallback/offline mode',
          details:
              '${msg.isEmpty ? 'No message' : msg}${chain.isEmpty ? '' : '\nchain: $chain'}',
        ),
      );
    } catch (e) {
      _upsertCheck(
        _DiagItem(
          key: 'ai-status',
          title: 'AI Availability',
          status: _DiagStatus.fail,
          message: 'AI status check failed',
          details: '$e',
        ),
      );
    }

    try {
      final cfgRes = await ApiService.getAiProviderConfig();
      if (cfgRes['success'] != true) {
        _upsertCheck(
          _DiagItem(
            key: 'ai-config',
            title: 'AI Provider Config',
            status: _DiagStatus.fail,
            message: 'Provider config read failed',
            details: (cfgRes['error'] ?? 'unknown').toString(),
          ),
        );
        return;
      }
      final cfg = Map<String, dynamic>.from(cfgRes['config'] ?? {});
      final p = Map<String, dynamic>.from(cfg['primary'] ?? {});
      final f = Map<String, dynamic>.from(cfg['fallback'] ?? {});
      final useFallback = cfg['use_fallback'] != false;

      final primaryProvider = (p['provider'] ?? '').toString().trim();
      final primaryModel = (p['model'] ?? '').toString().trim();
      final fallbackProvider = (f['provider'] ?? '').toString().trim();
      final fallbackModel = (f['model'] ?? '').toString().trim();

      if (primaryProvider.isEmpty) {
        _upsertCheck(
          const _DiagItem(
            key: 'ai-config',
            title: 'AI Provider Config',
            status: _DiagStatus.fail,
            message: 'Primary provider missing',
            details: 'AI settings me primary set karo.',
          ),
        );
      } else if (useFallback && fallbackProvider.isEmpty) {
        _upsertCheck(
          _DiagItem(
            key: 'ai-config',
            title: 'AI Provider Config',
            status: _DiagStatus.warn,
            message: 'Fallback enabled but provider missing',
            details: 'primary=$primaryProvider/$primaryModel',
          ),
        );
      } else {
        _upsertCheck(
          _DiagItem(
            key: 'ai-config',
            title: 'AI Provider Config',
            status: _DiagStatus.ok,
            message: 'Provider chain configured',
            details:
                'primary=$primaryProvider/$primaryModel${useFallback ? '\nfallback=$fallbackProvider/$fallbackModel' : '\nfallback=disabled'}',
          ),
        );
      }
    } catch (e) {
      _upsertCheck(
        _DiagItem(
          key: 'ai-config',
          title: 'AI Provider Config',
          status: _DiagStatus.fail,
          message: 'Provider config validation failed',
          details: '$e',
        ),
      );
    }
  }

  Future<void> _checkMedia() async {
    try {
      final notes = await ApiService.getNotes();
      if (notes.isEmpty) {
        _upsertCheck(
          const _DiagItem(
            key: 'media-preview',
            title: 'Media Pipeline',
            status: _DiagStatus.warn,
            message: 'No notes found',
            details: 'Media check skipped (koi note nahi).',
          ),
        );
        return;
      }

      Map<String, dynamic>? mediaItem;
      for (final n in notes.take(8)) {
        final id = (n['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final noteRes = await ApiService.getNoteById(id);
        final note = Map<String, dynamic>.from(noteRes['note'] ?? {});
        final media = (note['media'] as List<dynamic>? ?? <dynamic>[])
            .map((m) => Map<String, dynamic>.from(m as Map))
            .toList();
        if (media.isEmpty) continue;
        mediaItem = media.first;
        break;
      }

      if (mediaItem == null) {
        _upsertCheck(
          const _DiagItem(
            key: 'media-preview',
            title: 'Media Pipeline',
            status: _DiagStatus.warn,
            message: 'No media attached in sampled notes',
            details: 'Media upload check skipped.',
          ),
        );
        return;
      }

      final mediaId = (mediaItem['id'] ?? '').toString();
      final filePath = (mediaItem['file_path'] ?? '').toString();
      final testUrl =
          ApiService.resolveMediaUrl(mediaId: mediaId, filePath: filePath);
      final response = await http
          .get(Uri.parse(testUrl), headers: ApiService.authOnlyHeaders)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _upsertCheck(
          _DiagItem(
            key: 'media-preview',
            title: 'Media Pipeline',
            status: _DiagStatus.ok,
            message: 'Media file fetch working',
            details:
                'status=${response.statusCode}, content-type=${response.headers['content-type'] ?? 'unknown'}',
          ),
        );
      } else {
        final body = response.body.length > 180
            ? '${response.body.substring(0, 180)}...'
            : response.body;
        _upsertCheck(
          _DiagItem(
            key: 'media-preview',
            title: 'Media Pipeline',
            status: _DiagStatus.fail,
            message: 'Media fetch failed HTTP ${response.statusCode}',
            details: body,
          ),
        );
      }
    } catch (e) {
      _upsertCheck(
        _DiagItem(
          key: 'media-preview',
          title: 'Media Pipeline',
          status: _DiagStatus.fail,
          message: 'Media check failed',
          details: '$e',
        ),
      );
    }
  }

  Future<void> _checkPendingSync() async {
    try {
      final pending = await LocalDB.getPendingNotes();
      if (pending.isEmpty) {
        _upsertCheck(
          const _DiagItem(
            key: 'pending-sync',
            title: 'Pending Sync Queue',
            status: _DiagStatus.ok,
            message: 'No pending notes',
          ),
        );
      } else {
        _upsertCheck(
          _DiagItem(
            key: 'pending-sync',
            title: 'Pending Sync Queue',
            status: _DiagStatus.warn,
            message: '${pending.length} note(s) pending',
            details: 'Server/tunnel back online hote hi sync karo.',
          ),
        );
      }
    } catch (e) {
      _upsertCheck(
        _DiagItem(
          key: 'pending-sync',
          title: 'Pending Sync Queue',
          status: _DiagStatus.fail,
          message: 'Pending queue read failed',
          details: '$e',
        ),
      );
    }
  }

  Future<void> _checkServerSideDiagnostics() async {
    final diag = await ApiService.getSystemDiagnostics();
    if (diag['success'] != true) {
      _upsertCheck(
        _DiagItem(
          key: 'server-side-summary',
          title: 'Server Internal Diagnostics',
          status: _DiagStatus.fail,
          message: 'Server-side diagnostics unavailable',
          details: (diag['error'] ?? 'unknown').toString(),
        ),
      );
      return;
    }

    final summary = Map<String, dynamic>.from(diag['summary'] ?? {});
    final ok = (summary['ok'] ?? 0).toString();
    final warn = (summary['warn'] ?? 0).toString();
    final fail = (summary['fail'] ?? 0).toString();
    final summaryStatus = (summary['fail'] ?? 0) > 0
        ? _DiagStatus.fail
        : ((summary['warn'] ?? 0) > 0 ? _DiagStatus.warn : _DiagStatus.ok);

    _upsertCheck(
      _DiagItem(
        key: 'server-side-summary',
        title: 'Server Internal Diagnostics',
        status: summaryStatus,
        message: 'ok=$ok, warn=$warn, fail=$fail',
        details:
            'host=${diag['request_host'] ?? ''} | generated=${diag['generated_at'] ?? ''}',
      ),
    );

    final rows = (diag['checks'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    for (final row in rows) {
      final rawStatus = (row['status'] ?? 'warn').toString();
      final status = rawStatus == 'ok'
          ? _DiagStatus.ok
          : (rawStatus == 'fail' ? _DiagStatus.fail : _DiagStatus.warn);
      _upsertCheck(
        _DiagItem(
          key: 'server-${row['key']}',
          title: 'Server · ${(row['title'] ?? '').toString()}',
          status: status,
          message: (row['message'] ?? '').toString(),
          details: (row['details'] ?? '').toString(),
        ),
      );
    }
  }

  Color _statusColor(_DiagStatus status) {
    switch (status) {
      case _DiagStatus.ok:
        return Colors.green;
      case _DiagStatus.warn:
        return Colors.orange;
      case _DiagStatus.fail:
        return Colors.red;
    }
  }

  IconData _statusIcon(_DiagStatus status) {
    switch (status) {
      case _DiagStatus.ok:
        return Icons.check_circle;
      case _DiagStatus.warn:
        return Icons.warning_amber_rounded;
      case _DiagStatus.fail:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final okCount = _checks.where((c) => c.status == _DiagStatus.ok).length;
    final warnCount = _checks.where((c) => c.status == _DiagStatus.warn).length;
    final failCount = _checks.where((c) => c.status == _DiagStatus.fail).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Diagnostics'),
        actions: [
          IconButton(
            onPressed: _running ? null : _runAllChecks,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connection Manager',
                  style: TextStyle(
                      color: Color(0xFFE8884A), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _serverCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    border: OutlineInputBorder(),
                    hintText: 'https://... ya http://...:3000',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Mode: ${_connectionMode(_serverCtrl.text)}',
                  style:
                      const TextStyle(color: Color(0xFFB3B3B3), fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _savingUrl ? null : _saveServerUrl,
                        child: Text(_savingUrl ? 'Saving...' : 'Save URL'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _running ? null : _runAllChecks,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8884A),
                          foregroundColor: Colors.black,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _running
                                  ? Icons.hourglass_top
                                  : Icons.verified_user_outlined,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(_running ? 'Checking...' : 'Run Full Check'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF2E2E2E), height: 1),
                const SizedBox(height: 12),
                const Text(
                  'Tailscale Quick Fill',
                  style: TextStyle(
                      color: Color(0xFFE8884A),
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _tailscaleHostCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Host (.ts.net)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _tailscalePortCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Switch(
                      value: _tailscaleHttps,
                      onChanged: (v) => setState(() => _tailscaleHttps = v),
                    ),
                    Text(
                      _tailscaleHttps
                          ? 'Use HTTPS'
                          : 'Use HTTP (recommended for local Node)',
                      style: const TextStyle(
                          color: Color(0xFFB3B3B3), fontSize: 12),
                    ),
                    const Spacer(),
                    TextButton(
                        onPressed: _fillTailscaleUrl,
                        child: const Text('Apply')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Row(
              children: [
                _SummaryChip(color: Colors.green, label: 'OK', count: okCount),
                const SizedBox(width: 8),
                _SummaryChip(
                    color: Colors.orange, label: 'Warn', count: warnCount),
                const SizedBox(width: 8),
                _SummaryChip(
                    color: Colors.red, label: 'Fail', count: failCount),
                const Spacer(),
                Text(
                  _lastRunAt == null
                      ? 'Never run'
                      : 'Last: ${_lastRunAt!.toLocal().toString().split('.').first}',
                  style:
                      const TextStyle(color: Color(0xFF9E9E9E), fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_checks.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              child: const Text(
                'No diagnostics yet. Tap "Run Full Check".',
                style: TextStyle(color: Color(0xFFBDBDBD)),
              ),
            )
          else
            ..._checks.map((c) {
              final color = _statusColor(c.status);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.45)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_statusIcon(c.status), color: color, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.title,
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(c.message,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                    if (c.details.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        c.details,
                        style: const TextStyle(
                            color: Color(0xFFBDBDBD), fontSize: 11),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  const _SummaryChip(
      {required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$label: $count',
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
