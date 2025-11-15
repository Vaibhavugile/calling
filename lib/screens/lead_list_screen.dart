// lib/screens/lead_list_screen.dart
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
  
  // State for the call filter
  String _selectedFilter = 'All'; 
  final List<String> _filters = [
    'All',
    // ✅ NEW FILTER
    'Needs Review', 
    'Incoming',
    'Outgoing',
    'Answered',
    'Missed',
    'Rejected'
  ];

  @override
  void initState() {
    super.initState();
    _loadLeads();
    _searchCtrl.addListener(_applySearch);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applySearch);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLeads() async {
    setState(() => _loading = true);

    await _service.loadLeads();
    _allLeads = _service.getAll();

    // Sort -> latest interaction first
    _allLeads.sort((a, b) => b.lastInteraction.compareTo(a.lastInteraction));

    _applySearch(); // Apply search and filter after loading
    
    setState(() => _loading = false);
  }

  void _applySearch() {
    final query = _searchCtrl.text.toLowerCase();
    
    // 1. Apply text search
    List<Lead> searchFiltered = _allLeads.where((l) {
      return l.name.toLowerCase().contains(query) ||
             l.phoneNumber.contains(query);
    }).toList();

    // 2. Apply call filter
    _filteredLeads = searchFiltered.where((l) {
      if (_selectedFilter == 'All') return true;

      // ✅ NEW FILTER LOGIC: Leads that are brand new from a call
      if (_selectedFilter == 'Needs Review') {
          // A lead is 'Needs Review' if its name is empty AND its status is the default 'new'
          return l.name.isEmpty && l.status == 'new';
      }

      if (l.callHistory.isEmpty) return false;

      // 🔥 MODIFIED: Logic to filter by the latest event's direction/outcome
      final lastCall = l.callHistory.last;

      // Filter by Outcome (uses the new lastCallOutcome field)
      if (_selectedFilter == 'Answered' && l.lastCallOutcome == 'answered') return true;
      if (_selectedFilter == 'Missed' && l.lastCallOutcome == 'missed') return true;
      if (_selectedFilter == 'Rejected' && l.lastCallOutcome == 'rejected') return true;
      // Note: 'Ended' is not a filter chip, but it's an outcome.

      // Filter by Direction (uses the last entry in callHistory)
      if (_selectedFilter == 'Incoming' && lastCall.direction == 'inbound') return true;
      if (_selectedFilter == 'Outgoing' && lastCall.direction == 'outbound') return true;
      
      // If none of the specific filters matched, exclude the lead
      return false; 
    }).toList();


    setState(() {});
  }
  
  // Method to handle filter change
  void _changeFilter(String filter) {
    setState(() {
      _selectedFilter = filter;
      _applySearch(); // Re-filter the list
    });
  }


  Widget _statusChip(String status) {
    Color color;
    switch (status) {
      case "new":
        color = Colors.blue;
        break;
      case "in progress":
        color = Colors.orange;
        break;
      case "follow up":
        color = Colors.purple;
        break;
      case "interested":
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Chip(
      label: Text(
        status.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
      ),
      backgroundColor: color.withOpacity(0.1),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }

  // -----------------------------------------
  // UI: LEAD CARD
  // -----------------------------------------
  Widget _leadCard(Lead lead) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              // 🔥 MODIFIED: LeadDetailsScreen is deprecated, using LeadFormScreen
              builder: (_) => LeadFormScreen(
                lead: lead,
                autoOpenedFromCall: false, // Ensure this is false when opening from list
              ), 
            ),
          ).then((_) => _loadLeads());
        },
        title: Text(lead.name.isEmpty ? "No Name" : lead.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lead.phoneNumber),
            const SizedBox(height: 4),
            Row(
              children: [
                _statusChip(lead.status),
                const SizedBox(width: 8),
                // Display last call outcome
                if (lead.lastCallOutcome != 'none')
                  Chip(
                    label: Text(
                      lead.lastCallOutcome.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: lead.lastCallOutcome == 'missed' ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                    labelStyle: lead.lastCallOutcome == 'missed' ? const TextStyle(color: Colors.red) : const TextStyle(color: Colors.green),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  // -----------------------------------------
  // MAIN UI
  // -----------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Lead List"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              // Opens form for a new, empty lead.
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
                // FILTER CHIPS (NEW)
                // -------------------------
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filters.length,
                    itemBuilder: (_, i) {
                      final filter = _filters[i];
                      final isSelected = _selectedFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(filter),
                          backgroundColor: isSelected ? Colors.blueAccent : Colors.grey.shade200,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onPressed: () => _changeFilter(filter),
                        ),
                      );
                    },
                  ),
                ),
                
                const SizedBox(height: 8),

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