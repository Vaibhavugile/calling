// lib/screens/lead_form_screen.dart

import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/lead_service.dart';

class LeadFormScreen extends StatefulWidget {
  final Lead lead;
  final bool autoOpenedFromCall;

  const LeadFormScreen({
    super.key,
    required this.lead,
    this.autoOpenedFromCall = false,
  });

  @override
  State<LeadFormScreen> createState() => _LeadFormScreenState();
}

class _LeadFormScreenState extends State<LeadFormScreen> {
  final LeadService _service = LeadService();

  late Lead _lead;

  late TextEditingController _nameController;
  late TextEditingController _noteController;

  final List<String> _statusOptions = [
    "new",
    "in progress",
    "follow up",
    "interested",
    "not interested",
    "closed",
  ];

  @override
  void initState() {
    super.initState();
    _lead = widget.lead;
    _nameController = TextEditingController(text: _lead.name);
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // -----------------------------------------
  // UTIL: DATE FORMATTER
  // -----------------------------------------
  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}  "
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  // -----------------------------------------
  // SAVE NAME CHANGE
  // -----------------------------------------
  Future<void> _saveLead() async {
    final updated = _lead.copyWith(
      name: _nameController.text.trim(),
      lastUpdated: DateTime.now(),
    );

    await _service.saveLead(updated);
    setState(() => _lead = updated);
  }

  // -----------------------------------------
  // ADD NOTE
  // -----------------------------------------
  Future<void> _addNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;

    final updated = await _service.addNote(_lead.id, text);

    setState(() {
      _lead = updated;
      _noteController.clear();
    });
  }

  // -----------------------------------------
  // UI: SECTION TITLE
  // -----------------------------------------
  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.blueGrey.shade900,
        ),
      ),
    );
  }

  // -----------------------------------------
  // UI: HEADER CARD
  // -----------------------------------------
  Widget _headerCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.phone_android,
                  size: 28, color: Colors.blue.shade700),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _lead.phoneNumber,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------
  // UI: CALL HISTORY SECTION
  // -----------------------------------------
  Widget _callHistorySection() {
    if (_lead.callHistory.isEmpty) {
      return const Text("No call history yet");
    }

    return Column(
      children: _lead.callHistory.reversed.map((call) {
        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Icon(
              call.direction == "inbound"
                  ? Icons.call_received
                  : Icons.call_made,
              color: call.direction == "inbound" ? Colors.green : Colors.blue,
            ),
            title: Text("${call.direction} – ${call.outcome}"),
            subtitle: Text(_formatDate(call.timestamp)),
          ),
        );
      }).toList(),
    );
  }

  // -----------------------------------------
  // UI: NOTES SECTION
  // -----------------------------------------
  Widget _notesSection() {
    if (_lead.notes.isEmpty) {
      return const Text("No notes yet");
    }

    return Column(
      children: _lead.notes.reversed.map((note) {
        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.note),
            title: Text(note.text),
            subtitle: Text(_formatDate(note.timestamp)),
          ),
        );
      }).toList(),
    );
  }

  // -----------------------------------------
  // MAIN UI
  // -----------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.autoOpenedFromCall ? "Call Lead" : "Lead Details"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerCard(),

            // NAME
            _sectionTitle("Name"),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: "Enter lead name",
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => _saveLead(),
            ),

            // STATUS
            _sectionTitle("Status"),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: DropdownButton<String>(
                value: _lead.status,
                isExpanded: true,
                underline: const SizedBox(),
                items: _statusOptions.map((s) {
                  return DropdownMenuItem(value: s, child: Text(s));
                }).toList(),
                onChanged: (val) async {
                  if (val == null) return;

                  final updated =
                      _lead.copyWith(status: val, lastUpdated: DateTime.now());
                  await _service.saveLead(updated);

                  setState(() => _lead = updated);
                },
              ),
            ),

            // CALL HISTORY
            _sectionTitle("Call History"),
            _callHistorySection(),

            // NOTES
            _sectionTitle("Notes"),
            _notesSection(),

            const SizedBox(height: 12),

            TextField(
              controller: _noteController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "Write a note...",
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _addNote,
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
