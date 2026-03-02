import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _serverCtrl = TextEditingController(text: 'https://');
  bool _isLogin = true;
  bool _loading = false;
  bool _testingUrl = false;
  String? _error;

  bool _hasExplicitPort(String value) {
    return RegExp(r'^https?://[^/]*:\d+').hasMatch(value);
  }

  void _setServerUrl(String value) {
    _serverCtrl.text = value;
    _serverCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: _serverCtrl.text.length),
    );
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
    if (looksTailscale && !_hasExplicitPort(serverUrl)) {
      final uri = Uri.tryParse(serverUrl);
      if (uri != null && uri.host.isNotEmpty) {
        serverUrl = uri.replace(port: 3000).toString();
      }
    }
    return serverUrl;
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

  Future<Map<String, dynamic>> _checkServerDetailed(String serverUrl) async {
    final normalized = _normalizeServerUrl(serverUrl);
    final attempts = <String>[normalized];
    try {
      final parsed = Uri.parse(normalized);
      if (parsed.host.isEmpty) {
        return {'ok': false, 'msg': 'Invalid URL: host missing'};
      }
      final host = parsed.host.toLowerCase();
      if (host.contains('.ts.net')) {
        // Tailscale setups often run plain HTTP on :3000.
        if (normalized.startsWith('https://')) {
          attempts.add(normalized.replaceFirst('https://', 'http://'));
        } else if (normalized.startsWith('http://')) {
          attempts.add(normalized.replaceFirst('http://', 'https://'));
        }
        for (final h in _tailscaleHostVariants(parsed.host)) {
          final alt = parsed.replace(host: h).toString();
          attempts.add(alt);
          if (alt.startsWith('https://')) {
            attempts.add(alt.replaceFirst('https://', 'http://'));
          } else if (alt.startsWith('http://')) {
            attempts.add(alt.replaceFirst('http://', 'https://'));
          }
        }
      }
    } catch (_) {}

    String lastError = 'Unknown error';
    for (final candidate in attempts.toSet()) {
      try {
        final uri = Uri.parse(candidate);
        if (uri.host.isEmpty) {
          lastError = 'Invalid URL: host missing';
          continue;
        }
        try {
          await InternetAddress.lookup(uri.host)
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          lastError = 'DNS fail (${uri.host}): $e';
          continue;
        }

        final healthUri = Uri.parse('$candidate/api/health');
        final res =
            await http.get(healthUri).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          return {
            'ok': true,
            'msg': 'Server reachable ✅',
            'resolved_url': candidate,
          };
        }
        final body = res.body.length > 120
            ? '${res.body.substring(0, 120)}...'
            : res.body;
        lastError = 'Health failed: HTTP ${res.statusCode}. $body';
      } on SocketException catch (e) {
        lastError = 'Network socket error: $e';
      } on HandshakeException catch (e) {
        lastError = 'TLS/SSL error: $e';
      } catch (e) {
        lastError = 'Connection error: $e';
      }
    }
    return {'ok': false, 'msg': lastError};
  }

  Future<void> _testServerUrl() async {
    setState(() {
      _testingUrl = true;
      _error = null;
    });
    try {
      var serverUrl = _normalizeServerUrl(_serverCtrl.text);
      _setServerUrl(serverUrl);
      if (serverUrl.isEmpty || serverUrl == 'https://') {
        setState(
            () => _error = 'Server URL daalo (Tailscale/Cloudflare/custom)');
        return;
      }
      final diag = await _checkServerDetailed(serverUrl);
      final resolved = (diag['resolved_url'] ?? '').toString();
      if (resolved.isNotEmpty) {
        serverUrl = resolved;
        _setServerUrl(serverUrl);
      }
      if (!mounted) return;
      final message = (diag['msg'] ?? '').toString();
      if (diag['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(message), backgroundColor: Colors.green.shade700),
        );
      } else {
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _testingUrl = false);
    }
  }

  Future<void> _openTailscaleSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final hostCtrl = TextEditingController(
      text: prefs.getString('tailscale_host') ?? '',
    );
    final portCtrl = TextEditingController(
      text: (prefs.getInt('tailscale_port') ?? 3000).toString(),
    );
    bool useHttps = prefs.getBool('tailscale_https') ?? false;

    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Tailscale Setup',
              style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Host example: macmini-yourtailnet.ts.net',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: hostCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Tailscale Host',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: portCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: useHttps,
                  onChanged: (v) => setDialogState(() => useHttps = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use HTTPS'),
                  subtitle: const Text(
                      'Local Node server ke liye HTTP usually better'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final host = hostCtrl.text.trim();
                final port = int.tryParse(portCtrl.text.trim()) ?? 3000;
                if (host.isEmpty) return;
                Navigator.pop(ctx, {
                  'host': host,
                  'port': port,
                  'https': useHttps,
                });
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8884A)),
              child: const Text('Use'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final host = (result['host'] ?? '').toString().trim();
    final port = (result['port'] as int?) ?? 3000;
    final https = result['https'] == true;
    if (host.isEmpty) return;

    final url = '${https ? 'https' : 'http'}://$host:$port';
    _setServerUrl(url);
    await prefs.setString('tailscale_host', host);
    await prefs.setInt('tailscale_port', port);
    await prefs.setBool('tailscale_https', https);
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var serverUrl = _normalizeServerUrl(_serverCtrl.text);
      _setServerUrl(serverUrl);
      if (serverUrl.isEmpty || serverUrl == 'https://') {
        setState(() {
          _error = 'Server URL daalo (Tailscale/Cloudflare/custom)';
          _loading = false;
        });
        return;
      }

      final diag = await _checkServerDetailed(serverUrl);
      if (diag['ok'] != true) {
        setState(() {
          _error =
              (diag['msg'] ?? 'Server se connect nahi ho pa raha').toString();
          _loading = false;
        });
        return;
      }
      final resolved = (diag['resolved_url'] ?? '').toString();
      if (resolved.isNotEmpty) {
        serverUrl = resolved;
        _setServerUrl(serverUrl);
      }

      Map<String, dynamic> res;
      if (_isLogin) {
        res = await ApiService.login(
            _emailCtrl.text.trim(), _passCtrl.text, serverUrl);
      } else {
        res = await ApiService.register(_emailCtrl.text.trim(), _passCtrl.text,
            _nameCtrl.text.trim(), serverUrl);
      }

      if (res['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', res['token']);
        await prefs.setString('server_url', serverUrl);
        ApiService.init(serverUrl, res['token']);
        if (mounted) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        }
      } else {
        setState(() {
          _error = res['error'] ?? 'Kuch galat hua';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Connection error: $e';
      });
    }
    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D0D0D), Color(0xFF1A1A1A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF242424),
                      borderRadius: BorderRadius.circular(22),
                      border:
                          Border.all(color: const Color(0xFFE8884A), width: 2),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: Color(0xFFE8884A), size: 40),
                  ),
                  const SizedBox(height: 20),
                  const Text('Personal AI Assistant',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_isLogin ? 'Login karo' : 'Account banao',
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 36),

                  // Server URL
                  _buildField(
                      _serverCtrl, 'Server URL (Cloudflare URL)', Icons.link),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed:
                          (_loading || _testingUrl) ? null : _testServerUrl,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE8884A)),
                      ),
                      icon: _testingUrl
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFFE8884A)),
                            )
                          : const Icon(Icons.network_check,
                              size: 16, color: Color(0xFFE8884A)),
                      label: Text(
                        _testingUrl ? 'Testing...' : 'Test URL',
                        style: const TextStyle(color: Color(0xFFE8884A)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_loading || _testingUrl)
                              ? null
                              : _openTailscaleSetup,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF2E2E2E)),
                          ),
                          icon: const Icon(Icons.vpn_lock,
                              size: 16, color: Color(0xFFE8884A)),
                          label: const Text(
                            'Tailscale Setup',
                            style: TextStyle(color: Color(0xFFE8884A)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_loading || _testingUrl)
                              ? null
                              : () async {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  final last =
                                      (prefs.getString('server_url') ?? '')
                                          .trim();
                                  if (last.isEmpty) return;
                                  _setServerUrl(last);
                                },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF2E2E2E)),
                          ),
                          icon: const Icon(Icons.history,
                              size: 16, color: Color(0xFFE8884A)),
                          label: const Text(
                            'Use Last URL',
                            style: TextStyle(color: Color(0xFFE8884A)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (!_isLogin) ...[
                    _buildField(_nameCtrl, 'Aapka Naam', Icons.person),
                    const SizedBox(height: 12),
                  ],

                  _buildField(_emailCtrl, 'Email', Icons.email,
                      keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _buildField(_passCtrl, 'Password', Icons.lock, obscure: true),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 13))),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE8884A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(_isLogin ? 'Login' : 'Register',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),

                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() {
                      _isLogin = !_isLogin;
                      _error = null;
                    }),
                    child: Text(
                      _isLogin
                          ? 'Naya account banao? Register karo'
                          : 'Pehle se account hai? Login karo',
                      style: const TextStyle(color: Color(0xFFE8884A)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon,
      {bool obscure = false, TextInputType? keyboardType}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          prefixIcon: Icon(icon, color: const Color(0xFFE8884A), size: 20),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}
