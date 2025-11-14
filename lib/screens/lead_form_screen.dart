// lib/screens/lead_form_screen.dart

import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/lead_service.dart';

class LeadFormScreen extends StatefulWidget {
  final Lead lead;
  final bool autoOpenedFromCall;
  
  // 🔥 REMOVED: final String? callDirection; // No longer needed
  
  const LeadFormScreen({
    super.key,
    required this.lead,
    this.autoOpenedFromCall = false,
    
    // 🔥 REMOVED: callDirection
  });

  @override
  State<LeadFormScreen> createState() => _LeadFormScreenState();
}

class _LeadFormScreenState extends State<LeadFormScreen> {
  final LeadService _service = LeadService();

  late Lead _lead;

  late TextEditingController _nameController;
  late TextEditingController _noteController;
  // Controller for the read-only phone number field
  late TextEditingController _phoneController; 

  bool _hasUnsavedNameChanges = false; 
  // 🔥 REMOVED: _callHistoryEntryAdded flag is no longer needed

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
    // Initialize phone controller with the lead's phone number
    _phoneController = TextEditingController(text: _lead.phoneNumber);

    _nameController.addListener(_checkUnsavedChanges);
  }

  @override
  void dispose() {
    _nameController.removeListener(_checkUnsavedChanges);
    _nameController.dispose();
    _noteController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
  
  // -------------------------------------------------------------------------
  // 🔥 NEW: DURATION FORMATTER
  // -------------------------------------------------------------------------
  /// Converts seconds to a human-readable string (e.g., '1m 35s').
  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds ~/ 60);
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '${minutes}m ${secs}s';
  }

  // -------------------------------------------------------------------------
  // PERSISTENCE CORE LOGIC
  // -------------------------------------------------------------------------
  /// Checks if the lead is transient (no ID) and saves it to Firestore.
  Future<void> _persistLeadIfTransient() async {
  // If the ID is empty, the lead exists only in memory (transient).
  if (_lead.id.isEmpty) {
      print("📝 First save: Persisting new lead for ${_lead.phoneNumber}");
      
      // 1. Create the lead in Firestore to get an ID (saves only phone number)
      final persistedLead = await _service.createLead(_lead.phoneNumber);
      
      // 2. Update the local lead object, using the new ID and current controller values
      // This is crucial to preserve the call history and status that the CallEventHandler
      // may have already added to the transient lead object.
      final updatedTransientLead = persistedLead.copyWith(
        // Use the current state and controller values
        name: _nameController.text.trim(), 
        status: _lead.status,
        callHistory: _lead.callHistory, // Preserve history added by CallEventHandler
        notes: _lead.notes, // Preserve notes
        lastCallOutcome: _lead.lastCallOutcome,
        lastInteraction: DateTime.now(), 
        lastUpdated: DateTime.now(), 
      );

      // 3. Save the fully updated object back to Firestore
      await _service.saveLead(updatedTransientLead);

      // 4. Update local state
      setState(() {
          _lead = updatedTransientLead;
      });
  }
}
  // -------------------------------------------------------------------------
  // 🔥 REMOVED: _logCallHistory function is now gone.
  // -------------------------------------------------------------------------
  

  void _checkUnsavedChanges() {
    final currentName = _nameController.text.trim();
    final hasChanges = currentName != _lead.name;
    
    if (hasChanges != _hasUnsavedNameChanges) {
        setState(() {
            _hasUnsavedNameChanges = hasChanges;
        });
    }
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
  // SAVE LEAD (Triggered by Save button/Status change)
  // -----------------------------------------
  Future<void> _saveLead({String? newStatus, String? newName}) async {
    // Ensure lead is saved/persisted first
    await _persistLeadIfTransient();

    final name = newName ?? _nameController.text.trim();
    final status = newStatus ?? _lead.status;
    
    // Skip save if no changes
    if (name == _lead.name && status == _lead.status && newStatus == null && newName == null) {
      return;
    }

    final updated = _lead.copyWith(
      name: name,
      status: status,
      // Update the required interaction fields on every save
      lastInteraction: DateTime.now(), 
      lastUpdated: DateTime.now(), 
    );

    // Now that we guarantee _lead.id is NOT empty, we can safely call saveLead
    await _service.saveLead(updated);
    
    // Update local state and reset the flag
    setState(() {
      _lead = updated;
      _hasUnsavedNameChanges = false;
    });

    _checkUnsavedChanges();
  }

  // -----------------------------------------
  // ADD NOTE
  // -----------------------------------------
  Future<void> _addNote() async {
  if (_noteController.text.isEmpty) return;

  final String note = _noteController.text.trim();
  _noteController.clear();

  try {
    // ✅ FIX: Call the updated service method with the local _lead object
    await _service.addNote(lead: _lead, note: note);

    // After saving, refresh the local state to include the new note
    final updatedLead = await _service.getLead(leadId: _lead.id);

    setState(() {
      if (updatedLead != null) {
        _lead = updatedLead;
      }
    });
  } catch (e) {
    print('❌ Error adding note: $e');
    // Handle the exception gracefully, maybe show a snackbar
  }
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
  // UI: HEADER CARD (Now shows phone number and last outcome)
  // -----------------------------------------
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


  // -----------------------------------------
  // UI: CALL HISTORY SECTION
  // -----------------------------------------
  Widget _callHistorySection() {
    if (_lead.callHistory.isEmpty) {
      // Updated message to reflect handler logs the initial event
      return const Text("No call history yet (Save the lead to start tracking calls)");
    }

    return Column(
      children: _lead.callHistory.reversed.map((call) {
        final icon = call.direction == "inbound" ? Icons.call_received : Icons.call_made;
        final color = call.outcome == "answered" ? Colors.green : 
                      call.outcome == "missed" ? Colors.red : 
                      call.outcome == "rejected" ? Colors.orange : 
                      Colors.blue;
        
        // 🔥 MODIFIED: Display duration if available
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
        actions: [
          if (_hasUnsavedNameChanges)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () => _saveLead(newName: _nameController.text.trim()),
              tooltip: 'Save Name',
            ),
        ],
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


            // NAME (Editable)
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
              onSubmitted: (val) => _saveLead(newName: val),
              onEditingComplete: () => _saveLead(newName: _nameController.text.trim()),
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
                  // Use the unified save function
                  await _saveLead(newStatus: val);
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