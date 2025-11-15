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

  // Return type is Lead? (nullable)
  Lead? findByPhone(String phone) {
    final normalized = _normalize(phone);
    // ✅ FIX 1: Use try-catch block to safely handle StateError from firstWhere
    try {
      // firstWhere will throw a StateError if no element is found.
      return _cached.firstWhere(
        (l) => _normalize(l.phoneNumber) == normalized,
      );
    } catch (_) {
      // If an error is thrown (i.e., not found), return null, satisfying Lead?.
      return null; 
    }
  }

  // Fetch a single lead by ID, prioritizing cache but fetching from Firestore if needed
  Future<Lead?> getLead({required String leadId}) async {
    // 1. Check local cache first
    // ✅ FIX 2: Use try-catch block for the cache lookup as well.
    Lead? cachedLead;
    try {
      // If found, cachedLead is assigned a non-null Lead. If not found, throws.
      cachedLead = _cached.firstWhere((l) => l.id == leadId);
    } catch (_) {
      // If an error is thrown, cachedLead remains/becomes null.
      cachedLead = null;
    }
    
    if (cachedLead != null) return cachedLead;

    try {
      // 2. Fetch from Firestore as a fallback
      final doc = await _leadsCollection.doc(leadId).get();
      if (doc.exists) {
        final fetchedLead = Lead.fromMap(doc.data()!);
        // Add to cache now that we've fetched it
        _cached.add(fetchedLead); 
        return fetchedLead;
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
  // Internal save without clearing needsManualReview flag
  Future<void> _saveLeadToStorage(Lead lead) async {
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
  
  // Public method for manual user save actions (clears review flag)
  Future<void> saveLead(Lead lead) async {
    // A manual save/update always implies the lead has been reviewed
    final leadToSave = lead.copyWith(
        needsManualReview: false // Clear the flag on any explicit save
    );

    await _saveLeadToStorage(leadToSave);
  }

  // ---------------------------------------------------------------------------
  // CRUD Operations
  // ---------------------------------------------------------------------------
  Future<Lead> createLead(String phone) async {
    final lead = Lead.newLead(_normalize(phone));
    _cached.add(lead);
    await _saveLeadToStorage(lead); // Persist to Firestore immediately
    return lead;
  }
  
  // Implements the robust lookup: Cache -> Firestore Query -> Create
  Future<Lead> findOrCreateLead({
    required String phone,
    String finalOutcome = 'none', 
  }) async {
    final normalized = _normalize(phone);
    
    // 1. Search in cache first
    Lead? lead = findByPhone(normalized);

    if (lead == null) {
        // 2. If not in cache, search Firestore by phone number.
        final querySnapshot = await _leadsCollection
            .where('phoneNumber', isEqualTo: normalized)
            .limit(1)
            .get();
        
        if (querySnapshot.docs.isNotEmpty) {
            // Found in Firestore. Use this lead object.
            lead = Lead.fromMap(querySnapshot.docs.first.data());
            // Add to cache now that we've fetched it
            _cached.add(lead);
        } else {
            // 3. CREATE NEW LEAD if not found anywhere
            lead = Lead.newLead(normalized);
        }
    }

    // Preserve existing name and status from the found/new lead.
    final updated = lead!.copyWith( 
      lastUpdated: DateTime.now(),
      lastCallOutcome: finalOutcome, 
    );

    await _saveLeadToStorage(updated);
    return updated;
  }

  // ---------------------------------------------------------------------------
  // addCallEvent - For initial/ongoing call states ('ringing', 'started')
  // ---------------------------------------------------------------------------
  Future<Lead> addCallEvent({
    required String phone,
    required String direction,
    required String outcome,
    required DateTime timestamp, 
    int? durationInSeconds, 
  }) async {
    // 1. Find or create the lead in the background
    final latestLead = await findOrCreateLead(phone: phone);

    // 2. Create history entry
    final entry = CallHistoryEntry(
      direction: direction,
      outcome: outcome,
      timestamp: timestamp,
      durationInSeconds: durationInSeconds,
    );

    // 3. Update the lead, keeping name/status/etc.
    final updated = latestLead.copyWith(
      lastUpdated: DateTime.now(),
      callHistory: [...latestLead.callHistory, entry],
      // For initial states, don't update lastCallOutcome yet, keep the existing one.
      lastCallOutcome: latestLead.lastCallOutcome, 
      needsManualReview: latestLead.needsManualReview, // Keep the current state
    );

    await _saveLeadToStorage(updated); // Use internal save
    return updated;
  }
  
  // ---------------------------------------------------------------------------
  // addFinalCallEvent - For terminal call states ('ended', 'missed', 'rejected', 'answered')
  // ---------------------------------------------------------------------------
  Future<Lead?> addFinalCallEvent({
    required String phone,
    required String direction,
    required String outcome,
    required DateTime timestamp,
    int? durationInSeconds, 
  }) async {
    final latestLead = await findOrCreateLead(phone: phone, finalOutcome: outcome);
    
    // 1. Determine if MANUAL REVIEW IS REQUIRED based on the outcome
    bool reviewNeeded = latestLead.needsManualReview; // Preserve current review state
    if (outcome == 'missed' || outcome == 'rejected') {
        reviewNeeded = true; // Override to true for missed/rejected calls
    }
    
    // 2. Create history entry
    final entry = CallHistoryEntry(
      direction: direction,
      outcome: outcome,
      timestamp: timestamp,
      durationInSeconds: durationInSeconds,
    );

    // 3. Update the lead
    final updated = latestLead.copyWith(
      lastUpdated: DateTime.now(),
      lastInteraction: DateTime.now(), // Treat final event as interaction time
      callHistory: [...latestLead.callHistory, entry],
      lastCallOutcome: outcome, // Set the final outcome
      needsManualReview: reviewNeeded, // Set the review flag
    );

    await _saveLeadToStorage(updated); // Use internal save
    return updated;
  }

  // ---------------------------------------------------------------------------
  // User Actions (Clear review flag)
  // ---------------------------------------------------------------------------

  // Method required by LeadFormScreen to manually flag a lead
  Future<void> markLeadForReview(String leadId, bool isNeeded) async {
    final existingLead = await getLead(leadId: leadId);
    if (existingLead == null) {
      print("❌ Lead not found for review update.");
      return;
    }

    final updated = existingLead.copyWith(
      needsManualReview: isNeeded,
      lastUpdated: DateTime.now(),
    );
    
    await _saveLeadToStorage(updated);
  }

  // ✅ Ensures addNote clears the needsManualReview flag
  Future<void> addNote({required Lead lead, required String note}) async {
    if (lead.id.isEmpty) {
      throw Exception('Lead must have a valid ID to add a note.');
    }

    final latestLead = await getLead(leadId: lead.id);
    if (latestLead == null) throw Exception("Lead not found for note update.");
    
    final updatedLead = latestLead.copyWith(
      notes: [
        ...latestLead.notes,
        LeadNote(
          timestamp: DateTime.now(),
          text: note,
        ),
      ],
      lastUpdated: DateTime.now(),
      lastInteraction: DateTime.now(), // A note is an interaction
      needsManualReview: false, // CLEAR the flag on adding a note
    );

    await _saveLeadToStorage(updatedLead); // Use internal save
  }

  // ✅ Ensures updateLead clears the needsManualReview flag
  Future<Lead> updateLead({
    required String id,
    String? name,
    String? status,
    String? phoneNumber,
  }) async {
    final existingLead = await getLead(leadId: id);
    if (existingLead == null) throw Exception("Lead not found for update.");

    final updated = existingLead.copyWith(
      name: name ?? existingLead.name,
      status: status ?? existingLead.status,
      phoneNumber: phoneNumber ?? existingLead.phoneNumber,
      lastUpdated: DateTime.now(),
      lastInteraction: DateTime.now(), // Manual update is an interaction
      needsManualReview: false, // CLEAR the flag on manual update
    );

    await _saveLeadToStorage(updated); // Use internal save
    return updated;
  }

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------
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