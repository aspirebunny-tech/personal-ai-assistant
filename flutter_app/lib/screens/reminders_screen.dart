import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<dynamic> _reminders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final reminders = await ApiService.getReminders();
      setState(() => _reminders = reminders);
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _showAddReminder() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime? selectedDateTime;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Naya Reminder', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Reminder ka title',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2E2E))),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE8884A))),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2E2E))),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE8884A))),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(hours: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (ctx, child) => Theme(
                      data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFFE8884A))),
                      child: child!,
                    ),
                  );
                  if (date != null) {
                    if (!ctx.mounted) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.now(),
                      builder: (ctx, child) => Theme(
                        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Color(0xFFE8884A))),
                        child: child!,
                      ),
                    );
                    if (!ctx.mounted) return;
                    if (time != null) {
                      setSheet(() {
                        selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                      });
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2E2E2E)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, color: Color(0xFFE8884A), size: 18),
                    const SizedBox(width: 10),
                    Text(
                      selectedDateTime != null
                        ? DateFormat('dd MMM yyyy, hh:mm a').format(selectedDateTime!)
                        : 'Date aur time chuno',
                      style: TextStyle(color: selectedDateTime != null ? Colors.white : Colors.grey),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty || selectedDateTime == null) return;
                    await ApiService.createReminder(
                      title: titleCtrl.text,
                      remindAt: selectedDateTime!.toIso8601String(),
                      description: descCtrl.text,
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    _load();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8884A), padding: const EdgeInsets.all(14)),
                  child: const Text('Reminder Set Karo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
      appBar: AppBar(title: const Text('⏰ Reminders')),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8884A)))
        : _reminders.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.alarm_off, color: Colors.grey, size: 64),
              SizedBox(height: 16),
              Text('Koi reminder nahi', style: TextStyle(color: Colors.grey)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _reminders.length,
              itemBuilder: (ctx, i) {
                final r = _reminders[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2E2E2E)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.alarm, color: Color(0xFFE8884A), size: 24),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['title'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      if (r['description']?.isNotEmpty == true)
                        Text(r['description'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(r['remind_at']?.substring(0, 16)?.replaceAll('T', ' ') ?? '',
                        style: const TextStyle(color: Color(0xFFE8884A), fontSize: 12)),
                    ])),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                      onPressed: () async {
                        await ApiService.deleteReminder(r['id']);
                        _load();
                      },
                    ),
                  ]),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddReminder,
        backgroundColor: const Color(0xFFE8884A),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Reminder', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
