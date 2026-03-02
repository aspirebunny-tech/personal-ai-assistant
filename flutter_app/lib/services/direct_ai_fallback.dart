import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_db.dart';

class DirectAiFallback {
  static const String _configKey = 'ai_provider_config_local_v1';

  static Future<void> saveProviderConfig(Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config));
  }

  static Future<Map<String, dynamic>> loadProviderConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null || raw.trim().isEmpty) {
      return {
        'primary': <String, dynamic>{},
        'fallback': <String, dynamic>{},
        'use_fallback': true,
      };
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {
        'primary': <String, dynamic>{},
        'fallback': <String, dynamic>{},
        'use_fallback': true,
      };
    } catch (_) {
      return {
        'primary': <String, dynamic>{},
        'fallback': <String, dynamic>{},
        'use_fallback': true,
      };
    }
  }

  static String _providerDefaultBaseUrl(String provider) {
    switch (provider.toLowerCase()) {
      case 'openrouter':
        return 'https://openrouter.ai/api/v1/chat/completions';
      case 'openai':
        return 'https://api.openai.com/v1/chat/completions';
      case 'ollama':
        return 'http://127.0.0.1:11434/api/chat';
      default:
        return '';
    }
  }

  static bool _isModelConfigured(Map<String, dynamic> slot) {
    return (slot['model'] ?? '').toString().trim().isNotEmpty;
  }

  static bool _isKeyRequired(String provider) {
    return provider.toLowerCase() != 'ollama';
  }

  static Future<Map<String, dynamic>> getStatus() async {
    final cfg = await loadProviderConfig();
    final primary = Map<String, dynamic>.from(cfg['primary'] ?? {});
    final fallback = Map<String, dynamic>.from(cfg['fallback'] ?? {});
    final useFallback = cfg['use_fallback'] != false;

    bool primaryOk = false;
    bool fallbackOk = false;

    if (_isModelConfigured(primary)) {
      final provider = (primary['provider'] ?? '').toString().trim();
      final key = (primary['api_key'] ?? '').toString().trim();
      primaryOk = provider.isNotEmpty && (!_isKeyRequired(provider) || key.isNotEmpty);
    }
    if (_isModelConfigured(fallback)) {
      final provider = (fallback['provider'] ?? '').toString().trim();
      final key = (fallback['api_key'] ?? '').toString().trim();
      fallbackOk = provider.isNotEmpty && (!_isKeyRequired(provider) || key.isNotEmpty);
    }

    final aiAvailable = primaryOk || (useFallback && fallbackOk);
    final chain = <Map<String, dynamic>>[];
    if (primaryOk) {
      chain.add({
        'provider': (primary['provider'] ?? '').toString(),
        'model': (primary['model'] ?? '').toString(),
        'fallback': false,
      });
    }
    if (useFallback && fallbackOk) {
      chain.add({
        'provider': (fallback['provider'] ?? '').toString(),
        'model': (fallback['model'] ?? '').toString(),
        'fallback': true,
      });
    }

    return {
      'success': true,
      'ai_available': aiAvailable,
      'message': aiAvailable
          ? 'Android direct AI fallback active'
          : 'Android direct AI fallback not configured',
      'used_direct_fallback': true,
      'chain': chain,
      'configured_chain': chain,
      'providers': <String, dynamic>{},
    };
  }

  static int _clampInt(int? v, {required int min, required int max, required int fallback}) {
    if (v == null) return fallback;
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }

  static Map<String, int> _lengthDefaults(String answerLength) {
    final mode = answerLength.toLowerCase().trim();
    if (mode == 'short') return {'words': 80, 'sentences': 4};
    if (mode == 'long') return {'words': 260, 'sentences': 12};
    return {'words': 150, 'sentences': 7};
  }

  static String _limitText(String text, {required int maxWords, required int maxSentences}) {
    final raw = text.trim();
    if (raw.isEmpty) return raw;
    final sentenceParts = raw
        .split(RegExp(r'(?<=[.!?।])\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final sentenceLimited = sentenceParts.take(maxSentences).join(' ').trim();
    final words = sentenceLimited.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (words.length <= maxWords) return sentenceLimited;
    return '${words.take(maxWords).join(' ')}...';
  }

  static List<String> _tokens(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u0900-\u097F\u0A80-\u0AFF]+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  static double _score(String query, String text) {
    final q = _tokens(query);
    final t = _tokens(text).toSet();
    if (q.isEmpty || t.isEmpty) return 0;
    int hit = 0;
    for (final token in q) {
      if (t.contains(token)) hit++;
    }
    return hit / q.length;
  }

  static Future<List<Map<String, dynamic>>> _loadRankedNotes(String query) async {
    final notes = await LocalDB.getCachedNotes();
    final ranked = <Map<String, dynamic>>[];
    for (final n in notes) {
      final title = (n['title'] ?? '').toString();
      final content = (n['content'] ?? '').toString();
      final score = _score(query, '$title $content');
      if (score <= 0) continue;
      final note = Map<String, dynamic>.from(n);
      note['_score'] = score;
      ranked.add(note);
    }
    ranked.sort((a, b) =>
        ((b['_score'] ?? 0) as num).compareTo((a['_score'] ?? 0) as num));
    return ranked.take(8).toList();
  }

  static String _extractContentFromResponse(
      String provider, Map<String, dynamic> payload) {
    if (provider.toLowerCase() == 'ollama') {
      final message = payload['message'];
      if (message is Map<String, dynamic>) {
        return (message['content'] ?? '').toString();
      }
      return '';
    }
    final choices = payload['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          return (message['content'] ?? '').toString();
        }
      }
    }
    return '';
  }

  static Future<String?> _chatSingleProvider({
    required String provider,
    required String model,
    required String apiKey,
    required String baseUrl,
    required List<Map<String, String>> messages,
  }) async {
    final url = baseUrl.trim().isEmpty
        ? _providerDefaultBaseUrl(provider)
        : baseUrl.trim();
    if (url.isEmpty) return null;
    if (_isKeyRequired(provider) && apiKey.trim().isEmpty) return null;

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_isKeyRequired(provider)) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    if (provider.toLowerCase() == 'openrouter') {
      headers['HTTP-Referer'] = 'https://personal-ai-assistant.local';
      headers['X-Title'] = 'Personal AI Assistant';
    }

    Map<String, dynamic> body;
    if (provider.toLowerCase() == 'ollama') {
      body = {
        'model': model,
        'stream': false,
        'messages': messages,
      };
    } else {
      body = {
        'model': model,
        'messages': messages,
        'temperature': 0.35,
      };
    }

    final res = await http
        .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    final content = _extractContentFromResponse(provider, decoded).trim();
    if (content.isEmpty) return null;
    return content;
  }

  static Future<String?> _chat({
    required List<Map<String, String>> messages,
  }) async {
    final cfg = await loadProviderConfig();
    final useFallback = cfg['use_fallback'] != false;

    final chain = <Map<String, dynamic>>[];
    final primary = Map<String, dynamic>.from(cfg['primary'] ?? {});
    final fallback = Map<String, dynamic>.from(cfg['fallback'] ?? {});
    if (_isModelConfigured(primary)) chain.add(primary);
    if (useFallback && _isModelConfigured(fallback)) chain.add(fallback);

    for (final slot in chain) {
      final provider = (slot['provider'] ?? '').toString();
      final model = (slot['model'] ?? '').toString();
      final apiKey = (slot['api_key'] ?? '').toString();
      final baseUrl = (slot['base_url'] ?? '').toString();
      final out = await _chatSingleProvider(
        provider: provider,
        model: model,
        apiKey: apiKey,
        baseUrl: baseUrl,
        messages: messages,
      );
      if (out != null && out.trim().isNotEmpty) return out.trim();
    }
    return null;
  }

  static Future<Map<String, dynamic>> cleanupText(String text) async {
    final input = text.trim();
    if (input.isEmpty) {
      return {'success': true, 'cleaned_text': text, 'usedAI': false};
    }
    final prompt = '''
Fix punctuation and obvious speech-to-text mistakes in this Hinglish/Marathi/Hindi/English text.
Do not change meaning. Keep style natural.
Return only corrected text.

Text:
$input
''';
    final out = await _chat(messages: [
      {'role': 'system', 'content': 'You are a precise transcription editor.'},
      {'role': 'user', 'content': prompt},
    ]);
    if (out == null) {
      return {'success': false, 'cleaned_text': text, 'usedAI': false};
    }
    return {'success': true, 'cleaned_text': out, 'usedAI': true};
  }

  static Future<Map<String, dynamic>> summarize(
    String text, {
    List<String>? noteIds,
    String? folderId,
  }) async {
    final input = text.trim();
    if (input.isEmpty) {
      return {'success': true, 'summary': 'No text provided', 'usedAI': false};
    }
    final out = await _chat(messages: [
      {
        'role': 'system',
        'content': 'Summarize into concise bullets with useful headings.',
      },
      {'role': 'user', 'content': input},
    ]);
    if (out == null) {
      return {'success': false, 'summary': 'Summary unavailable', 'usedAI': false};
    }
    return {'success': true, 'summary': out, 'usedAI': true};
  }

  static Future<Map<String, dynamic>> aiSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      return {'success': true, 'results': <dynamic>[], 'usedAI': false, 'explanation': ''};
    }
    final ranked = await _loadRankedNotes(q);
    final terms = _tokens(q);
    final results = ranked.map((n) {
      final content = (n['content'] ?? '').toString();
      final snippet = content.length > 220 ? '${content.substring(0, 220)}...' : content;
      return {
        ...n,
        'match_confidence': (n['_score'] ?? 0),
        'match_terms': terms,
        'match_snippet': snippet,
        'match_reason': 'Local semantic-lite match',
      };
    }).toList();
    return {
      'success': true,
      'results': results,
      'usedAI': false,
      'explanation': results.isEmpty
          ? 'Tunnel off: local cached notes me exact/semantic match nahi mila.'
          : 'Tunnel off: local cached notes se best matches dikhaye gaye.',
    };
  }

  static Future<Map<String, dynamic>> askNotes(
    String question, {
    String tone = 'creative',
    String answerLength = 'medium',
    int? maxWords,
    int? maxSentences,
    bool includeCounterQuestion = false,
    List<Map<String, String>> conversationHistory = const [],
  }) async {
    final q = question.trim();
    if (q.isEmpty) {
      return {'success': true, 'answer': '', 'usedAI': false, 'source_media': <dynamic>[]};
    }

    final defaults = _lengthDefaults(answerLength);
    final wordsLimit = _clampInt(maxWords, min: 30, max: 450, fallback: defaults['words']!);
    final sentenceLimit = _clampInt(maxSentences, min: 2, max: 20, fallback: defaults['sentences']!);

    final ranked = await _loadRankedNotes(q);
    if (ranked.isEmpty) {
      return {
        'success': true,
        'answer': _limitText(
          'Tunnel off mode: local cache me relevant note nahi mila.',
          maxWords: wordsLimit,
          maxSentences: sentenceLimit,
        ),
        'counter_question': includeCounterQuestion
            ? 'Kya tum same question ko thoda specific person/date/detail ke saath poochna chahoge?'
            : '',
        'usedAI': false,
        'source_media': <dynamic>[],
      };
    }

    final context = ranked.map((n) {
      final title = (n['title'] ?? 'Untitled').toString();
      final content = (n['content'] ?? '').toString();
      final clipped = content.length > 900 ? '${content.substring(0, 900)}...' : content;
      return '- Title: $title\n  Content: $clipped';
    }).join('\n');
    final historyContext = conversationHistory
        .take(6)
        .map((h) =>
            'Q: ${(h['question'] ?? '').trim()}\nA: ${(h['answer'] ?? '').trim()}')
        .where((e) => e.trim().isNotEmpty)
        .join('\n\n');

    final prompt = '''
Question: $q
Tone: $tone

Answer strictly from provided notes context below. If uncertain, say uncertain briefly.
Do not copy note lines verbatim; paraphrase naturally.

Notes context:
$context
${historyContext.isEmpty ? '' : '\n\nConversation history:\n$historyContext'}
''';

    final out = await _chat(messages: [
      {'role': 'system', 'content': 'You answer using user note evidence only.'},
      {'role': 'user', 'content': prompt},
    ]);

    if (out == null) {
      return {
        'success': true,
        'answer': _limitText(
          'Local match mila, lekin AI response unavailable (provider/key/model check karo).',
          maxWords: wordsLimit,
          maxSentences: sentenceLimit,
        ),
        'counter_question': includeCounterQuestion
            ? 'Kya tum provider settings check karke isi question ko phir se poochna chahoge?'
            : '',
        'usedAI': false,
        'source_media': <dynamic>[],
      };
    }
    return {
      'success': true,
      'answer': _limitText(out, maxWords: wordsLimit, maxSentences: sentenceLimit),
      'counter_question': includeCounterQuestion
          ? 'Kya tum answer ka next step/action plan nikalna chahte ho?'
          : '',
      'usedAI': true,
      'source_media': <dynamic>[],
    };
  }
}
