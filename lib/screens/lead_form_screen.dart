// lib/screens/lead_form_screen.dart

import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/lead_service.dart';

class LeadFormScreen extends StatefulWidget {
  final Lead lead;
  final bool autoOpenedFromCall;
  // 🔥 NEW: Pass the call direction from the handler
  final String? callDirection;
  
  const LeadFormScreen({
    super.key,
    required this.lead,
    this.autoOpenedFromCall = false,
    this.callDirection,
  });

  @override
  State<LeadFormScreen> createState() => _LeadFormScreenState();
}

class _LeadFormScreenState extends State<LeadFormScreen> {
  final LeadService _service = LeadService();

  late Lead _lead;

  late TextEditingController _nameController;
  late TextEditingController _noteController;
  // 🔥 NEW: Controller for the read-only phone number field
  late TextEditingController _phoneController; 

  bool _hasUnsavedNameChanges = false; 
  // 🔥 NEW: Flag to ensure we only log the final call history event once
  bool _callHistoryEntryAdded = false; 

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
    // 🔥 NEW: Initialize phone controller with the lead's phone number
    _phoneController = TextEditingController(text: _lead.phoneNumber);

    _nameController.addListener(_checkUnsavedChanges);
  }

  @override
  void dispose() {
    _nameController.removeListener(_checkUnsavedChanges);
    _nameController.dispose();
    _noteController.dispose();
    _phoneController.dispose(); // 🔥 NEW: Dispose phone controller
    super.dispose();
  }
  
  // -------------------------------------------------------------------------
  // 🔥 NEW: PERSISTENCE CORE LOGIC
  // -------------------------------------------------------------------------
  /// Checks if the lead is transient (no ID) and saves it to Firestore.
  Future<void> _persistLeadIfTransient() async {
    // If the ID is empty, the lead exists only in memory (transient).
    if (_lead.id.isEmpty) {
        print("📝 First save: Persisting new lead for ${_lead.phoneNumber}");
        
        // 1. Create the lead in Firestore to get an ID
        final persistedLead = await _service.createLead(_lead.phoneNumber);
        
        // 2. Update the local state with the new persisted lead's ID and original transient data
        setState(() {
          // 🔥 FIX 3: Ensure all required fields (lastInteraction, lastUpdated) are set when copying
          // data from the transient lead onto the newly persisted lead.
          _lead = persistedLead.copyWith(
            name: _lead.name,
            status: _lead.status,
            lastCallOutcome: _lead.lastCallOutcome,
            lastInteraction: DateTime.now(), 
            lastUpdated: DateTime.now(), 
          );
        });
        
        // 3. Log the initial call history event
        await _logCallHistory();
    }
  }

  // -------------------------------------------------------------------------
  // 🔥 MODIFIED: LOG CALL HISTORY
  // -------------------------------------------------------------------------
  /// Logs the initial/final call event. This is now only called AFTER 
  /// the lead is successfully persisted (saved) by the user.
  Future<void> _logCallHistory() async {
    // Only log if the form was opened by a call AND history hasn't been added yet.
    // Also, ensure the lead has been persisted (i.e., has an ID).
    if (!widget.autoOpenedFromCall || _callHistoryEntryAdded || _lead.id.isEmpty) return;
    
    final finalOutcome = _lead.lastCallOutcome;
    final direction = widget.callDirection ?? 'unknown';

    final outcomeToLog = finalOutcome != 'none' 
        ? finalOutcome 
        : direction == 'inbound' ? 'ringing' : 'started';
    
    print('📞 Logging call history: $direction - $outcomeToLog');

    try {
        final updated = await _service.addCallEvent(
            phone: _lead.phoneNumber,
            direction: direction,
            outcome: outcomeToLog,
        );
        setState(() {
            _lead = updated;
            _callHistoryEntryAdded = true;
        });
    } catch(e) {
        print('❌ Failed to log call history: $e');
    }
  }


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
    // 🔥 FIX 4: Ensure lead is saved/persisted first
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
      // 🔥 FIX 5: Update the required interaction fields on every save
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
    final text = _noteController.text.trim();
    if (text.isEmpty) return;

    // 🔥 FIX 6: Ensure lead is saved/persisted first
    await _persistLeadIfTransient();
    
    // Now that we guarantee _lead.id is NOT empty, we can safely call addNote
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
      return const Text("No call history yet (Save the lead to log the current call)");
    }

    return Column(
      children: _lead.callHistory.reversed.map((call) {
        final icon = call.direction == "inbound" ? Icons.call_received : Icons.call_made;
        final color = call.outcome == "answered" ? Colors.green : 
                      call.outcome == "missed" ? Colors.red : 
                      call.outcome == "rejected" ? Colors.orange : 
                      Colors.blue;

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Icon(icon, color: color),
            title: Text("${call.direction} – ${call.outcome.toUpperCase()}"),
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