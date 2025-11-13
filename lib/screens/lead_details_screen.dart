// lib/screens/lead_details_screen.dart
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

  Future<void> _reloadLead() async {
    final refreshed = _service.findByPhone(_lead.phoneNumber);
    if (refreshed != null) {
      setState(() => _lead = refreshed);
    }
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

  Future<void> _openEdit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LeadFormScreen(lead: _lead)),
    );
    await _reloadLead();
  }

  // Format DateTime safely
  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} "
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  Widget _headerCard() {
    final avatarChar = _lead.name.isNotEmpty
        ? _lead.name[0].toUpperCase()
        : (_lead.phoneNumber.isNotEmpty ? _lead.phoneNumber[0] : '#');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A90E2), Color(0xFF6FB1FC)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white24,
            child: Text(avatarChar,
                style: const TextStyle(fontSize: 28, color: Colors.white)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lead.name.isEmpty ? "(No name)" : _lead.name,
                  style: const TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 18, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      _lead.phoneNumber,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _lead.status,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: _openEdit,
          )
        ],
      ),
    );
  }

  Widget _callHistory() {
    if (_lead.callHistory.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text("No call history yet", style: TextStyle(color: Colors.grey)),
      );
    }

    final calls = _lead.callHistory.reversed.toList();

    return Column(
      children: calls.map((c) {
        IconData icon;
        Color color;

        switch (c.direction) {
          case "inbound":
            icon = Icons.call_received;
            color = Colors.green;
            break;
          case "outbound":
          case "outgoing":
            icon = Icons.call_made;
            color = Colors.blue;
            break;
          default:
            icon = Icons.phone;
            color = Colors.grey;
        }

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color),
            ),
            title: Text("${c.direction} • ${c.outcome}"),
            subtitle: Text(_formatDateTime(c.timestamp)),
          ),
        );
      }).toList(),
    );
  }

  Widget _notes() {
    if (_lead.notes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text("No notes added yet", style: TextStyle(color: Colors.grey)),
      );
    }

    final notes = _lead.notes.reversed.toList();

    return Column(
      children: notes.map((n) {
        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.note),
            title: Text(n.text),
            subtitle: Text(_formatDateTime(n.timestamp)),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Lead Details"),
        backgroundColor: Colors.blueAccent,
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
