import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import 'notes_screen.dart';
import 'search_screen.dart';
import 'add_note_screen.dart';
import 'quick_summary_screen.dart';
import 'ask_notes_screen.dart';
import 'ai_provider_settings_screen.dart';
import 'system_diagnostics_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<dynamic> _folders = [];
  bool _loading = true;
  bool _isOnline = true;
  bool _aiAvailable = true;
  String _aiMessage = '';
  bool _serverHealthy = false;
  bool _startingServer = false;
  int _pendingSyncCount = 0;
  bool _checkingUpdate = false;
  bool _downloadingUpdate = false;
  bool _hasUpdate = false;
  String _latestVersionLabel = '';
  String _releaseNotes = '';
  String _apkUrl = '';
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _serverHealthTimer;
  Timer? _autoRefreshTimer;
  bool _autoRefreshing = false;
  Timer? _tailscaleStatusTimer;
  bool _tailscaleWarnVisible = false;
  bool _tailscaleWarnFail = false;
  String _tailscaleWarnMessage = '';
  String _tailscaleWarnDetails = '';

  String _serverHostLabel() {
    final uri = Uri.tryParse(ApiService.baseUrl);
    if (uri == null || uri.host.isEmpty) return 'server';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.host}$port';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final online = !result.contains(ConnectivityResult.none);
      if (online != _isOnline) {
        setState(() => _isOnline = online);
        if (online) _syncPendingNotes();
      }
    });
    _serverHealthTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _checkServerHealth();
    });
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshFoldersSilently();
    });
    _tailscaleStatusTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkTailscaleSessionWarning();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkConnectivity();
      _checkServerHealth();
      _refreshFoldersSilently();
      _checkAiStatus();
      _checkTailscaleSessionWarning();
    }
  }

  Future<void> _bootstrap() async {
    await _checkConnectivity();
    await _checkServerHealth();
    await _refreshPendingSyncCount();
    await _checkAndroidUpdate();
    await _loadFolders();
    await _checkAiStatus();
    await _checkTailscaleSessionWarning();
  }

  Future<void> _refreshPendingSyncCount() async {
    final pending = await LocalDB.getPendingNotes();
    if (!mounted) return;
    setState(() => _pendingSyncCount = pending.length);
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() => _isOnline = !result.contains(ConnectivityResult.none));
    }
  }

  Future<void> _loadFolders() async {
    setState(() => _loading = true);
    try {
      if (_isOnline) {
        final folders = await ApiService.getFolders();
        await LocalDB.cacheFolders(folders);
        setState(() => _folders = folders);
      } else {
        final cached = await LocalDB.getCachedFolders();
        setState(() => _folders = cached);
      }
    } catch (_) {
      final cached = await LocalDB.getCachedFolders();
      setState(() => _folders = cached);
    }
    await _refreshPendingSyncCount();
    setState(() => _loading = false);
  }

  Future<void> _refreshFoldersSilently() async {
    if (!mounted || _autoRefreshing || _loading || !_isOnline) return;
    if (!_serverHealthy) return;
    _autoRefreshing = true;
    try {
      final folders = await ApiService.getFolders();
      await LocalDB.cacheFolders(folders);
      if (!mounted) return;
      setState(() => _folders = folders);
      await _refreshPendingSyncCount();
    } catch (_) {
      // Silent background refresh; UI warning noise avoid.
    } finally {
      _autoRefreshing = false;
    }
  }

  Future<void> _checkAiStatus() async {
    try {
      final res = await ApiService.getAiStatus();
      if (!mounted) return;
      setState(() {
        _aiAvailable = res['ai_available'] == true;
        _aiMessage = (res['message'] ?? '').toString();
      });
    } catch (_) {}
  }

  Future<void> _checkServerHealth() async {
    final wasHealthy = _serverHealthy;
    final res = await ApiService.getServerHealth();
    if (!mounted) return;
    final nowHealthy = res['healthy'] == true;
    setState(() {
      _serverHealthy = nowHealthy;
    });
    if (!wasHealthy && nowHealthy) {
      await _refreshPendingSyncCount();
      if (_pendingSyncCount > 0) {
        await _syncPendingNotes();
      } else {
        await _loadFolders();
      }
    }
    if (nowHealthy) {
      _checkTailscaleSessionWarning();
    } else if (mounted) {
      setState(() {
        _tailscaleWarnVisible = false;
      });
    }
  }

  Future<void> _checkTailscaleSessionWarning() async {
    if (!_serverHealthy) return;
    try {
      final diag = await ApiService.getSystemDiagnostics();
      if (!mounted || diag['success'] != true) return;
      final rows = (diag['checks'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final ts = rows.firstWhere(
        (r) => (r['key'] ?? '').toString() == 'tailscale-session',
        orElse: () => <String, dynamic>{},
      );
      if (ts.isEmpty) {
        setState(() => _tailscaleWarnVisible = false);
        return;
      }
      final status = (ts['status'] ?? '').toString().toLowerCase();
      final isWarn = status == 'warn' || status == 'fail';
      setState(() {
        _tailscaleWarnVisible = isWarn;
        _tailscaleWarnFail = status == 'fail';
        _tailscaleWarnMessage = (ts['message'] ?? '').toString();
        _tailscaleWarnDetails = (ts['details'] ?? '').toString();
      });
    } catch (_) {
      // Diagnostics fail should not break home UX.
    }
  }

  int _compareVersions(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  Future<void> _checkAndroidUpdate() async {
    if (!Platform.isAndroid) return;
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final pkg = await PackageInfo.fromPlatform();
      final currentVersion = pkg.version;
      final currentBuild = int.tryParse(pkg.buildNumber) ?? 0;
      final res = await ApiService.getAndroidUpdateInfo();
      if (!mounted) return;
      if (res['success'] != true) {
        setState(() => _checkingUpdate = false);
        return;
      }
      final update = Map<String, dynamic>.from(res['update'] ?? {});
      final latestVersion = (update['latest_version'] ?? '').toString().trim();
      final latestBuild =
          int.tryParse((update['latest_build_number'] ?? '').toString()) ?? 0;
      var apkUrl = (update['apk_url'] ?? '').toString().trim();
      if (apkUrl.startsWith('/')) {
        apkUrl = '${ApiService.baseUrl}$apkUrl';
      }
      final releaseNotes = (update['release_notes'] ?? '').toString();
      final newer = latestVersion.isNotEmpty &&
          (_compareVersions(latestVersion, currentVersion) > 0 ||
              latestBuild > currentBuild);
      setState(() {
        _hasUpdate = newer;
        _latestVersionLabel = latestVersion;
        _releaseNotes = releaseNotes;
        _apkUrl = apkUrl;
        _checkingUpdate = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _downloadAndInstallUpdate() async {
    if (!Platform.isAndroid ||
        _downloadingUpdate ||
        !_hasUpdate ||
        _apkUrl.isEmpty) {
      return;
    }
    setState(() => _downloadingUpdate = true);
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/personal_ai_assistant_update.apk';
      final file =
          await ApiService.downloadFile(url: _apkUrl, savePath: filePath);
      final result = await OpenFilex.open(file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.type == ResultType.done
                ? 'Update installer opened. Permission dekar install karo.'
                : 'Installer open status: ${result.message}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update download failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloadingUpdate = false);
    }
  }

  Future<void> _startLocalServer() async {
    if (_startingServer || !Platform.isMacOS) return;
    setState(() => _startingServer = true);
    try {
      final home = Platform.environment['HOME'] ?? '';
      final candidateDirs = <String>[
        '$home/Desktop/personal-ai-assistant/server',
        '$home/personal-ai-assistant/server',
        '/Users/aspirebunny/Desktop/personal-ai-assistant/server',
      ];
      String? chosenDir;
      for (final dir in candidateDirs) {
        if (await Directory(dir).exists()) {
          chosenDir = dir;
          break;
        }
      }
      if (chosenDir == null) {
        throw Exception('Server folder not found in default locations');
      }

      // Packaged macOS app me PATH often minimal hota hai; explicit Node binary detect karo.
      const nodeCandidates = <String>[
        '/opt/homebrew/bin/node',
        '/usr/local/bin/node',
        '/usr/bin/node',
      ];
      String nodeBin = 'node';
      for (final candidate in nodeCandidates) {
        if (await File(candidate).exists()) {
          nodeBin = candidate;
          break;
        }
      }

      final cmd = [
        'cd',
        "'$chosenDir'",
        '&&',
        'nohup',
        "'$nodeBin'",
        'src/index.js',
        '>/tmp/pai_server.log',
        '2>&1',
        '&',
      ].join(' ');

      await Process.run('/bin/zsh', ['-lc', cmd]);

      // Retry checks: start hone me thoda time lag sakta hai.
      bool up = false;
      for (int i = 0; i < 8; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final health = await ApiService.getServerHealth();
        if (health['healthy'] == true) {
          up = true;
          break;
        }
      }

      await _checkServerHealth();
      if (_serverHealthy) {
        await _checkAiStatus();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (_serverHealthy || up)
                ? 'Server started ✅'
                : 'Server start failed. Check /tmp/pai_server.log',
          ),
        ),
      );
      if (!_serverHealthy && !up) {
        try {
          final logFile = File('/tmp/pai_server.log');
          if (await logFile.exists()) {
            final lines = await logFile.readAsLines();
            final tail = lines.reversed.take(3).toList().reversed.join(' | ');
            if (mounted && tail.trim().isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Server log: $tail')),
              );
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Start server failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _startingServer = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _serverHealthTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _tailscaleStatusTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncPendingNotes() async {
    final pending = await LocalDB.getPendingNotes();
    for (final note in pending) {
      try {
        await ApiService.createNote(
          content: note['content'],
          title: note['title'],
          folderId: note['folder_id'],
        );
        await LocalDB.markSynced(note['id']);
      } catch (_) {}
    }
    if (pending.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${pending.length} notes sync ho gaye! ✅'),
          backgroundColor: Colors.green.shade700));
      await _refreshPendingSyncCount();
      _loadFolders();
    } else {
      await _refreshPendingSyncCount();
    }
  }

  void _showAddFolderDialog() {
    final nameCtrl = TextEditingController();
    String selectedIcon = '📁';
    final icons = [
      '📁',
      '💡',
      '❤️',
      '🎯',
      '💼',
      '🎵',
      '🏠',
      '✈️',
      '📚',
      '💰',
      '🌱',
      '⭐'
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title:
              const Text('Naya Folder', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Folder ka naam',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFE8884A))),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Icon chuno:',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: icons
                    .map((icon) => GestureDetector(
                          onTap: () =>
                              setDialogState(() => selectedIcon = icon),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: selectedIcon == icon
                                  ? const Color(0xFFE8884A)
                                      .withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selectedIcon == icon
                                    ? const Color(0xFFE8884A)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(icon,
                                style: const TextStyle(fontSize: 20)),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isNotEmpty) {
                  await ApiService.createFolder(
                      nameCtrl.text.trim(), selectedIcon, '#E8884A');
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _loadFolders();
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8884A)),
              child: const Text('Banao'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameFolderDialog(Map<String, dynamic> folder) async {
    final nameCtrl =
        TextEditingController(text: (folder['name'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title:
            const Text('Rename Folder', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Folder name',
            labelStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8884A)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final nextName = nameCtrl.text.trim();
    if (nextName.isEmpty) return;
    await ApiService.updateFolder(
      id: folder['id'].toString(),
      name: nextName,
      icon: (folder['icon'] ?? '📁').toString(),
      color: (folder['color'] ?? '#E8884A').toString(),
    );
    await _loadFolders();
  }

  Future<void> _confirmDeleteFolder(Map<String, dynamic> folder) async {
    if (Platform.isAndroid && !_serverHealthy) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tunnel/server off: Android pe delete disabled.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title:
            const Text('Delete Folder?', style: TextStyle(color: Colors.white)),
        content: Text(
          '"${folder['name']}" folder delete hoga. Iske notes orphan ho sakte hain.',
          style: const TextStyle(color: Color(0xFFCCCCCC)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ApiService.deleteFolder(folder['id'].toString());
    await _loadFolders();
  }

  void _openFolder(Map<String, dynamic> folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotesScreen(
          folderId: folder['id'],
          folderName: folder['name'],
          folderIcon: folder['icon'] ?? '📁',
        ),
      ),
    ).then((_) => _loadFolders());
  }

  void _createQuickNoteInFolder(Map<String, dynamic> folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddNoteScreen(
          folderId: folder['id']?.toString(),
          folderName: folder['name']?.toString(),
          onSaved: _loadFolders,
        ),
      ),
    );
  }

  Future<void> _showFolderContextMenu(
      Map<String, dynamic> folder, Offset globalPosition) async {
    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xFF1A1A1A),
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'open', child: Text('Open Folder')),
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'new_note', child: Text('New Note')),
        PopupMenuItem(value: 'delete', child: Text('Delete Folder')),
      ],
    );
    if (selected == null) return;
    if (selected == 'open') {
      _openFolder(folder);
      return;
    }
    if (selected == 'rename') {
      await _showRenameFolderDialog(folder);
      return;
    }
    if (selected == 'new_note') {
      _createQuickNoteInFolder(folder);
      return;
    }
    if (selected == 'delete') {
      await _confirmDeleteFolder(folder);
    }
  }

  void _showQuickActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add, color: Color(0xFFE8884A)),
              title: const Text('Quick Note',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Naya note likho',
                  style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AddNoteScreen(onSaved: _loadFolders)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: Color(0xFFE8884A)),
              title: const Text('Quick AI Summary',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Purane notes select karke bullet summary',
                  style: TextStyle(color: Colors.grey)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QuickSummaryScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final folderColumns = screenWidth > 700 ? 3 : 2;
    final compactFolders = _folders.length >= 3;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.auto_awesome, color: Color(0xFFE8884A), size: 22),
          const SizedBox(width: 8),
          const Text('AI Assistant',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isOnline
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_isOnline ? Icons.wifi : Icons.wifi_off,
                  color: _isOnline ? Colors.green : Colors.red, size: 14),
              const SizedBox(width: 4),
              Text(_isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                      color: _isOnline ? Colors.green : Colors.red,
                      fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'System Diagnostics',
            icon: const Icon(Icons.health_and_safety_outlined,
                color: Color(0xFFE8884A)),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SystemDiagnosticsScreen()),
              );
              _checkServerHealth();
              _checkAiStatus();
            },
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'AI Settings',
            icon: const Icon(Icons.tune, color: Color(0xFFE8884A)),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AiProviderSettingsScreen()),
              );
              _checkAiStatus();
            },
          ),
        ]),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE8884A)))
          : RefreshIndicator(
              onRefresh: _loadFolders,
              color: const Color(0xFFE8884A),
              child: CustomScrollView(
                slivers: [
                  // Quick Actions
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        _QuickAction(
                            icon: Icons.search,
                            label: 'AI Search',
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SearchScreen()))),
                        const SizedBox(width: 12),
                        _QuickAction(
                            icon: Icons.psychology_alt,
                            label: 'Ask Notes',
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AskNotesScreen()))),
                        const SizedBox(width: 12),
                        _QuickAction(
                            icon: Icons.note_add,
                            label: 'Quick Note',
                            onTap: _showQuickActionSheet),
                      ]),
                    ),
                  ),
                  if (!_aiAvailable)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 2),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _aiMessage.isEmpty
                                      ? 'AI unavailable: fallback mode'
                                      : _aiMessage,
                                  style: const TextStyle(
                                      color: Colors.orange, fontSize: 12),
                                ),
                              ),
                              TextButton(
                                onPressed: _checkAiStatus,
                                child: const Text('Retry',
                                    style: TextStyle(color: Colors.orange)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (Platform.isAndroid && _hasUpdate)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 2),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF28A745).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF28A745)
                                    .withValues(alpha: 0.45)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.system_update_alt,
                                  color: Color(0xFF28A745), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Update available: v$_latestVersionLabel ${_releaseNotes.isEmpty ? '' : '• $_releaseNotes'}',
                                  style: const TextStyle(
                                      color: Color(0xFF7BE495), fontSize: 12),
                                ),
                              ),
                              TextButton(
                                onPressed: _downloadingUpdate
                                    ? null
                                    : _downloadAndInstallUpdate,
                                child: Text(
                                  _downloadingUpdate
                                      ? 'Downloading...'
                                      : 'Update',
                                  style:
                                      const TextStyle(color: Color(0xFF7BE495)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (_serverHealthy ? Colors.green : Colors.red)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (_serverHealthy ? Colors.green : Colors.red)
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _serverHealthy
                                  ? Icons.cloud_done
                                  : Icons.cloud_off,
                              color: _serverHealthy ? Colors.green : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _serverHealthy
                                    ? 'Server healthy (${_serverHostLabel()})'
                                    : 'Server unavailable (${_serverHostLabel()})',
                                style: TextStyle(
                                  color: _serverHealthy
                                      ? Colors.green
                                      : Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _checkServerHealth,
                              child: const Text('Check'),
                            ),
                            if (Platform.isMacOS && !_serverHealthy)
                              TextButton(
                                onPressed:
                                    _startingServer ? null : _startLocalServer,
                                child: Text(_startingServer
                                    ? 'Starting...'
                                    : 'Start Server'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_tailscaleWarnVisible)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 2),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (_tailscaleWarnFail
                                    ? Colors.red
                                    : Colors.orange)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: (_tailscaleWarnFail
                                      ? Colors.red
                                      : Colors.orange)
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _tailscaleWarnFail
                                    ? Icons.error_outline
                                    : Icons.warning_amber_rounded,
                                color: _tailscaleWarnFail
                                    ? Colors.red
                                    : Colors.orange,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _tailscaleWarnDetails.isEmpty
                                      ? 'Tailscale: $_tailscaleWarnMessage'
                                      : 'Tailscale: $_tailscaleWarnMessage\n$_tailscaleWarnDetails',
                                  style: TextStyle(
                                    color: _tailscaleWarnFail
                                        ? Colors.red
                                        : Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _checkTailscaleSessionWarning,
                                child: Text(
                                  'Retry',
                                  style: TextStyle(
                                    color: _tailscaleWarnFail
                                        ? Colors.red
                                        : Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_pendingSyncCount > 0)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 2),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.sync_problem,
                                  color: Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Pending Sync: $_pendingSyncCount note(s)',
                                  style: const TextStyle(
                                      color: Colors.orange, fontSize: 12),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await _syncPendingNotes();
                                },
                                child: const Text('Sync Now',
                                    style: TextStyle(color: Colors.orange)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Folders Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(children: [
                        const Text('Folders',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _showAddFolderDialog,
                          icon: const Icon(Icons.add,
                              color: Color(0xFFE8884A), size: 18),
                          label: const Text('Naya',
                              style: TextStyle(color: Color(0xFFE8884A))),
                        ),
                      ]),
                    ),
                  ),

                  // Folders Grid
                  _folders.isEmpty
                      ? SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(children: [
                                const Icon(Icons.folder_open,
                                    color: Colors.grey, size: 64),
                                const SizedBox(height: 16),
                                const Text('Koi folder nahi hai abhi',
                                    style: TextStyle(color: Colors.grey)),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: _showAddFolderDialog,
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE8884A)),
                                  child: const Text('Pehla folder banao'),
                                ),
                              ]),
                            ),
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) => _FolderCard(
                                folder: _folders[i],
                                compact: compactFolders,
                                onTap: () => _openFolder(
                                    Map<String, dynamic>.from(
                                        _folders[i] as Map)),
                                onTitleDoubleTap: () => _showRenameFolderDialog(
                                  Map<String, dynamic>.from(_folders[i] as Map),
                                ),
                                onSecondaryTapDown: (pos) =>
                                    _showFolderContextMenu(
                                  Map<String, dynamic>.from(_folders[i] as Map),
                                  pos,
                                ),
                              ),
                              childCount: _folders.length,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: folderColumns,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: compactFolders ? 1.25 : 1.1,
                            ),
                          ),
                        ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AddNoteScreen(onSaved: _loadFolders))),
        backgroundColor: const Color(0xFFE8884A),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Note',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2E2E2E)),
          ),
          child: Column(children: [
            Icon(icon, color: const Color(0xFFE8884A), size: 22),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 11),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final dynamic folder;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onTitleDoubleTap;
  final ValueChanged<Offset> onSecondaryTapDown;
  const _FolderCard({
    required this.folder,
    required this.compact,
    required this.onTap,
    required this.onTitleDoubleTap,
    required this.onSecondaryTapDown,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (d) => onSecondaryTapDown(d.globalPosition),
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF2E2E2E)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(folder['icon'] ?? '📁',
                style: TextStyle(fontSize: compact ? 30 : 36)),
            const Spacer(),
            GestureDetector(
              onDoubleTap: onTitleDoubleTap,
              child: Text(folder['name'] ?? '',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            SizedBox(height: compact ? 2 : 4),
            Text('${folder['note_count'] ?? 0} notes',
                style:
                    TextStyle(color: Colors.grey, fontSize: compact ? 11 : 12)),
          ],
        ),
      ),
    );
  }
}
