// lib/services/lead_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lead.dart';

// -----------------------------------------------------------------------------
// LEAD SERVICE (Firestore - Single Collection)
// -----------------------------------------------------------------------------
class LeadService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 🎯 Reference to the top-level 'leads' collection
  final CollectionReference<Map<String, dynamic>> _leadsCollection = 
      FirebaseFirestore.instance.collection('leads');

  List<Lead> _cached = [];

  // ---------------------------------------------------------------------------
  // LOAD & GET
  // ---------------------------------------------------------------------------
  Future<void> loadLeads() async {
    try {
      final snapshot = await _leadsCollection.get();
      _cached = snapshot.docs
          .map((doc) => Lead.fromMap(doc.data()))
          .toList();
      print("✅ [FIRESTORE] Loaded ${_cached.length} leads from /leads.");
    } catch (e) {
      print("❌ [FIRESTORE] Error loading leads: $e");
      _cached = [];
    }
  }

  List<Lead> getAll() => _cached;

  // Helper to normalize phone numbers for searching
  String _normalize(String number) => number.replaceAll(RegExp(r'[^0-9+]'), '');

  Lead? findByPhone(String phone) {
    final normalized = _normalize(phone);
    try {
      return _cached.firstWhere((l) => _normalize(l.phoneNumber) == normalized);
    } catch (_) {
      return null;
    }
  }

  // ✅ NEW: Fetch a single lead from Firestore by ID. Used for integrity checks.
  Future<Lead?> getLead({required String leadId}) async {
    try {
      final doc = await _leadsCollection.doc(leadId).get();
      if (doc.exists) {
        return Lead.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      print("❌ [FIRESTORE] Error fetching lead $leadId: $e");
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // SAVE (The core persistence method)
  // ---------------------------------------------------------------------------
  Future<void> saveLead(Lead lead) async {
    try {
      // 1. Save to Firestore using the lead's ID as the document ID
      await _leadsCollection.doc(lead.id).set(lead.toMap());
      print("✅ [FIRESTORE] Saved lead ${lead.id} to /leads.");

      // 2. Update cache
      final index = _cached.indexWhere((l) => l.id == lead.id);
      if (index == -1) {
        _cached.add(lead);
      } else {
        _cached[index] = lead;
      }
    } catch (e) {
      print("❌ [FIRESTORE] Error saving lead: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD Operations
  // ---------------------------------------------------------------------------
  Future<Lead> createLead(String phone) async {
    final lead = Lead.newLead(_normalize(phone));
    _cached.add(lead);
    await saveLead(lead); // Persist to Firestore immediately
    return lead;
  }
  
  // ✅ UPDATED: Added Firestore check if not found in cache.
  Future<Lead> findOrCreateLead({
    required String phone,
    required String finalOutcome,
  }) async {
    final normalized = _normalize(phone);
    
    // 1. Search in cache first
    Lead? lead = findByPhone(normalized);

    if (lead == null) {
      // 2. If not in cache, search Firestore
      final querySnapshot = await _leadsCollection
          .where('phoneNumber', isEqualTo: normalized)
          .limit(1)
          .get();
      
      if (querySnapshot.docs.isNotEmpty) {
        // Found in Firestore
        lead = Lead.fromMap(querySnapshot.docs.first.data());
      } else {
        // 3. Create New Lead
        lead = Lead.newLead(normalized);
      }
    }

    // Update the lead's interaction time and outcome for list filtering
    final updated = lead.copyWith(
      lastInteraction: DateTime.now(),
      lastUpdated: DateTime.now(),
      lastCallOutcome: finalOutcome, 
    );

    await saveLead(updated);
    return updated;
  }

  // addCallHistoryEntry method is retained for potential future use...

  // ---------------------------------------------------------------------------
  // ✅ FIX: Uses getLead to fetch the latest state from Firestore before updating
  // ---------------------------------------------------------------------------
  Future<Lead> addCallEvent({
    required String phone,
    required String direction,
    required String outcome,
    int? durationInSeconds, 
  }) async {
    // 1. Find lead ID/metadata via cache
    final Lead? cachedLead = findByPhone(phone);
    if (cachedLead == null) throw Exception("Lead not found");

    // 2. Fetch the latest lead object from Firestore using the ID
    final latestLead = await getLead(leadId: cachedLead.id);
    if (latestLead == null) throw Exception("Lead not found in Firestore.");

    final entry = CallHistoryEntry(
      direction: direction,
      outcome: outcome,
      timestamp: DateTime.now(),
      durationInSeconds: durationInSeconds,
    );

    // Determine the outcome to display in the list.
    final String newOutcome = (outcome == 'ringing' || outcome == 'started') 
        ? latestLead.lastCallOutcome // Keep the current state if it's still ongoing/initial
        : outcome; // Use the final outcome (answered, missed, rejected, ended)

    final updated = latestLead.copyWith(
      lastInteraction: DateTime.now(),
      lastUpdated: DateTime.now(),
      callHistory: [...latestLead.callHistory, entry],
      lastCallOutcome: newOutcome,
    );

    await saveLead(updated); // Persist updated lead
    return updated;
  }

  // ✅ FIX: Uses getLead to fetch the latest state from Firestore before adding a note
  Future<void> addNote({required Lead lead, required String note}) async {
    if (lead.id.isEmpty) {
      throw Exception('Lead must have a valid ID to add a note.');
    }

    // Fetch the latest version from Firestore to prevent overwriting concurrent updates
    final latestLead = await getLead(leadId: lead.id);
    if (latestLead == null) throw Exception("Lead not found for note update.");
    
    final updatedLead = latestLead.copyWith(
      notes: [
        ...latestLead.notes,
        LeadNote(
  timestamp: DateTime.now(),
  text: note, // ⬅️ FIX IS HERE
),
      ],
      lastUpdated: DateTime.now(),
      lastInteraction: DateTime.now(), // A note is an interaction
    );

    await saveLead(updatedLead); 
  }

  // ✅ UPDATED: Now updates lastInteraction on update.
  Future<Lead> updateLead({
    required String id,
    String? name,
    String? status,
    String? phoneNumber,
  }) async {
    final index = _cached.indexWhere((l) => l.id == id);
    if (index == -1) throw Exception("Lead not found");

    final lead = _cached[index];
    final updated = lead.copyWith(
      name: name ?? lead.name,
      status: status ?? lead.status,
      phoneNumber: phoneNumber ?? lead.phoneNumber,
      lastUpdated: DateTime.now(),
      lastInteraction: DateTime.now(),
    );

    await saveLead(updated); // Persist updated lead
    return updated;
  }

  Future<void> deleteLead(String id) async {
    try {
      await _leadsCollection.doc(id).delete();
      print("✅ [FIRESTORE] Deleted lead $id from /leads.");

      _cached.removeWhere((l) => l.id == id);
    } catch (e) {
      print("❌ [FIRESTORE] Error deleting lead: $e");
    }
  }
}