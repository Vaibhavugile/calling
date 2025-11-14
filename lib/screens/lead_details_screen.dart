// lib/screens/lead_details_screen.dart

import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/lead_service.dart';

class LeadDetailsScreen extends StatefulWidget {
  final Lead lead;

  const LeadDetailsScreen({
    super.key,
    required this.lead,
  });

  @override
  State<LeadDetailsScreen> createState() => _LeadDetailsScreenState();
}

class _LeadDetailsScreenState extends State<LeadDetailsScreen> {
  final LeadService _service = LeadService();

  late Lead _lead;

  // Controller for the read-only phone number field
  late TextEditingController _phoneController; 
  
  // ✅ FIX: Note controller added
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
    // Initialize controllers
    _phoneController = TextEditingController(text: _lead.phoneNumber);
    _noteController = TextEditingController(); // ✅ FIX: Initialized
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _noteController.dispose(); // ✅ FIX: Disposed
    super.dispose();
  }
  
  // -------------------------------------------------------------------------
  // UTILITY METHODS
  // -------------------------------------------------------------------------

  /// Converts seconds to a human-readable string (e.g., '1m 35s').
  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds ~/ 60);
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '${minutes}m ${secs}s';
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}  "
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  // -------------------------------------------------------------------------
  // PERSISTENCE & ACTIONS
  // -------------------------------------------------------------------------
  
  Future<void> _saveStatus(String newStatus) async {
    final updated = _lead.copyWith(
      status: newStatus,
      lastInteraction: DateTime.now(), 
      lastUpdated: DateTime.now(), 
    );
    
    // Assumes lead.id is not empty for a Details screen
    await _service.saveLead(updated);
    
    setState(() {
      _lead = updated;
    });
  }


  // ✅ FIX: Correct logic to save note and refresh lead state.
  Future<void> _addNote() async {
    if (_noteController.text.isEmpty) return;

    final String note = _noteController.text.trim();
    _noteController.clear(); // Clear the text field immediately

    try {
      // 1. Save the note. Note that addNote returns Future<void>.
      await _service.addNote(lead: _lead, note: note);

      // 2. Fetch the updated lead object from the service (which includes the new note)
      final updatedLead = await _service.getLead(leadId: _lead.id);

      // 3. Update local state
      setState(() {
        if (updatedLead != null) {
          _lead = updatedLead; // Now assigning a Lead object, fixing the error
        }
      });
    } catch (e) {
      print('❌ Error adding note: $e');
      // Handle the exception gracefully, e.g., show a snackbar
    }
  }

  // -------------------------------------------------------------------------
  // UI COMPONENTS
  // -------------------------------------------------------------------------
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

  Widget _headerCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            if (_lead.lastCallOutcome != 'none') ...[
              const SizedBox(height: 10),
              // Display the last call outcome for context
              Text(
                'Last Call Status: ${_lead.lastCallOutcome.toUpperCase()}',
                style: TextStyle(
                  fontSize: 16,
                  color: _lead.lastCallOutcome == 'missed' ? Colors.red.shade700 : Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _callHistorySection() {
    if (_lead.callHistory.isEmpty) {
      return const Text("No call history yet.");
    }

    return Column(
      children: _lead.callHistory.reversed.map((call) {
        final icon = call.direction == "inbound" ? Icons.call_received : Icons.call_made;
        final color = call.outcome == "answered" ? Colors.green : 
                      call.outcome == "missed" ? Colors.red : 
                      call.outcome == "rejected" ? Colors.orange : 
                      Colors.blue;
        
        final durationText = call.durationInSeconds != null
            ? ' (${_formatDuration(call.durationInSeconds!)})'
            : '';

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Icon(icon, color: color),
            // Title includes outcome and duration
            title: Text("${call.direction} – ${call.outcome.toUpperCase()}$durationText"),
            subtitle: Text(_formatDate(call.timestamp)),
          ),
        );
      }).toList(),
    );
  }

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
        title: const Text("Lead Details"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerCard(),

            // PHONE NUMBER (Read Only)
            _sectionTitle("Phone Number"),
            TextField(
              controller: _phoneController,
              readOnly: true, 
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade200,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),


            // NAME (Read Only for Details Screen)
            _sectionTitle("Name"),
            TextField(
              controller: TextEditingController(text: _lead.name), // Display the current name
              readOnly: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade200,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),

            // STATUS (Editable)
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
                  await _saveStatus(val);
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

            // NOTE INPUT FIELD
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