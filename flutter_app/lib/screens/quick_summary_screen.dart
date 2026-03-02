import 'package:flutter/material.dart';
import '../services/api_service.dart';

class QuickSummaryScreen extends StatefulWidget {
  const QuickSummaryScreen({super.key});

  @override
  State<QuickSummaryScreen> createState() => _QuickSummaryScreenState();
}

class _QuickSummaryScreenState extends State<QuickSummaryScreen> {
  List<dynamic> _notes = [];
  final Set<String> _selectedNoteIds = <String>{};
  bool _loading = true;
  bool _summarizing = false;
  String _summary = '';
  bool _usedAI = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _loading = true);
    try {
      final notes = await ApiService.getNotes();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _generateSummary() async {
    if (_selectedNoteIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pehle notes select karo')),
      );
      return;
    }
    setState(() => _summarizing = true);
    final res = await ApiService.summarizeDetailed(
      '',
      noteIds: _selectedNoteIds.toList(),
    );
    if (!mounted) return;
    setState(() {
      _summary = (res['summary'] ?? '').toString();
      _usedAI = res['usedAI'] == true;
      _summarizing = false;
    });
    if (_summary.isNotEmpty) _showSummarySheet();
  }

  void _showSummarySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.96,
        minChildSize: 0.55,
        builder: (ctx, controller) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Summary',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  if (!_usedAI)
                    const Text(
                      '(Fallback)',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: SelectableText(
                    _summary,
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
      appBar: AppBar(
        title: const Text('Quick AI Summary'),
        actions: [
          TextButton(
            onPressed: _summarizing ? null : _generateSummary,
            child: const Text(
              'Summarize',
              style: TextStyle(color: Color(0xFFE8884A), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8884A)))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: _notes.length,
                    itemBuilder: (context, i) {
                      final note = _notes[i];
                      final id = (note['id'] ?? '').toString();
                      final selected = _selectedNoteIds.contains(id);
                      return CheckboxListTile(
                        value: selected,
                        activeColor: const Color(0xFFE8884A),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedNoteIds.add(id);
                            } else {
                              _selectedNoteIds.remove(id);
                            }
                          });
                        },
                        title: Text(
                          note['title'] ?? 'Note',
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          note['content'] ?? '',
                          style: const TextStyle(color: Colors.grey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
                if (_summarizing)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(color: Color(0xFFE8884A)),
                  ),
                if (_summary.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFF2E2E2E))),
                      color: Color(0xFF151515),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_usedAI)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              'AI unavailable, fallback summary shown',
                              style: TextStyle(color: Colors.orange, fontSize: 12),
                            ),
                          ),
                        Text(
                          _summary.split('\n').take(4).join('\n'),
                          style: const TextStyle(color: Color(0xFFE0E0E0), height: 1.55),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _showSummarySheet,
                          child: const Text(
                            'Open full summary',
                            style: TextStyle(color: Color(0xFFE8884A)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
