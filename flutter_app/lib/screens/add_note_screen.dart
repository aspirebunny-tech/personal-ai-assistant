import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';

class _PendingMediaItem {
  final String path;
  final String originalName;
  final String kind;
  String displayName;
  String caption;

  _PendingMediaItem({
    required this.path,
    required this.originalName,
    required this.kind,
    String? displayName,
  })  : displayName = (displayName == null || displayName.trim().isEmpty)
            ? originalName
            : displayName.trim(),
        caption = '';
}

class AddNoteScreen extends StatefulWidget {
  final String? folderId;
  final String? folderName;
  final dynamic existingNote;
  final VoidCallback? onSaved;

  const AddNoteScreen(
      {super.key,
      this.folderId,
      this.folderName,
      this.existingNote,
      this.onSaved});

  @override
  State<AddNoteScreen> createState() => _AddNoteScreenState();
}

class _AddNoteScreenState extends State<AddNoteScreen> {
  // Safe mode: keep transcript as spoken, avoid aggressive post-corrections.
  static const bool _enableAiPostCorrection = false;
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _initialTitle = '';
  String _initialContent = '';
  String? _initialFolderId;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _saving = false;
  String? _selectedFolderId;
  List<dynamic> _folders = [];
  String? _voiceLocale;
  String _partialText = '';
  String _latestTranscript = '';
  String _lastCommittedPreview = '';
  bool _manualStopRequested = false;
  int _restartAttempts = 0;
  bool _restartInProgress = false;
  bool _startInProgress = false;
  bool _toggleInProgress = false;
  DateTime _toggleStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _finalizeInProgress = false;
  Timer? _cleanupTimer;
  Timer? _speechWatchdogTimer;
  bool _cleanupInFlight = false;
  String _lastCleanedSnapshot = '';
  DateTime _lastCommitAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSpeechActivityAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _manualRefineLoading = false;
  String? _refineUndoBackup;
  bool _refineUndoActive = false;
  Timer? _refineUndoTimer;
  final ImagePicker _imagePicker = ImagePicker();
  final List<_PendingMediaItem> _pendingMedia = [];
  final List<Map<String, dynamic>> _existingMedia = [];
  bool _loadingExistingMedia = false;
  final SpeechToText _speech = SpeechToText();
  Set<String> _availableLocales = {};

  @override
  void initState() {
    super.initState();
    _selectedFolderId = widget.folderId;
    if (widget.existingNote != null) {
      _titleCtrl.text = (widget.existingNote['title'] ?? '').toString();
      _contentCtrl.text = widget.existingNote['content'] ?? '';
      _loadExistingMediaForEdit();
    }
    _initialTitle = _titleCtrl.text.trim();
    _initialContent = _contentCtrl.text.trim();
    _initialFolderId = _selectedFolderId;
    _initSpeech();
    _loadFolders();
  }

  bool _isImageType(String typeOrPath) {
    final v = typeOrPath.toLowerCase();
    return v.contains('image') ||
        v.endsWith('.png') ||
        v.endsWith('.jpg') ||
        v.endsWith('.jpeg') ||
        v.endsWith('.webp');
  }

  String _mediaUrlFromItem(Map<String, dynamic> media) {
    final id = (media['id'] ?? '').toString();
    final path = (media['file_path'] ?? '').toString();
    return ApiService.resolveMediaUrl(mediaId: id, filePath: path);
  }

  Future<void> _loadExistingMediaForEdit() async {
    final id = widget.existingNote?['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _loadingExistingMedia = true);
    try {
      final res = await ApiService.getNoteById(id);
      final note = Map<String, dynamic>.from(res['note'] ?? {});
      final mediaList = (note['media'] as List<dynamic>? ?? <dynamic>[])
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        for (final m in mediaList) {
          final fileName = (m['file_name'] ?? '').toString();
          final display = (m['display_name'] ?? '').toString().trim();
          final caption = (m['caption'] ?? '').toString().trim();
          m['display_name'] = display.isNotEmpty ? display : fileName;
          m['caption'] = caption;
          m['_orig_display_name'] = m['display_name'];
          m['_orig_caption'] = m['caption'];
        }
        _existingMedia
          ..clear()
          ..addAll(mediaList);
        final latestContent = (note['content'] ?? '').toString();
        if (latestContent.trim().isNotEmpty) {
          _contentCtrl.text = latestContent;
          _contentCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _contentCtrl.text.length),
          );
        }
      });
    } catch (_) {
      // silent: edit screen should still work without media load
    } finally {
      if (mounted) setState(() => _loadingExistingMedia = false);
    }
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: _handleSpeechError,
      onStatus: _handleSpeechStatus,
    );
    if (available) {
      final locales = await _speech.locales();
      _availableLocales = locales.map((e) => e.localeId).toSet();
      debugPrint('Speech locales: ${_availableLocales.join(', ')}');
    }
    debugPrint('Speech available: $available');
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _startListeningSession() async {
    if (_startInProgress) return;
    _startInProgress = true;
    final selectedLocale = _voiceLocale;
    final effectiveLocale =
        (selectedLocale == null || _availableLocales.contains(selectedLocale))
            ? selectedLocale
            : null;
    try {
      await _speech.cancel();
      await Future.delayed(const Duration(milliseconds: 120));
      await _speech.listen(
        onResult: _onSpeechResult,
        localeId: effectiveLocale,
        pauseFor: const Duration(seconds: 20),
        listenFor: const Duration(minutes: 30),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          onDevice: false,
          listenMode: ListenMode.dictation,
        ),
      );
    } finally {
      _startInProgress = false;
    }
  }

  void _handleSpeechError(SpeechRecognitionError err) {
    debugPrint('Speech error: ${err.errorMsg}');
    if (!mounted) return;
    if (_isListening && !_manualStopRequested) {
      _scheduleRestart();
    }
  }

  void _handleSpeechStatus(String status) {
    debugPrint('Speech status: $status');
    if (!mounted) return;
    if (status == 'listening') {
      _restartAttempts = 0;
      _lastSpeechActivityAt = DateTime.now();
      _ensureSpeechWatchdog();
      return;
    }
    if (status == 'done' || status == 'notListening') {
      if (_manualStopRequested) {
        // Manual stop flow does its own finalize/commit; do not wipe live text here.
        return;
      }
      if (_isListening && !_manualStopRequested) {
        _commitLivePreview();
      }
      if (mounted) setState(() => _partialText = '');
      _schedulePostSpeechCleanup();
      if (_isListening && !_manualStopRequested) {
        _scheduleRestart();
      }
    }
  }

  void _scheduleRestart() {
    _restartAttempts += 1;
    final delayMs = 350 + (_restartAttempts > 6 ? 900 : _restartAttempts * 180);
    Future.delayed(Duration(milliseconds: delayMs), () async {
      if (!mounted ||
          !_isListening ||
          _manualStopRequested ||
          _restartInProgress) {
        return;
      }
      try {
        _restartInProgress = true;
        await _speech.cancel();
        await Future.delayed(const Duration(milliseconds: 120));
        _latestTranscript = '';
        await _startListeningSession();
      } catch (e) {
        debugPrint('Speech restart failed: $e');
      } finally {
        _restartInProgress = false;
      }
    });
  }

  void _ensureSpeechWatchdog() {
    _speechWatchdogTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted ||
          !_isListening ||
          _manualStopRequested ||
          _restartInProgress) {
        return;
      }
      if (DateTime.now().difference(_lastSpeechActivityAt) >
          const Duration(seconds: 9)) {
        _lastSpeechActivityAt = DateTime.now();
        _scheduleRestart();
      }
    });
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    final text = result.recognizedWords;
    final isFinal = result.finalResult;
    debugPrint('[MIC] text="$text" isFinal=$isFinal');
    final words = text.trim();
    if (words.isEmpty) return;
    _lastSpeechActivityAt = DateTime.now();
    _latestTranscript = words;
    if (mounted) setState(() => _partialText = words);
    if (isFinal) {
      _commitLivePreview();
      _schedulePostSpeechCleanup();
    }
  }

  void _commitLivePreview() {
    final transcript = _latestTranscript.trim().isNotEmpty
        ? _latestTranscript.trim()
        : _partialText.trim();
    if (transcript.isEmpty || !mounted) return;
    String delta = transcript;
    if (_lastCommittedPreview.isNotEmpty &&
        transcript.startsWith(_lastCommittedPreview)) {
      delta = transcript.substring(_lastCommittedPreview.length).trim();
    }
    if (delta.isEmpty) return;
    setState(() {
      final base = _contentCtrl.text.trimRight();
      _contentCtrl.text = base.isEmpty ? delta : '$base $delta';
      _contentCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _contentCtrl.text.length),
      );
      _lastCommittedPreview = transcript;
      _lastCommitAt = DateTime.now();
    });
  }

  void _schedulePostSpeechCleanup() {
    if (!_enableAiPostCorrection) return;
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(milliseconds: 1400), () async {
      if (!mounted || _cleanupInFlight) return;
      if (DateTime.now().difference(_lastCommitAt) <
          const Duration(milliseconds: 1200)) {
        return;
      }
      final current = _contentCtrl.text.trim();
      if (current.length < 20) return;
      final pivot = current.length > 900 ? current.length - 900 : 0;
      final prefix = current.substring(0, pivot);
      final tail = current.substring(pivot);
      if (tail == _lastCleanedSnapshot) return;
      _cleanupInFlight = true;
      try {
        final res = await ApiService.cleanupTranscriptText(tail);
        final cleaned = (res['cleaned_text'] ?? '').toString().trim();
        if (!mounted || cleaned.isEmpty || cleaned == tail) return;
        setState(() {
          _contentCtrl.text = '$prefix$cleaned';
          _contentCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _contentCtrl.text.length),
          );
        });
        _lastCleanedSnapshot = cleaned;
      } finally {
        _cleanupInFlight = false;
      }
    });
  }

  Future<void> _runForcedCleanupBeforeSave() async {
    final current = _contentCtrl.text.trim();
    if (current.length < 20) return;
    final pivot = current.length > 1400 ? current.length - 1400 : 0;
    final prefix = current.substring(0, pivot);
    final tail = current.substring(pivot);
    final res = await ApiService.cleanupTranscriptText(tail);
    final cleaned = (res['cleaned_text'] ?? '').toString().trim();
    if (cleaned.isEmpty || cleaned == tail) return;
    setState(() {
      _contentCtrl.text = '$prefix$cleaned';
      _contentCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _contentCtrl.text.length),
      );
    });
  }

  List<String> _words(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  int _countChangedWords(String original, String refined) {
    final originalSet = _words(original).toSet();
    final refinedWords = _words(refined);
    return refinedWords.where((w) => !originalSet.contains(w)).length;
  }

  Widget _buildHighlightedRefinedText(String original, String refined) {
    final originalSet = _words(original).toSet();
    final spans = <TextSpan>[];
    final parts = refined.split(RegExp(r'(\s+)'));
    for (final part in parts) {
      if (part.trim().isEmpty) {
        spans.add(TextSpan(text: part));
        continue;
      }
      final key = part
          .toLowerCase()
          .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
      final changed = key.isNotEmpty && !originalSet.contains(key);
      spans.add(
        TextSpan(
          text: part,
          style: TextStyle(
            color: changed ? const Color(0xFFE8884A) : Colors.white,
            fontWeight: changed ? FontWeight.w700 : FontWeight.w400,
            backgroundColor:
                changed ? const Color(0x33E8884A) : Colors.transparent,
          ),
        ),
      );
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, height: 1.45, color: Colors.white),
        children: spans,
      ),
    );
  }

  Future<void> _runManualAiRefinePreview() async {
    final candidate = _contentCtrl.text.trim().isNotEmpty
        ? _contentCtrl.text.trim()
        : _partialText.trim();
    final original = candidate;
    if (original.length < 12) {
      debugPrint('AI refine skipped: not enough content');
      return;
    }
    setState(() => _manualRefineLoading = true);
    try {
      final res = await ApiService.cleanupTranscriptText(original);
      final proposed = (res['cleaned_text'] ?? '').toString().trim();
      if (!mounted) return;
      if (proposed.isEmpty || proposed == original) {
        debugPrint('AI refine: no useful changes');
        return;
      }

      final changedWords = _countChangedWords(original, proposed);
      final changedChars = (proposed.length - original.length).abs();
      final apply = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF171717),
          title: const Text('AI Refine Preview',
              style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Summary: ~$changedWords word changes, ~$changedChars char difference',
                    style:
                        const TextStyle(color: Color(0xFFBDBDBD), fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Highlighted Changes (orange):',
                    style: TextStyle(color: Color(0xFFE8884A), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101010),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2E2E2E)),
                    ),
                    child: _buildHighlightedRefinedText(original, proposed),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Original',
                  style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8884A),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply Changes'),
            ),
          ],
        ),
      );

      if (apply == true && mounted) {
        final backup = _contentCtrl.text;
        setState(() {
          _contentCtrl.text = proposed;
          _contentCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _contentCtrl.text.length),
          );
          _refineUndoBackup = backup;
          _refineUndoActive = true;
        });
        _refineUndoTimer?.cancel();
        _refineUndoTimer = Timer(const Duration(seconds: 20), () {
          if (!mounted) return;
          setState(() {
            _refineUndoActive = false;
            _refineUndoBackup = null;
          });
        });
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('AI refine failed: $e');
    } finally {
      if (mounted) setState(() => _manualRefineLoading = false);
    }
  }

  void _undoLastRefine() {
    if (!_refineUndoActive || _refineUndoBackup == null || !mounted) return;
    final backup = _refineUndoBackup!;
    setState(() {
      _contentCtrl.text = backup;
      _contentCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _contentCtrl.text.length),
      );
      _refineUndoActive = false;
      _refineUndoBackup = null;
    });
    _refineUndoTimer?.cancel();
  }

  String _kindFromPath(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png') ||
        p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.webp') ||
        p.endsWith('.heic')) {
      return 'image';
    }
    if (p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.m4v') ||
        p.endsWith('.avi') ||
        p.endsWith('.mkv')) {
      return 'video';
    }
    if (p.endsWith('.m4a') ||
        p.endsWith('.mp3') ||
        p.endsWith('.wav') ||
        p.endsWith('.aac') ||
        p.endsWith('.ogg')) {
      return 'audio';
    }
    return 'file';
  }

  Future<bool> _ensureMediaPermission({required bool camera}) async {
    if (!Platform.isAndroid) return true;
    if (camera) {
      final status = await Permission.camera.request();
      return status.isGranted;
    }
    final photos = await Permission.photos.request();
    if (photos.isGranted || photos.isLimited) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  Future<void> _showUiMessage(String text) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Upload', style: TextStyle(color: Colors.white)),
        content: Text(text, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    try {
      final ok = await _ensureMediaPermission(camera: true);
      if (!ok) {
        await _showUiMessage('Camera permission required');
        return;
      }
      final file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );
      if (file == null || !mounted) return;
      setState(() {
        _pendingMedia.add(
          _PendingMediaItem(
            path: file.path,
            originalName: file.name,
            kind: 'image',
          ),
        );
      });
    } catch (e) {
      await _showUiMessage('Camera open failed: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final ok = await _ensureMediaPermission(camera: false);
      if (!ok) {
        await _showUiMessage('Gallery permission required');
        return;
      }
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (file == null || !mounted) return;
      setState(() {
        _pendingMedia.add(
          _PendingMediaItem(
            path: file.path,
            originalName: file.name,
            kind: 'image',
          ),
        );
      });
    } catch (e) {
      await _showUiMessage('Gallery open failed: $e');
    }
  }

  Future<void> _pickAnyMediaFile() async {
    try {
      final ok = await _ensureMediaPermission(camera: false);
      if (!ok) {
        await _showUiMessage('File access permission required');
        return;
      }
      // FileType.media is flaky on some desktop targets; FileType.any is more reliable.
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (res == null || !mounted) {
        await _showUiMessage('Picker cancelled.');
        return;
      }
      int added = 0;
      setState(() {
        for (final file in res.files) {
          final path = file.path;
          if (path == null || path.isEmpty) continue;
          final kind = _kindFromPath(path);
          if (kind == 'file' && !Platform.isAndroid) {
            // Desktop par generic files bhi allow karte hain.
            _pendingMedia.add(
              _PendingMediaItem(
                path: path,
                originalName: file.name,
                kind: 'file',
              ),
            );
            added += 1;
            continue;
          }
          _pendingMedia.add(
            _PendingMediaItem(
              path: path,
              originalName: file.name,
              kind: kind,
            ),
          );
          added += 1;
        }
      });
      if (added == 0 && mounted) {
        await _showUiMessage('No valid file selected.');
      }
    } catch (e) {
      await _showUiMessage('File picker failed: $e');
    }
  }

  Future<void> _openAttachPicker() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (Platform.isAndroid)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined,
                    color: Color(0xFFE8884A)),
                title:
                    const Text('Camera', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickFromCamera();
                },
              ),
            if (Platform.isAndroid)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: Color(0xFFE8884A)),
                title: const Text('Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _pickFromGallery();
                },
              ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Color(0xFFE8884A)),
              title: Text(
                Platform.isAndroid ? 'Files' : 'Browse Mac Files',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _pickAnyMediaFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finalizeListeningSession() async {
    if (_finalizeInProgress) return;
    _finalizeInProgress = true;
    try {
      try {
        await _speech.stop().timeout(const Duration(milliseconds: 1200));
      } catch (_) {
        try {
          await _speech.cancel().timeout(const Duration(milliseconds: 800));
        } catch (_) {}
      }
      _commitLivePreview();
      _schedulePostSpeechCleanup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice finalize failed: $e')),
        );
      }
    } finally {
      _finalizeInProgress = false;
    }
  }

  Future<void> _loadFolders() async {
    try {
      final folders = await ApiService.getFolders();
      setState(() => _folders = folders);
    } catch (_) {
      final cached = await LocalDB.getCachedFolders();
      setState(() => _folders = cached);
    }
  }

  void _toggleListening() async {
    if (_toggleInProgress &&
        DateTime.now().difference(_toggleStartedAt) <
            const Duration(seconds: 5)) {
      return;
    }
    _toggleInProgress = true;
    _toggleStartedAt = DateTime.now();
    try {
      if (_isListening) {
        _manualStopRequested = true;
        if (mounted) setState(() => _isListening = false);
        _speechWatchdogTimer?.cancel();
        _speechWatchdogTimer = null;
        await _finalizeListeningSession();
        if (mounted) {
          setState(() {
            _partialText = '';
            _latestTranscript = '';
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
        if (!_speechAvailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Voice recognition available nahi hai')),
          );
          return;
        }
        if (mounted) {
          setState(() {
            _isListening = true;
            _manualStopRequested = false;
            _restartAttempts = 0;
            _partialText = '';
            _latestTranscript = '';
            _lastCommittedPreview = '';
          });
        }
        try {
          _lastSpeechActivityAt = DateTime.now();
          _ensureSpeechWatchdog();
          await _startListeningSession();
        } catch (e) {
          _manualStopRequested = true;
          if (mounted) {
            setState(() => _isListening = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Mic start failed: $e')),
            );
          }
        }
      }
    } finally {
      _toggleInProgress = false;
      _toggleStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Title likho pehle')));
      return;
    }
    if (content.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Kuch toh likho pehle!')));
      return;
    }

    bool existingMediaChanged = false;
    for (final m in _existingMedia) {
      final nextName = (m['display_name'] ?? '').toString().trim();
      final nextCaption = (m['caption'] ?? '').toString().trim();
      final oldName = (m['_orig_display_name'] ?? '').toString().trim();
      final oldCaption = (m['_orig_caption'] ?? '').toString().trim();
      if (nextName != oldName || nextCaption != oldCaption) {
        existingMediaChanged = true;
        break;
      }
    }

    final noTextChange = title == _initialTitle &&
        content == _initialContent &&
        _selectedFolderId == _initialFolderId;
    final noMediaChange = _pendingMedia.isEmpty && !existingMediaChanged;
    if (widget.existingNote != null && noTextChange && noMediaChange) {
      widget.onSaved?.call();
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);
    String correctedContent = content;

    try {
      if (_isListening) {
        _manualStopRequested = true;
        if (mounted) setState(() => _isListening = false);
        _speechWatchdogTimer?.cancel();
        _speechWatchdogTimer = null;
        await _finalizeListeningSession();
        if (mounted) {
          setState(() {
            _partialText = '';
            _latestTranscript = '';
          });
        }
      }
      if (_enableAiPostCorrection) {
        await _runForcedCleanupBeforeSave();
      }
      correctedContent = _contentCtrl.text.trim();
      final connectivity = await Connectivity().checkConnectivity();
      final hasInternet = !connectivity.contains(ConnectivityResult.none);
      bool canReachServer = false;
      if (hasInternet) {
        final health = await ApiService.getServerHealth(
          timeout: const Duration(milliseconds: 900),
        );
        canReachServer = health['healthy'] == true;
      }

      if (canReachServer) {
        String? targetNoteId;
        if (widget.existingNote != null) {
          targetNoteId = widget.existingNote['id']?.toString();
          await ApiService.updateNote(
              widget.existingNote['id'], correctedContent,
              title: title, folderId: _selectedFolderId);
        } else {
          final created = await ApiService.createNote(
              content: correctedContent,
              title: title,
              folderId: _selectedFolderId);
          targetNoteId = created['note']?['id']?.toString();
        }
        final pendingCopy = List<_PendingMediaItem>.from(_pendingMedia);
        final existingCopy =
            _existingMedia.map((m) => Map<String, dynamic>.from(m)).toList();
        if (mounted) {
          setState(() => _pendingMedia.clear());
        }
        // Non-blocking: heavy media uploads/metadata updates run in background.
        if (targetNoteId != null &&
            (pendingCopy.isNotEmpty || existingCopy.isNotEmpty)) {
          final noteId = targetNoteId;
          unawaited(Future<void>(() async {
            try {
              for (final item in pendingCopy) {
                await ApiService.uploadNoteMedia(
                  noteId: noteId,
                  filePath: item.path,
                  displayName: item.displayName,
                  caption: item.caption,
                );
              }
              for (final m in existingCopy) {
                final mediaId = (m['id'] ?? '').toString();
                if (mediaId.isEmpty) continue;
                final nextName = (m['display_name'] ?? '').toString().trim();
                final nextCaption = (m['caption'] ?? '').toString().trim();
                final oldName =
                    (m['_orig_display_name'] ?? '').toString().trim();
                final oldCaption = (m['_orig_caption'] ?? '').toString().trim();
                if (nextName == oldName && nextCaption == oldCaption) continue;
                await ApiService.updateMediaInfo(
                  mediaId: mediaId,
                  displayName: nextName,
                  caption: nextCaption,
                );
              }
            } catch (e) {
              debugPrint('Background media sync failed: $e');
            }
          }));
        }
      } else {
        await LocalDB.savePendingNote(
          id: const Uuid().v4(),
          content: correctedContent,
          title: title,
          folderId: _selectedFolderId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Offline saved! Internet aate hi sync hoga ✅'),
            backgroundColor: Colors.orange,
          ));
        }
        if (_pendingMedia.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Media upload online hone par hi hoga.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      widget.onSaved?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      // Fast fallback: local save even if online call fails.
      try {
        await LocalDB.savePendingNote(
          id: const Uuid().v4(),
          content: correctedContent,
          title: title,
          folderId: _selectedFolderId,
        );
        if (mounted) {
          widget.onSaved?.call();
          Navigator.pop(context);
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Save failed: $e')),
          );
        }
      }
    }

    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    if (_isListening) {
      _manualStopRequested = true;
      _speech.stop();
    }
    _contentCtrl.dispose();
    _titleCtrl.dispose();
    _cleanupTimer?.cancel();
    _speechWatchdogTimer?.cancel();
    _refineUndoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final hideMediaWhileTyping = Platform.isAndroid && keyboardVisible;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title:
            Text(widget.existingNote != null ? 'Note Edit Karo' : 'Naya Note'),
        actions: [
          if (_saving)
            const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Color(0xFFE8884A), strokeWidth: 2)))
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save',
                  style: TextStyle(
                      color: Color(0xFFE8884A),
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: GestureDetector(
        onTap: _toggleListening,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _isListening ? Colors.red : const Color(0xFFE8884A),
            shape: BoxShape.circle,
            boxShadow: _isListening
                ? [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    )
                  ]
                : [],
          ),
          child: Icon(
            _isListening ? Icons.stop : Icons.mic,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
      body: Column(
        children: [
          if (_folders.isNotEmpty)
            Container(
              height: 50,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _folders.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) {
                    return _FolderChip(
                      label: 'Koi folder nahi',
                      icon: '📋',
                      selected: _selectedFolderId == null,
                      onTap: () => setState(() => _selectedFolderId = null),
                    );
                  }
                  final folder = _folders[i - 1];
                  return _FolderChip(
                    label: folder['name'],
                    icon: folder['icon'] ?? '📁',
                    selected: _selectedFolderId == folder['id'],
                    onTap: () =>
                        setState(() => _selectedFolderId = folder['id']),
                  );
                },
              ),
            ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _titleCtrl,
                    maxLines: 1,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Note Title',
                      hintStyle: const TextStyle(
                          color: Color(0xFF666666), fontSize: 16),
                      filled: true,
                      fillColor: const Color(0xFF131313),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE8884A)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TextField(
                      controller: _contentCtrl,
                      maxLines: null,
                      expands: true,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16, height: 1.6),
                      decoration: const InputDecoration(
                        hintText: 'Apna note yahan likho ya voice se bolo...',
                        hintStyle:
                            TextStyle(color: Color(0xFF555555), fontSize: 15),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Listening indicator
          if (_isListening)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      const Text('Sun raha hoon...',
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                  ),
                  if (_partialText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 120),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151515),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2E2E2E)),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            _partialText,
                            style: const TextStyle(
                              color: Color(0xFFCCCCCC),
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.existingNote != null && _loadingExistingMedia)
            const Padding(
              padding: EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: Color(0xFFE8884A),
                backgroundColor: Color(0xFF2E2E2E),
              ),
            ),
          if (_existingMedia.isNotEmpty && !hideMediaWhileTyping)
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _existingMedia.length,
                itemBuilder: (ctx, i) {
                  final m = _existingMedia[i];
                  final path = (m['file_path'] ?? '').toString();
                  final mediaUrl = _mediaUrlFromItem(m);
                  final type = (m['file_type'] ?? '').toString();
                  final isImage = _isImageType(type) || _isImageType(path);
                  final icon = type.startsWith('video/')
                      ? Icons.videocam_outlined
                      : type.startsWith('audio/')
                          ? Icons.audio_file_outlined
                          : Icons.attach_file;
                  return Container(
                    key: ValueKey('existing-media-${m['id']}-$i'),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2E2E2E)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 56,
                            height: 56,
                            color: const Color(0xFF101010),
                            child: isImage
                                ? Image.network(
                                    mediaUrl,
                                    fit: BoxFit.cover,
                                    headers: ApiService.authOnlyHeaders,
                                    errorBuilder: (_, __, ___) => Icon(
                                      icon,
                                      color: const Color(0xFFE8884A),
                                      size: 20,
                                    ),
                                  )
                                : Icon(
                                    icon,
                                    color: const Color(0xFFE8884A),
                                    size: 22,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                initialValue:
                                    (m['display_name'] ?? '').toString(),
                                onChanged: (v) => m['display_name'] = v.trim(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: const Color(0xFF121212),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  labelText: 'Name',
                                  hintText: 'Photo/File name',
                                  labelStyle: const TextStyle(
                                    color: Color(0xFF9A9A9A),
                                    fontSize: 10,
                                  ),
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF7A7A7A),
                                    fontSize: 11,
                                  ),
                                  border: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFF343434)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFF343434)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE8884A)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                initialValue: (m['caption'] ?? '').toString(),
                                onChanged: (v) => m['caption'] = v.trim(),
                                style: const TextStyle(
                                  color: Color(0xFFCCCCCC),
                                  fontSize: 11,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: const Color(0xFF121212),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  labelText: 'Description',
                                  hintText:
                                      'Isme kya hai / kaun hai (AI context)',
                                  labelStyle: const TextStyle(
                                    color: Color(0xFF9A9A9A),
                                    fontSize: 10,
                                  ),
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF666666),
                                    fontSize: 11,
                                  ),
                                  border: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFF343434)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFF343434)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE8884A)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              Text(
                                (m['file_name'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF6E6E6E),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_pendingMedia.isNotEmpty && !hideMediaWhileTyping)
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _pendingMedia.length,
                itemBuilder: (ctx, i) {
                  final item = _pendingMedia[i];
                  final icon = switch (item.kind) {
                    'image' => Icons.image_outlined,
                    'video' => Icons.videocam_outlined,
                    'audio' => Icons.audio_file_outlined,
                    _ => Icons.attach_file,
                  };
                  return Container(
                    key: ValueKey('${item.path}-$i'),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2E2E2E)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 56,
                            height: 56,
                            color: const Color(0xFF101010),
                            child: item.kind == 'image'
                                ? Image.file(
                                    File(item.path),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(
                                      icon,
                                      color: const Color(0xFFE8884A),
                                      size: 20,
                                    ),
                                  )
                                : Icon(
                                    icon,
                                    color: const Color(0xFFE8884A),
                                    size: 22,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                initialValue: item.displayName,
                                onChanged: (v) => item.displayName = v.trim(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: const Color(0xFF121212),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  labelText: 'Name',
                                  hintText: 'Photo/File name',
                                  labelStyle: const TextStyle(
                                    color: Color(0xFF9A9A9A),
                                    fontSize: 10,
                                  ),
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF7A7A7A),
                                    fontSize: 11,
                                  ),
                                  border: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFF343434)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFF343434)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE8884A)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                initialValue: item.caption,
                                onChanged: (v) => item.caption = v.trim(),
                                style: const TextStyle(
                                  color: Color(0xFFCCCCCC),
                                  fontSize: 11,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: const Color(0xFF121212),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  labelText: 'Description',
                                  hintText:
                                      'Isme kya hai / kaun hai (AI context)',
                                  labelStyle: const TextStyle(
                                    color: Color(0xFF9A9A9A),
                                    fontSize: 10,
                                  ),
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF666666),
                                    fontSize: 11,
                                  ),
                                  border: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFF343434)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFF343434)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE8884A)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              Text(
                                item.originalName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF6E6E6E),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            setState(() => _pendingMedia.removeAt(i));
                          },
                          child: const Icon(Icons.close,
                              size: 15, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (hideMediaWhileTyping &&
              (_existingMedia.isNotEmpty || _pendingMedia.isNotEmpty))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              child: const Text(
                'Typing mode: media cards temporarily hidden',
                style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 11),
              ),
            ),
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.of(context).viewPadding.bottom * 0.6,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              border: Border(top: BorderSide(color: Color(0xFF2E2E2E))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _openAttachPicker,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE8884A)),
                            foregroundColor: const Color(0xFFE8884A),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.attach_file, size: 16),
                          label: const Text('Upload'),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String?>(
                          value: _voiceLocale,
                          dropdownColor: const Color(0xFF1A1A1A),
                          underline: const SizedBox(),
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 13),
                          hint: const Text('🌐 Auto',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 13)),
                          items: const [
                            DropdownMenuItem<String?>(
                                value: null, child: Text('🌐 Auto (Mix)')),
                            DropdownMenuItem(
                                value: 'hi-IN', child: Text('🇮🇳 Hindi')),
                            DropdownMenuItem(
                                value: 'mr-IN', child: Text('🟠 Marathi')),
                            DropdownMenuItem(
                                value: 'en-US', child: Text('🇬🇧 English')),
                          ],
                          onChanged: (val) =>
                              setState(() => _voiceLocale = val),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _manualRefineLoading
                              ? null
                              : _runManualAiRefinePreview,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE8884A)),
                            foregroundColor: const Color(0xFFE8884A),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: _manualRefineLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.auto_fix_high, size: 16),
                          label: const Text('AI Refine'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _refineUndoActive ? _undoLastRefine : null,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: _refineUndoActive
                                  ? const Color(0xFFE8884A)
                                  : const Color(0xFF4A4A4A),
                            ),
                            foregroundColor: _refineUndoActive
                                ? const Color(0xFFE8884A)
                                : const Color(0xFF666666),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.undo, size: 16),
                          label: const Text('Undo'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 58),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderChip extends StatelessWidget {
  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;
  const _FolderChip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFE8884A).withValues(alpha: 0.2)
              : const Color(0xFF242424),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0xFFE8884A) : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                color: selected ? const Color(0xFFE8884A) : Colors.grey,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              )),
        ]),
      ),
    );
  }
}
