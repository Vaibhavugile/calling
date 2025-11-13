import 'package:flutter/material.dart';
import '../models/lead.dart';
import '../services/lead_service.dart';
import 'lead_details_screen.dart';
import 'lead_form_screen.dart';

class LeadListScreen extends StatefulWidget {
  const LeadListScreen({super.key});

  @override
  State<LeadListScreen> createState() => _LeadListScreenState();
}

class _LeadListScreenState extends State<LeadListScreen> {
  final LeadService _service = LeadService();

  List<Lead> _allLeads = [];
  List<Lead> _filteredLeads = [];
  bool _loading = true;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLeads();
    _searchCtrl.addListener(_applySearch);
  }

  Future<void> _loadLeads() async {
    setState(() => _loading = true);

    await _service.loadLeads();
    _allLeads = _service.getAll();

    // Sort -> latest interaction first
    _allLeads.sort((a, b) => b.lastInteraction.compareTo(a.lastInteraction));

    _filteredLeads = List.from(_allLeads);

    setState(() => _loading = false);
  }

  void _applySearch() {
    final query = _searchCtrl.text.toLowerCase();

    if (query.isEmpty) {
      setState(() => _filteredLeads = List.from(_allLeads));
      return;
    }

    setState(() {
      _filteredLeads = _allLeads.where((lead) {
        return lead.name.toLowerCase().contains(query) ||
            lead.phoneNumber.toLowerCase().contains(query);
      }).toList();
    });
  }

  // -------------------------------------------------------
  // LAST CALL SUBTITLE
  // -------------------------------------------------------
  String _lastCall(Lead lead) {
    if (lead.callHistory.isEmpty) return "No calls yet";
    final last = lead.callHistory.last;
    return "${last.direction} • ${last.outcome}";
  }

  // -------------------------------------------------------
  // LEAD CARD
  // -------------------------------------------------------
  Widget _leadCard(Lead lead) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),

        leading: CircleAvatar(
          radius: 26,
          backgroundColor: Colors.blue.shade100,
          child: Text(
            lead.name.isEmpty ? "#" : lead.name[0].toUpperCase(),
            style: TextStyle(
              fontSize: 22,
              color: Colors.blue.shade600,
            ),
          ),
        ),

        title: Text(
          lead.name.isEmpty ? "No Name" : lead.name,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),

        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              lead.phoneNumber,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              _lastCall(lead),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),

        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            lead.status,
            style: TextStyle(
              color: Colors.blue.shade700,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LeadDetailsScreen(lead: lead),
            ),
          );
          _loadLeads(); // refresh after editing
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // -------------------------------------------------------
  // UI
  // -------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("All Leads"),
        backgroundColor: Colors.blueAccent,
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LeadFormScreen(
                lead: Lead.newLead(""),
                autoOpenedFromCall: false,
              ),
            ),
          ).then((_) => _loadLeads());
        },
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // -------------------------
                // SEARCH BAR
                // -------------------------
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: "Search by name or phone",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                // -------------------------
                // LIST
                // -------------------------
                Expanded(
                  child: _filteredLeads.isEmpty
                      ? const Center(child: Text("No leads found"))
                      : ListView.builder(
                          itemCount: _filteredLeads.length,
                          itemBuilder: (_, i) => _leadCard(_filteredLeads[i]),
                        ),
                ),
              ],
            ),
    );
  }
}
