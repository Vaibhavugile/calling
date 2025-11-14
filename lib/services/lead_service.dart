import 'package:cloud_firestore/cloud_firestore.dart';
// NOTE: firebase_auth is no longer needed/imported for this flat structure.
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
  
  // 🔥 RE-IMPLEMENTED: findOrCreateLead for CallEventHandler compatibility
  Future<Lead> findOrCreateLead({
    required String phone,
    required String finalOutcome,
  }) async {
    final normalized = _normalize(phone);
    final existingIndex = _cached.indexWhere(
        (l) => _normalize(l.phoneNumber) == normalized);
    
    Lead lead;
    if (existingIndex == -1) {
      // Create New Lead
      lead = Lead.newLead(normalized);
      _cached.add(lead);
    } else {
      // Found Existing Lead
      lead = _cached[existingIndex];
    }

    // Update the lead's interaction time and outcome for list filtering
    final updated = lead.copyWith(
      lastInteraction: DateTime.now(),
      lastUpdated: DateTime.now(),
      lastCallOutcome: finalOutcome, 
    );

    await saveLead(updated);
    // Note: saveLead updates the cache

    return updated;
  }

  // 🔥 RE-IMPLEMENTED: addCallHistoryEntry for UI/CallHandler compatibility
  Future<Lead> addCallHistoryEntry({
    required String leadId,
    required String direction,
    required String outcome, // answered, missed, ended, rejected, etc.
  }) async {
    final index = _cached.indexWhere((l) => l.id == leadId);
    if (index == -1) throw Exception("Lead not found");

    final lead = _cached[index];
    final entry = CallHistoryEntry(
      direction: direction,
      outcome: outcome,
      timestamp: DateTime.now(),
    );

    // Update lead with the new call history entry and timestamps
    final updated = lead.copyWith(
      lastInteraction: DateTime.now(), // Update interaction time
      lastUpdated: DateTime.now(), // Update modification time
      callHistory: [...lead.callHistory, entry],
    );

    await saveLead(updated); // Persist updated lead and update cache
    return updated;
  }

  Future<Lead> addCallEvent({
    required String phone,
    required String direction,
    required String outcome,
  }) async {
    final lead = findByPhone(phone);
    if (lead == null) throw Exception("Lead not found");

    final entry = CallHistoryEntry(
      direction: direction,
      outcome: outcome,
      timestamp: DateTime.now(),
    );

    final updated = lead.copyWith(
      lastInteraction: DateTime.now(),
      lastUpdated: DateTime.now(),
      callHistory: [...lead.callHistory, entry],
    );

    await saveLead(updated); // Persist updated lead
    return updated;
  }

  Future<Lead> addNote(String id, String text) async {
    final index = _cached.indexWhere((l) => l.id == id);
    if (index == -1) throw Exception("Lead not found");

    final note = LeadNote(text: text, timestamp: DateTime.now());
    final lead = _cached[index];
    final updated = lead.copyWith(
      notes: [...lead.notes, note],
      lastUpdated: DateTime.now(),
    );

    await saveLead(updated); // Persist updated lead
    return updated;
  }

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