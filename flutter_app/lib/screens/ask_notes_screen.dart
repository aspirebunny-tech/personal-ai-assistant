import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AskNotesScreen extends StatefulWidget {
  const AskNotesScreen({super.key});

  @override
  State<AskNotesScreen> createState() => _AskNotesScreenState();
}

class _AskNotesScreenState extends State<AskNotesScreen> {
  final TextEditingController _qCtrl = TextEditingController();
  final List<Map<String, String>> _turns = [];
  String _tone = 'creative';
  String _answerLength = 'medium';
  int? _maxWords;
  int? _maxSentences;
  bool _includeCounterQuestion = true;
  bool _loading = false;
  String _counterQuestion = '';

  Future<void> _ask({String? overrideQuestion}) async {
    final q = (overrideQuestion ?? _qCtrl.text).trim();
    if (q.isEmpty) return;
    if (overrideQuestion != null) {
      _qCtrl.text = q;
      _qCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _qCtrl.text.length),
      );
    }
    setState(() {
      _loading = true;
      _counterQuestion = '';
    });
    final cleanQRes = await ApiService.cleanupTranscriptText(q);
    final cleanedQ = (cleanQRes['cleaned_text'] ?? q).toString().trim();
    if (cleanedQ.isNotEmpty && cleanedQ != q) {
      _qCtrl.text = cleanedQ;
      _qCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _qCtrl.text.length),
      );
    }
    final res = await ApiService.askNotesQuestion(
      cleanedQ.isNotEmpty ? cleanedQ : q,
      tone: _tone,
      answerLength: _answerLength,
      maxWords: _maxWords,
      maxSentences: _maxSentences,
      includeCounterQuestion: _includeCounterQuestion,
      conversationHistory: _turns,
    );
    if (!mounted) return;
    final answer = (res['answer'] ?? '').toString();
    final usedAI = res['usedAI'] == true;
    final userQ = cleanedQ.isNotEmpty ? cleanedQ : q;
    setState(() {
      _loading = false;
      _turns.add({
        'question': userQ,
        'answer': answer,
        'usedAI': usedAI ? 'true' : 'false',
      });
      _counterQuestion = (res['counter_question'] ?? '').toString().trim();
    });
    _qCtrl.clear();
  }

  Widget _buildTurnCard(Map<String, String> t) {
    final usedAI = (t['usedAI'] ?? 'false') == 'true';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                t['question'] ?? '',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!usedAI)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        '[Fallback]',
                        style: TextStyle(color: Colors.orange, fontSize: 11),
                      ),
                    ),
                  SelectableText(
                    t['answer'] ?? '',
                    style:
                        const TextStyle(color: Color(0xFFE0E0E0), height: 1.55),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask Notes')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              collapsedIconColor: const Color(0xFFE8884A),
              iconColor: const Color(0xFFE8884A),
              title:
                  const Text('Answer Controls', style: TextStyle(fontSize: 13)),
              children: [
                Row(
                  children: [
                    const Text('Tone:', style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _tone,
                      dropdownColor: const Color(0xFF1A1A1A),
                      items: const [
                        DropdownMenuItem(
                            value: 'creative', child: Text('Creative')),
                        DropdownMenuItem(
                            value: 'emotional', child: Text('Emotional')),
                        DropdownMenuItem(
                            value: 'simple', child: Text('Simple')),
                      ],
                      onChanged: (v) => setState(() => _tone = v ?? 'creative'),
                    ),
                    const SizedBox(width: 10),
                    const Text('Size:', style: TextStyle(color: Colors.grey)),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _answerLength,
                      dropdownColor: const Color(0xFF1A1A1A),
                      items: const [
                        DropdownMenuItem(value: 'short', child: Text('Short')),
                        DropdownMenuItem(
                            value: 'medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'long', child: Text('Long')),
                      ],
                      onChanged: (v) =>
                          setState(() => _answerLength = v ?? 'medium'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _maxWords,
                        dropdownColor: const Color(0xFF1A1A1A),
                        decoration: const InputDecoration(
                          labelText: 'Max words',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem<int?>(
                              value: null, child: Text('Auto')),
                          DropdownMenuItem<int?>(value: 60, child: Text('60')),
                          DropdownMenuItem<int?>(
                              value: 100, child: Text('100')),
                          DropdownMenuItem<int?>(
                              value: 150, child: Text('150')),
                          DropdownMenuItem<int?>(
                              value: 220, child: Text('220')),
                          DropdownMenuItem<int?>(
                              value: 320, child: Text('320')),
                        ],
                        onChanged: (v) => setState(() => _maxWords = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _maxSentences,
                        dropdownColor: const Color(0xFF1A1A1A),
                        decoration: const InputDecoration(
                          labelText: 'Max sentences',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem<int?>(
                              value: null, child: Text('Auto')),
                          DropdownMenuItem<int?>(value: 3, child: Text('3')),
                          DropdownMenuItem<int?>(value: 5, child: Text('5')),
                          DropdownMenuItem<int?>(value: 8, child: Text('8')),
                          DropdownMenuItem<int?>(value: 12, child: Text('12')),
                        ],
                        onChanged: (v) => setState(() => _maxSentences = v),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Counter question suggest kare',
                      style: TextStyle(fontSize: 13)),
                  value: _includeCounterQuestion,
                  onChanged: (v) => setState(() => _includeCounterQuestion = v),
                  activeThumbColor: const Color(0xFFE8884A),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _turns.isEmpty
                  ? const Center(
                      child: Text(
                        'Question pucho, yahi thread me chat chalega.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      itemCount: _turns.length,
                      itemBuilder: (ctx, i) {
                        final t = _turns[_turns.length - 1 - i];
                        return _buildTurnCard(t);
                      },
                    ),
            ),
            if (_counterQuestion.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8884A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFE8884A).withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _counterQuestion,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _loading
                          ? null
                          : () => _ask(overrideQuestion: _counterQuestion),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE8884A)),
                      ),
                      child: const Text(
                        'Ask this',
                        style: TextStyle(color: Color(0xFFE8884A)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qCtrl,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Follow-up question pucho...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : () => _ask(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8884A),
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
