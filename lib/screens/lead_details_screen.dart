import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/lead_service.dart';
import 'lead_form_screen.dart';

class LeadDetailsScreen extends StatefulWidget {
  final Lead lead;

  const LeadDetailsScreen({super.key, required this.lead});

  @override
  State<LeadDetailsScreen> createState() => _LeadDetailsScreenState();
}

class _LeadDetailsScreenState extends State<LeadDetailsScreen> {
  final LeadService _service = LeadService();

  late Lead _lead;
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _lead = widget.lead;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  // Reloads lead from service cache/storage to get updated details
  Future<void> _reloadLead() async {
    final refreshed = _service.findByPhone(_lead.phoneNumber);
    if (refreshed != null) {
      setState(() => _lead = refreshed);
    }
  }

  void _editLead() {
    Navigator.push(
      context,
      MaterialPageRoute(
        // Navigation remains to the unified LeadFormScreen
        builder: (_) => LeadFormScreen(lead: _lead),
      ),
    ).then((_) {
      // Reload the lead data after returning from the form
      _reloadLead();
    });
  }

  Future<void> _addNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;

    final updated = await _service.addNote(_lead.id, text);
    setState(() {
      _lead = updated;
      _noteCtrl.clear();
    });
  }

  // -----------------------------------------
  // UTIL: DURATION FORMATTER (🔥 NEW)
  // -----------------------------------------
  /// Converts seconds to a human-readable string (e.g., '1m 35s').
  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds ~/ 60);
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '${minutes}m ${secs}s';
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
  // UI: HEADER CARD
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
            Text(
              _lead.name.isEmpty ? "No Name" : _lead.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.phone, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(
                  _lead.phoneNumber,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.indigo.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _lead.status.toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade800,
                ),
              ),
            ),
            
            // Display last call outcome
            if (_lead.lastCallOutcome != 'none') ...[
              const SizedBox(height: 8),
              Text(
                'Last Call: ${_lead.lastCallOutcome.toUpperCase()}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _lead.lastCallOutcome == 'missed' ? Colors.red : Colors.green.shade700,
                ),
              ),
            ],
            
            const SizedBox(height: 12),
            Text(
              "Last updated: ${_formatDate(_lead.lastUpdated)}",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------
  // UI: CALL HISTORY (🔥 UPDATED to show duration)
  // -----------------------------------------
  Widget _callHistory() {
    if (_lead.callHistory.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8.0),
        child: Text("No call history recorded (only final outcome logged)."), 
      );
    }

    return Column(
      children: _lead.callHistory.reversed.map((call) {
        final icon = call.direction == "inbound" ? Icons.call_received : Icons.call_made;
        final color = call.outcome == "answered" ? Colors.green : 
                      call.outcome == "missed" ? Colors.red : 
                      call.outcome == "rejected" ? Colors.orange : 
                      Colors.blue;
        
        // Calculate and format duration
        final durationText = call.durationInSeconds != null
            ? ' (${_formatDuration(call.durationInSeconds!)})'
            : '';
                      
        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
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
  // UI: NOTES
  // -----------------------------------------
  Widget _notes() {
    if (_lead.notes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8.0),
        child: Text("No notes added yet."),
      );
    }

    return Column(
      children: _lead.notes.reversed.map((note) {
        return Card(
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
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
        title: Text(_lead.name.isEmpty ? _lead.phoneNumber : _lead.name),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editLead,
            tooltip: 'Edit Lead',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reloadLead,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 20),

              const Text("Call history",
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              _callHistory(),

              const SizedBox(height: 20),

              const Text("Notes",
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              _notes(),

              const SizedBox(height: 16),
              TextField(
                controller: _noteCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: "Add a note...",
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _addNote,
                  ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}