import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:io';
import '../services/api_service.dart';
import '../services/local_db.dart';
import 'add_note_screen.dart';

class NotesScreen extends StatefulWidget {
  final String folderId;
  final String folderName;
  final String folderIcon;
  const NotesScreen(
      {super.key,
      required this.folderId,
      required this.folderName,
      required this.folderIcon});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with WidgetsBindingObserver {
  List<dynamic> _notes = [];
  bool _loading = true;
  String? _summarizing;
  Timer? _autoRefreshTimer;
  bool _autoRefreshing = false;

  Future<bool> _canDeleteNow() async {
    if (!Platform.isAndroid) return true;
    final health = await ApiService.getServerHealth();
    return health['healthy'] == true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadNotes();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _refreshNotesSilently();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotesSilently();
    }
  }

  Future<void> _loadNotes() async {
    setState(() => _loading = true);
    try {
      final notes = await ApiService.getNotes(folderId: widget.folderId);
      await LocalDB.cacheNotes(notes);
      setState(() => _notes = notes);
    } catch (_) {
      final cached = await LocalDB.getCachedNotes(folderId: widget.folderId);
      setState(() => _notes = cached);
    }
    setState(() => _loading = false);
  }

  Future<void> _refreshNotesSilently() async {
    if (!mounted || _loading || _autoRefreshing) return;
    _autoRefreshing = true;
    try {
      final notes = await ApiService.getNotes(folderId: widget.folderId);
      await LocalDB.cacheNotes(notes);
      if (!mounted) return;
      setState(() => _notes = notes);
    } catch (_) {
      // Keep existing notes on silent failures.
    } finally {
      _autoRefreshing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _summarizeNote(dynamic note) async {
    setState(() => _summarizing = note['id']);
    final summary = await ApiService.summarize(note['content']);
    setState(() => _summarizing = null);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.auto_awesome, color: Color(0xFFE8884A), size: 20),
                SizedBox(width: 8),
                Text('AI Summary',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: SelectableText(
                    summary,
                    style: const TextStyle(
                        color: Color(0xFFE0E0E0), height: 1.6, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNoteDetail(dynamic note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _NoteDetailSheet(
        note: note,
        onEdit: () {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddNoteScreen(
                folderId: widget.folderId,
                existingNote: note,
                onSaved: _loadNotes,
              ),
            ),
          );
        },
        onSummarize: () {
          Navigator.pop(ctx);
          _summarizeNote(note);
        },
      ),
    );
  }

  // Group notes by date
  DateTime? _parseNoteDate(dynamic raw) {
    final input = (raw ?? '').toString().trim();
    if (input.isEmpty) return null;
    try {
      // SQLite CURRENT_TIMESTAMP format is UTC without timezone: "YYYY-MM-DD HH:MM:SS"
      final sqliteUtc = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$');
      if (sqliteUtc.hasMatch(input)) {
        return DateTime.parse('${input.replaceFirst(' ', 'T')}Z').toLocal();
      }
      final parsed = DateTime.parse(input);
      return parsed.isUtc ? parsed.toLocal() : parsed;
    } catch (_) {
      return null;
    }
  }

  Map<String, List<dynamic>> _groupByDate() {
    final grouped = <String, List<dynamic>>{};
    for (final note in _notes) {
      String dateKey = '';
      try {
        final date = _parseNoteDate(note['created_at']);
        if (date == null) {
          dateKey = 'Unknown';
          grouped[dateKey] = [...(grouped[dateKey] ?? []), note];
          continue;
        }
        final today = DateTime.now();
        final yesterday = today.subtract(const Duration(days: 1));
        if (date.day == today.day &&
            date.month == today.month &&
            date.year == today.year) {
          dateKey = 'Aaj';
        } else if (date.day == yesterday.day && date.month == yesterday.month) {
          dateKey = 'Kal';
        } else {
          dateKey = DateFormat('dd MMM yyyy').format(date);
        }
      } catch (_) {
        dateKey = 'Unknown';
      }
      grouped[dateKey] = [...(grouped[dateKey] ?? []), note];
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final groupedNotes = _groupByDate();
    final compactMode = _notes.length >= 20;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Text(widget.folderIcon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text(widget.folderName),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadNotes),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE8884A)))
          : _notes.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.note_outlined,
                            color: Colors.grey, size: 64),
                        const SizedBox(height: 16),
                        const Text('Is folder mein koi note nahi',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => AddNoteScreen(
                                      folderId: widget.folderId,
                                      onSaved: _loadNotes))),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE8884A)),
                          child: const Text('Pehla note banao'),
                        ),
                      ]),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: groupedNotes.entries
                      .map((entry) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Row(children: [
                                  Text(entry.key,
                                      style: const TextStyle(
                                          color: Color(0xFFE8884A),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Divider(
                                          color: Colors.grey
                                              .withValues(alpha: 0.2))),
                                ]),
                              ),
                              ...entry.value.map((note) => _NoteCard(
                                    note: note,
                                    compact: compactMode,
                                    summarizing: _summarizing == note['id'],
                                    onTap: () => _showNoteDetail(note),
                                    onSummarize: () => _summarizeNote(note),
                                    onDelete: () async {
                                      final canDelete = await _canDeleteNow();
                                      if (!context.mounted) return;
                                      if (!canDelete) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Tunnel/server off: Android pe delete disabled. Notes add kar sakte ho.'),
                                            backgroundColor: Colors.orange,
                                          ),
                                        );
                                        return;
                                      }
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor:
                                              const Color(0xFF1A1A1A),
                                          title: const Text('Delete Note?',
                                              style: TextStyle(
                                                  color: Colors.white)),
                                          content: Text(
                                            '"${(note['title'] ?? 'Untitled').toString()}" delete hoga.',
                                            style: const TextStyle(
                                                color: Color(0xFFCCCCCC)),
                                          ),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Cancel')),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok == true) {
                                        await ApiService.deleteNote(note['id']);
                                        _loadNotes();
                                      }
                                    },
                                  )),
                            ],
                          ))
                      .toList(),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AddNoteScreen(
                    folderId: widget.folderId, onSaved: _loadNotes))),
        backgroundColor: const Color(0xFFE8884A),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _NoteDetailSheet extends StatefulWidget {
  final dynamic note;
  final VoidCallback onEdit;
  final VoidCallback onSummarize;

  const _NoteDetailSheet({
    required this.note,
    required this.onEdit,
    required this.onSummarize,
  });

  @override
  State<_NoteDetailSheet> createState() => _NoteDetailSheetState();
}

class _NoteDetailSheetState extends State<_NoteDetailSheet> {
  bool _loading = true;
  Map<String, dynamic> _note = {};
  List<dynamic> _media = [];

  DateTime? _parseNoteDate(dynamic raw) {
    final input = (raw ?? '').toString().trim();
    if (input.isEmpty) return null;
    try {
      final sqliteUtc = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$');
      if (sqliteUtc.hasMatch(input)) {
        return DateTime.parse('${input.replaceFirst(' ', 'T')}Z').toLocal();
      }
      final parsed = DateTime.parse(input);
      return parsed.isUtc ? parsed.toLocal() : parsed;
    } catch (_) {
      return null;
    }
  }

  String _formatDetailDate(dynamic raw) {
    final dt = _parseNoteDate(raw);
    if (dt == null) return '';
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  @override
  void initState() {
    super.initState();
    _note = Map<String, dynamic>.from(widget.note as Map);
    _loadNoteDetail();
  }

  Future<void> _loadNoteDetail() async {
    try {
      final id = widget.note['id']?.toString();
      if (id == null || id.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final res = await ApiService.getNoteById(id);
      final note = Map<String, dynamic>.from(res['note'] ?? widget.note);
      final media = (note['media'] as List<dynamic>? ?? <dynamic>[]);
      if (!mounted) return;
      setState(() {
        _note = note;
        _media = media;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _isImageType(String typeOrPath) {
    final v = typeOrPath.toLowerCase();
    return v.contains('image') ||
        v.endsWith('.png') ||
        v.endsWith('.jpg') ||
        v.endsWith('.jpeg') ||
        v.endsWith('.webp');
  }

  bool _isVideoType(String typeOrPath) {
    final v = typeOrPath.toLowerCase();
    return v.contains('video') ||
        v.endsWith('.mp4') ||
        v.endsWith('.mov') ||
        v.endsWith('.m4v');
  }

  bool _isAudioType(String typeOrPath) {
    final v = typeOrPath.toLowerCase();
    return v.contains('audio') ||
        v.endsWith('.mp3') ||
        v.endsWith('.m4a') ||
        v.endsWith('.wav') ||
        v.endsWith('.aac');
  }

  String _mediaUrl(String path) {
    return ApiService.resolveMediaUrl(filePath: path);
  }

  String _mediaUrlFromItem(dynamic media) {
    final id = (media['id'] ?? '').toString();
    final path = (media['file_path'] ?? '').toString();
    return ApiService.resolveMediaUrl(mediaId: id, filePath: path);
  }

  Future<void> _openMedia(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _mediaTitle(dynamic media) {
    final display = (media['display_name'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;
    final raw = (media['file_name'] ?? 'media').toString();
    return raw;
  }

  String _mediaCaption(dynamic media) {
    return (media['caption'] ?? '').toString().trim();
  }

  void _openImageGallery(List<dynamic> images, int initialIndex) {
    int current = initialIndex;
    final controller = PageController(initialPage: initialIndex);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final item = images[current] as Map<String, dynamic>;
          final title = _mediaTitle(item);
          final caption = _mediaCaption(item);
          final total = images.length;
          return Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(8),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (caption.isNotEmpty)
                                Text(
                                  caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFB9B9B9),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '${current + 1}/$total',
                          style: const TextStyle(
                              color: Color(0xFFE8884A), fontSize: 12),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFF2A2A2A)),
                  Expanded(
                    child: PageView.builder(
                      controller: controller,
                      itemCount: images.length,
                      onPageChanged: (idx) =>
                          setDialogState(() => current = idx),
                      itemBuilder: (ctx, i) {
                        final media = images[i] as Map<String, dynamic>;
                        final imageUrl = _mediaUrlFromItem(media);
                        return InteractiveViewer(
                          minScale: 0.7,
                          maxScale: 5,
                          child: Center(
                            child: Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              headers: ApiService.authOnlyHeaders,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.grey,
                                size: 40,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFE8884A)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        _note['title'] ?? 'Note',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Color(0xFFE8884A)),
                      onPressed: widget.onEdit,
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_awesome,
                          color: Color(0xFFE8884A)),
                      onPressed: widget.onSummarize,
                    ),
                  ]),
                  Text(
                    _formatDetailDate(_note['created_at']),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  const Divider(color: Color(0xFF2E2E2E), height: 24),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: controller,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _note['content'] ?? '',
                            style: const TextStyle(
                              color: Color(0xFFE0E0E0),
                              fontSize: 15,
                              height: 1.7,
                            ),
                          ),
                          if (_media.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Media',
                              style: TextStyle(
                                color: Color(0xFFE8884A),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Builder(
                              builder: (ctx) {
                                final imageMedia = _media.where((m) {
                                  final path =
                                      (m['file_path'] ?? '').toString();
                                  final type =
                                      (m['file_type'] ?? '').toString();
                                  return _isImageType(type) ||
                                      _isImageType(path);
                                }).toList();
                                final otherMedia = _media.where((m) {
                                  final path =
                                      (m['file_path'] ?? '').toString();
                                  final type =
                                      (m['file_type'] ?? '').toString();
                                  return !(_isImageType(type) ||
                                      _isImageType(path));
                                }).toList();

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (imageMedia.isNotEmpty)
                                      GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: imageMedia.length,
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          crossAxisSpacing: 10,
                                          mainAxisSpacing: 10,
                                          childAspectRatio: 1.0,
                                        ),
                                        itemBuilder: (ctx, i) {
                                          final m = imageMedia[i];
                                          final url = _mediaUrlFromItem(m);
                                          final title = _mediaTitle(m);
                                          final caption = _mediaCaption(m);
                                          return GestureDetector(
                                            onTap: () => _openImageGallery(
                                                imageMedia, i),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                    color: const Color(
                                                        0xFF2E2E2E)),
                                                color: const Color(0xFF101010),
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    Container(
                                                      color: const Color(
                                                          0xFF0D0D0D),
                                                      child: Image.network(
                                                        url,
                                                        fit: BoxFit.contain,
                                                        headers: ApiService
                                                            .authOnlyHeaders,
                                                        errorBuilder:
                                                            (_, __, ___) =>
                                                                const Center(
                                                          child: Icon(
                                                            Icons
                                                                .broken_image_outlined,
                                                            color: Colors.grey,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Positioned(
                                                      left: 0,
                                                      right: 0,
                                                      bottom: 0,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8,
                                                                vertical: 7),
                                                        decoration:
                                                            const BoxDecoration(
                                                          gradient:
                                                              LinearGradient(
                                                            begin: Alignment
                                                                .topCenter,
                                                            end: Alignment
                                                                .bottomCenter,
                                                            colors: [
                                                              Color(0x00000000),
                                                              Color(0xB3000000)
                                                            ],
                                                          ),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              title,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            if (caption
                                                                .isNotEmpty)
                                                              Text(
                                                                caption,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style:
                                                                    const TextStyle(
                                                                  color: Color(
                                                                      0xFFD0D0D0),
                                                                  fontSize: 10,
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    if (otherMedia.isNotEmpty) ...[
                                      if (imageMedia.isNotEmpty)
                                        const SizedBox(height: 10),
                                      ...otherMedia.map((m) {
                                        final path =
                                            (m['file_path'] ?? '').toString();
                                        final fileType =
                                            (m['file_type'] ?? '').toString();
                                        final url = _mediaUrl(path);
                                        final icon = _isVideoType(fileType) ||
                                                _isVideoType(path)
                                            ? Icons.play_circle_outline
                                            : _isAudioType(fileType) ||
                                                    _isAudioType(path)
                                                ? Icons.graphic_eq
                                                : Icons
                                                    .insert_drive_file_outlined;
                                        final title = _mediaTitle(m);
                                        final caption = _mediaCaption(m);
                                        return ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(icon,
                                              color: const Color(0xFFE8884A)),
                                          title: Text(
                                            title,
                                            style: const TextStyle(
                                                color: Colors.white70),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: caption.isNotEmpty
                                              ? Text(
                                                  caption,
                                                  style: const TextStyle(
                                                      color: Color(0xFF9E9E9E),
                                                      fontSize: 12),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                )
                                              : null,
                                          trailing: const Icon(
                                              Icons.open_in_new,
                                              color: Colors.grey,
                                              size: 18),
                                          onTap: () => _openMedia(url),
                                        );
                                      }),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final dynamic note;
  final bool compact;
  final bool summarizing;
  final VoidCallback onTap;
  final VoidCallback onSummarize;
  final VoidCallback onDelete;

  const _NoteCard({
    required this.note,
    required this.compact,
    required this.summarizing,
    required this.onTap,
    required this.onSummarize,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2E2E2E)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (note['title'] ?? 'Untitled').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 13 : 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: compact ? 6 : 8),
            Text(
              note['content'] ?? '',
              maxLines: compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFE0E0E0),
                fontSize: compact ? 13 : 14,
                height: compact ? 1.35 : 1.5,
              ),
            ),
            SizedBox(height: compact ? 8 : 10),
            Row(children: [
              Icon(Icons.access_time,
                  color: Colors.grey, size: compact ? 11 : 12),
              const SizedBox(width: 4),
              Text(
                _formatTime(note['created_at']),
                style:
                    TextStyle(color: Colors.grey, fontSize: compact ? 10 : 11),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onSummarize,
                child: summarizing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Color(0xFFE8884A), strokeWidth: 2))
                    : Icon(Icons.auto_awesome,
                        color: const Color(0xFFE8884A),
                        size: compact ? 16 : 18),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.delete_outline,
                    color: Colors.grey, size: compact ? 16 : 18),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return '';
    try {
      final sqliteUtc = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$');
      DateTime parsed;
      if (sqliteUtc.hasMatch(dateStr.trim())) {
        parsed = DateTime.parse('${dateStr.replaceFirst(' ', 'T')}Z').toLocal();
      } else {
        final dt = DateTime.parse(dateStr);
        parsed = dt.isUtc ? dt.toLocal() : dt;
      }
      return DateFormat('dd MMM, hh:mm a').format(parsed);
    } catch (_) {
      return '';
    }
  }
}
