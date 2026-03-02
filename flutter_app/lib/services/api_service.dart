import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'direct_ai_fallback.dart';

class ApiService {
  static String _baseUrl = '';
  static String _token = '';
  static String get baseUrl => _baseUrl;
  static String get token => _token;
  static Map<String, String> get authOnlyHeaders =>
      _token.isEmpty ? {} : {'Authorization': 'Bearer $_token'};

  static void init(String serverUrl, String token) {
    _baseUrl = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    _token = token;
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  static String resolveMediaUrl({
    String? mediaId,
    String? filePath,
  }) {
    if (mediaId != null && mediaId.trim().isNotEmpty) {
      return '$_baseUrl/api/media/file/${mediaId.trim()}';
    }
    final p = (filePath ?? '').trim();
    if (p.isEmpty) return '';
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    return '$_baseUrl$p';
  }

  static Map<String, dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return <String, dynamic>{};
    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{'data': data};
  }

  static Map<String, dynamic> _decodeOrThrow(http.Response res,
      {Set<int>? okCodes}) {
    final allowed = okCodes ?? <int>{200};
    final data = _decode(res);
    if (!allowed.contains(res.statusCode)) {
      throw Exception(
        (data['error'] ?? data['message'] ?? 'HTTP ${res.statusCode}')
            .toString(),
      );
    }
    if (data['success'] == false) {
      throw Exception(
          (data['error'] ?? data['message'] ?? 'Request failed').toString());
    }
    return data;
  }

  // ── AUTH ──
  static Future<Map<String, dynamic>> login(
      String email, String password, String serverUrl) async {
    final url = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    final res = await http
        .post(
          Uri.parse('$url/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> register(
      String email, String password, String name, String serverUrl) async {
    final url = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    final res = await http
        .post(
          Uri.parse('$url/api/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body:
              jsonEncode({'email': email, 'password': password, 'name': name}),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(res.body);
  }

  // ── HEALTH CHECK ──
  static Future<bool> checkHealth(String serverUrl) async {
    try {
      final url = serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl;
      final res = await http
          .get(Uri.parse('$url/api/health'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── FOLDERS ──
  static Future<List<dynamic>> getFolders() async {
    final res =
        await http.get(Uri.parse('$_baseUrl/api/folders'), headers: _headers);
    final data = _decodeOrThrow(res);
    return data['folders'] ?? [];
  }

  static Future<Map<String, dynamic>> createFolder(
      String name, String icon, String color) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/folders'),
      headers: _headers,
      body: jsonEncode({'name': name, 'icon': icon, 'color': color}),
    );
    return _decodeOrThrow(res);
  }

  static Future<Map<String, dynamic>> updateFolder({
    required String id,
    required String name,
    required String icon,
    required String color,
  }) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/folders/$id'),
      headers: _headers,
      body: jsonEncode({'name': name, 'icon': icon, 'color': color}),
    );
    return _decodeOrThrow(res);
  }

  static Future<void> deleteFolder(String id) async {
    final res = await http.delete(Uri.parse('$_baseUrl/api/folders/$id'),
        headers: _headers);
    _decodeOrThrow(res);
  }

  // ── NOTES ──
  static Future<List<dynamic>> getNotes(
      {String? folderId, String? search}) async {
    String url = '$_baseUrl/api/notes';
    final params = <String, String>{};
    if (folderId != null) params['folder_id'] = folderId;
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (params.isNotEmpty) url += '?${Uri(queryParameters: params).query}';

    final res = await http.get(Uri.parse(url), headers: _headers);
    final data = _decodeOrThrow(res);
    return data['notes'] ?? [];
  }

  static Future<Map<String, dynamic>> createNote({
    required String content,
    String? title,
    String? folderId,
    List<String>? tags,
  }) async {
    final res = await http
        .post(
          Uri.parse('$_baseUrl/api/notes'),
          headers: _headers,
          body: jsonEncode({
            'content': content,
            'title': title ??
                content.substring(0, content.length > 50 ? 50 : content.length),
            'folder_id': folderId,
            'tags': tags ?? [],
          }),
        )
        .timeout(const Duration(seconds: 8));
    return _decodeOrThrow(res);
  }

  static Future<void> deleteNote(String id) async {
    final res = await http.delete(Uri.parse('$_baseUrl/api/notes/$id'),
        headers: _headers);
    _decodeOrThrow(res);
  }

  static Future<Map<String, dynamic>> updateNote(
    String id,
    String content, {
    String? title,
    String? folderId,
  }) async {
    final res = await http
        .put(
          Uri.parse('$_baseUrl/api/notes/$id'),
          headers: _headers,
          body: jsonEncode({
            'title': title ??
                content.substring(0, content.length > 50 ? 50 : content.length),
            'content': content,
            'folder_id': folderId,
          }),
        )
        .timeout(const Duration(seconds: 8));
    return _decodeOrThrow(res);
  }

  // ── REMINDERS ──
  static Future<List<dynamic>> getReminders() async {
    final res =
        await http.get(Uri.parse('$_baseUrl/api/reminders'), headers: _headers);
    final data = _decodeOrThrow(res);
    return data['reminders'] ?? [];
  }

  static Future<Map<String, dynamic>> createReminder({
    required String title,
    required String remindAt,
    String? description,
    String? noteId,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/reminders'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'remind_at': remindAt,
        'description': description,
        'note_id': noteId
      }),
    );
    return _decodeOrThrow(res);
  }

  static Future<void> deleteReminder(String id) async {
    final res = await http.delete(Uri.parse('$_baseUrl/api/reminders/$id'),
        headers: _headers);
    _decodeOrThrow(res);
  }

  // ── AI ──
  static Future<String> summarize(
    String text, {
    List<String>? noteIds,
    String? folderId,
  }) async {
    final data =
        await summarizeDetailed(text, noteIds: noteIds, folderId: folderId);
    return data['summary'] ?? 'Summary nahi ban saki';
  }

  static Future<Map<String, dynamic>> summarizeDetailed(
    String text, {
    List<String>? noteIds,
    String? folderId,
  }) async {
    try {
      final payload = <String, dynamic>{'text': text};
      if (noteIds != null && noteIds.isNotEmpty) payload['note_ids'] = noteIds;
      if (folderId != null && folderId.isNotEmpty) {
        payload['folder_id'] = folderId;
      }
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/ai/summarize'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
      final data = _decodeOrThrow(res);
      return data;
    } catch (_) {
      if (Platform.isAndroid) {
        return DirectAiFallback.summarize(
          text,
          noteIds: noteIds,
          folderId: folderId,
        );
      }
      return {'summary': 'Server se connect nahi ho pa raha', 'usedAI': false};
    }
  }

  static Future<List<dynamic>> aiSearch(String query) async {
    try {
      final data = await aiSearchDetailed(query);
      return data['results'] ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> aiSearchDetailed(String query) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/ai/search'),
            headers: _headers,
            body: jsonEncode({'query': query}),
          )
          .timeout(const Duration(seconds: 30));
      final data = _decodeOrThrow(res);
      return data;
    } catch (_) {
      if (Platform.isAndroid) {
        return DirectAiFallback.aiSearch(query);
      }
      return {'results': <dynamic>[], 'explanation': '', 'usedAI': false};
    }
  }

  static Future<Map<String, dynamic>> getAiStatus() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/ai/status'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      return _decodeOrThrow(res);
    } catch (e) {
      if (Platform.isAndroid) {
        final localStatus = await DirectAiFallback.getStatus();
        if (localStatus['ai_available'] == true) {
          return localStatus;
        }
      }
      return {
        'success': false,
        'ai_available': false,
        'message': 'AI status check failed: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> getServerHealth(
      {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final res =
          await http.get(Uri.parse('$_baseUrl/api/health')).timeout(timeout);
      final data = _decodeOrThrow(res);
      return {
        'success': true,
        'healthy': data['status'] == 'ok',
        'message': (data['message'] ?? '').toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'healthy': false,
        'message': '$e',
      };
    }
  }

  static Future<Map<String, dynamic>> getAndroidUpdateInfo() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/app/version/android'))
          .timeout(const Duration(seconds: 8));
      return _decodeOrThrow(res);
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  static Future<File> downloadFile({
    required String url,
    required String savePath,
  }) async {
    final req = await HttpClient().getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Download failed HTTP ${resp.statusCode}');
    }
    final out = File(savePath);
    await out.parent.create(recursive: true);
    final sink = out.openWrite();
    await resp.forEach(sink.add);
    await sink.flush();
    await sink.close();
    return out;
  }

  static Future<Map<String, dynamic>> getAiProviderConfig() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/ai/providers-config'),
              headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _decodeOrThrow(res);
    } catch (e) {
      if (Platform.isAndroid) {
        return getLocalAiProviderConfig();
      }
      return {'success': false, 'error': '$e'};
    }
  }

  static Future<Map<String, dynamic>> saveAiProviderConfig(
      Map<String, dynamic> payload) async {
    try {
      await DirectAiFallback.saveProviderConfig(payload);
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/ai/providers-config'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      return _decodeOrThrow(res);
    } catch (e) {
      if (!Platform.isAndroid) {
        return {'success': false, 'error': '$e'};
      }
      return {
        'success': true,
        'local_only': true,
        'message': 'Saved locally for Android direct fallback',
        'config': payload,
      };
    }
  }

  static Future<Map<String, dynamic>> getLocalAiProviderConfig() async {
    try {
      final cfg = await DirectAiFallback.loadProviderConfig();
      return {'success': true, 'config': cfg};
    } catch (e) {
      return {'success': false, 'error': '$e', 'config': <String, dynamic>{}};
    }
  }

  static Future<Map<String, dynamic>> getProviderModels({
    required String provider,
    required String slot,
    String apiKey = '',
    String baseUrl = '',
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/ai/providers-models'),
            headers: _headers,
            body: jsonEncode({
              'provider': provider,
              'slot': slot,
              'api_key': apiKey,
              'base_url': baseUrl,
            }),
          )
          .timeout(const Duration(seconds: 30));
      return _decodeOrThrow(res);
    } catch (e) {
      return {'success': false, 'error': '$e', 'models': <dynamic>[]};
    }
  }

  static Future<Map<String, dynamic>> askNotesQuestion(
    String question, {
    String tone = 'creative',
    String answerLength = 'medium',
    int? maxWords,
    int? maxSentences,
    bool includeCounterQuestion = false,
    List<Map<String, String>> conversationHistory = const [],
  }) async {
    try {
      final payload = <String, dynamic>{
        'question': question,
        'tone': tone,
        'answer_length': answerLength,
        'include_counter_question': includeCounterQuestion,
      };
      if (maxWords != null) payload['max_words'] = maxWords;
      if (maxSentences != null) payload['max_sentences'] = maxSentences;
      if (conversationHistory.isNotEmpty) {
        payload['conversation_history'] = conversationHistory;
      }
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/ai/ask'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 35));
      return _decodeOrThrow(res);
    } catch (e) {
      if (Platform.isAndroid) {
        return DirectAiFallback.askNotes(
          question,
          tone: tone,
          answerLength: answerLength,
          maxWords: maxWords,
          maxSentences: maxSentences,
          includeCounterQuestion: includeCounterQuestion,
          conversationHistory: conversationHistory,
        );
      }
      return {
        'success': false,
        'answer': 'Ask feature abhi available nahi: $e',
        'usedAI': false,
      };
    }
  }

  static Future<Map<String, dynamic>> cleanupTranscriptText(String text) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/ai/cleanup-text'),
            headers: _headers,
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 25));
      return _decodeOrThrow(res);
    } catch (e) {
      if (Platform.isAndroid) {
        return DirectAiFallback.cleanupText(text);
      }
      return {
        'success': false,
        'cleaned_text': text,
        'usedAI': false,
        'error': '$e'
      };
    }
  }

  // ── MEDIA ──
  static Future<Map<String, dynamic>> uploadNoteMedia({
    required String noteId,
    required String filePath,
    String? displayName,
    String? caption,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/media/upload/$noteId'),
      );
      request.headers['Authorization'] = 'Bearer $_token';
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      if (displayName != null && displayName.trim().isNotEmpty) {
        request.fields['display_name'] = displayName.trim();
      }
      if (caption != null && caption.trim().isNotEmpty) {
        request.fields['caption'] = caption.trim();
      }
      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();
      if (body.isEmpty) {
        return {'success': false, 'error': 'Empty upload response'};
      }
      final data = jsonDecode(body);
      if (streamed.statusCode < 200 ||
          streamed.statusCode >= 300 ||
          data['success'] == false) {
        return {'success': false, 'error': data['error'] ?? 'Upload failed'};
      }
      return data;
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  static Future<List<dynamic>> getNoteMedia(String noteId) async {
    final res = await http.get(Uri.parse('$_baseUrl/api/media/note/$noteId'),
        headers: _headers);
    final data = _decodeOrThrow(res);
    return data['media'] ?? [];
  }

  static Future<Map<String, dynamic>> updateMediaInfo({
    required String mediaId,
    String? displayName,
    String? caption,
  }) async {
    try {
      final res = await http
          .patch(
            Uri.parse('$_baseUrl/api/media/$mediaId'),
            headers: _headers,
            body: jsonEncode({
              'display_name': (displayName ?? '').trim(),
              'caption': (caption ?? '').trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      return _decodeOrThrow(res);
    } catch (e) {
      return {'success': false, 'error': '$e'};
    }
  }

  static Future<Map<String, dynamic>> getNoteById(String noteId) async {
    final res = await http.get(Uri.parse('$_baseUrl/api/notes/$noteId'),
        headers: _headers);
    return _decodeOrThrow(res);
  }

  static Future<Map<String, dynamic>> getSystemDiagnostics() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/system/diagnostics'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      return _decodeOrThrow(res);
    } catch (e) {
      return {'success': false, 'error': '$e', 'checks': <dynamic>[]};
    }
  }
}
