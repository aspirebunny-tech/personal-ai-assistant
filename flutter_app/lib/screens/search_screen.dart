import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/api_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryCtrl = TextEditingController();
  final _speech = SpeechToText();
  List<dynamic> _results = [];
  bool _loading = false;
  bool _isListening = false;
  String _explanation = '';
  bool _usedAI = true;

  String _formatDateSmall(dynamic raw) {
    final input = (raw ?? '').toString().trim();
    if (input.isEmpty) return '';
    try {
      final sqliteUtc = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$');
      DateTime dt;
      if (sqliteUtc.hasMatch(input)) {
        dt = DateTime.parse('${input.replaceFirst(' ', 'T')}Z').toLocal();
      } else {
        final parsed = DateTime.parse(input);
        dt = parsed.isUtc ? parsed.toLocal() : parsed;
      }
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${_two(dt.hour)}:${_two(dt.minute)}';
    } catch (_) {
      return '';
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    _speech.initialize();
  }

  void _toggleVoice() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      _search();
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) => setState(() => _queryCtrl.text = result.recognizedWords),
        localeId: 'hi-IN',
      );
    }
  }

  Future<void> _search() async {
    if (_queryCtrl.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _results = [];
      _explanation = '';
      _usedAI = true;
    });
    final res = await ApiService.aiSearchDetailed(_queryCtrl.text.trim());
    if (!mounted) return;
    setState(() {
      _results = (res['results'] as List<dynamic>? ?? []);
      _explanation = (res['explanation'] ?? '').toString();
      _usedAI = res['usedAI'] == true;
      _loading = false;
    });
  }

  String _mediaUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${ApiService.baseUrl}$path';
  }

  Widget _buildHighlightedSnippet(String text, List<dynamic> terms) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final lowered = text.toLowerCase();
    int start = text.length;
    int end = -1;
    final cleanTerms = terms.map((e) => e.toString().toLowerCase()).where((t) => t.isNotEmpty).toList();
    for (final term in cleanTerms) {
      final i = lowered.indexOf(term);
      if (i >= 0) {
        if (i < start) start = i;
        if (i + term.length > end) end = i + term.length;
      }
    }
    if (end <= start || start >= text.length) {
      return Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 13, height: 1.45),
      );
    }
    return RichText(
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 13, height: 1.45),
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: text.substring(start, end),
            style: const TextStyle(
              color: Colors.black,
              backgroundColor: Color(0xFFE8884A),
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }

  void _openSearchResult(dynamic note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        maxChildSize: 0.95,
        builder: (ctx, controller) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note['title']?.toString().isNotEmpty == true ? note['title'] : 'Matched Note',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                note['folder_name']?.toString() ?? '',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const Divider(color: Color(0xFF2E2E2E), height: 22),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: SelectableText(
                    note['content']?.toString() ?? '',
                    style: const TextStyle(color: Color(0xFFE0E0E0), height: 1.55, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Smart Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2E2E2E)),
                  ),
                  child: TextField(
                    controller: _queryCtrl,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'Poocho... "GF ke liye gift note kiya tha?"',
                      hintStyle: const TextStyle(color: Color(0xFF555555), fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: IconButton(
                        icon: Icon(_isListening ? Icons.stop : Icons.mic,
                          color: _isListening ? Colors.red : const Color(0xFFE8884A)),
                        onPressed: _toggleVoice,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _search,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8884A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.all(14),
                ),
                child: const Icon(Icons.search, color: Colors.white),
              ),
            ]),
          ),

          if (_explanation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8884A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE8884A).withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFFE8884A), size: 14),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_explanation, style: const TextStyle(color: Color(0xFFE8884A), fontSize: 12))),
                  const SizedBox(width: 8),
                  Text(
                    _usedAI ? 'AI' : 'Fallback',
                    style: TextStyle(
                      color: _usedAI ? Colors.greenAccent : Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),

          if (_loading)
            const Expanded(child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFFE8884A)),
                SizedBox(height: 16),
                Text('AI dhundh raha hai...', style: TextStyle(color: Colors.grey)),
              ],
            )))
          else
            Expanded(
              child: _results.isEmpty && _queryCtrl.text.isNotEmpty
                ? const Center(child: Text('Koi note nahi mila', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) {
                      final note = _results[i];
                      final snippet = (note['match_snippet'] ?? '').toString();
                      final terms = (note['match_terms'] as List<dynamic>?) ?? const <dynamic>[];
                      final reason = (note['match_reason'] ?? '').toString();
                      final conf = (note['match_confidence'] ?? 0).toString();
                      return GestureDetector(
                        onTap: () => _openSearchResult(note),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF2E2E2E)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((note['preview_image_path'] ?? '').toString().isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: double.infinity,
                                    constraints: const BoxConstraints(maxHeight: 180),
                                    color: const Color(0xFF101010),
                                    child: Image.network(
                                      _mediaUrl((note['preview_image_path'] ?? '').toString()),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (note['folder_name'] != null)
                                Row(children: [
                                  const Icon(Icons.folder, color: Color(0xFFE8884A), size: 14),
                                  const SizedBox(width: 4),
                                  Text(note['folder_name'], style: const TextStyle(color: Color(0xFFE8884A), fontSize: 12)),
                                  const Spacer(),
                                  Text(
                                    _formatDateSmall(note['created_at']),
                                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                                  ),
                                ]),
                              const SizedBox(height: 8),
                              Text(note['content'] ?? '', maxLines: 4, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFFE0E0E0), fontSize: 14, height: 1.5)),
                              if ((note['media_labels'] ?? '').toString().trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Builder(
                                  builder: (_) {
                                    final labelsRaw = (note['media_labels'] ?? '').toString();
                                    final labels = labelsRaw
                                        .split('|')
                                        .map((s) => s.trim())
                                        .where((s) => s.isNotEmpty)
                                        .take(4)
                                        .toList();
                                    return Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: labels
                                          .map(
                                            (label) => Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE8884A).withValues(alpha: 0.14),
                                                borderRadius: BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: const Color(0xFFE8884A).withValues(alpha: 0.4),
                                                ),
                                              ),
                                              child: Text(
                                                label,
                                                style: const TextStyle(
                                                  color: Color(0xFFE7A56D),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    );
                                  },
                                ),
                              ],
                              if (snippet.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildHighlightedSnippet(snippet, terms),
                              ],
                              if (reason.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Why: $reason${conf != "0" ? " (conf: $conf)" : ""}',
                                  style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
        ],
      ),
    );
  }
}
