// lib/call_event_handler.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/lead.dart';
import 'services/lead_service.dart';
import 'screens/lead_form_screen.dart';

class CallEventHandler {
  final GlobalKey<NavigatorState> navigatorKey;

  static const EventChannel _eventChannel =
      EventChannel("com.example.call_leads_app/callEvents");

  final LeadService _leadService = LeadService();

  StreamSubscription? _subscription;

  /// Prevents multiple screens from opening
  bool _screenOpen = false;

  // ✅ FIX: State tracker for call deduplication
  String? _currentlyProcessingCall; 

  CallEventHandler({required this.navigatorKey});

  // --------------------------------------------------------------------------
  // START LISTENING & CLEANUP
  // --------------------------------------------------------------------------
  void startListening() {
    print("📞 [CALL HANDLER] START LISTENING");
    
    _subscription = _eventChannel
        .receiveBroadcastStream()
        .listen(
      (event) {
        // Explicitly create a new Map<String, dynamic> from the raw event
        final Map<String, dynamic> typedEvent = Map<String, dynamic>.from(event as Map);
        _processCallEvent(typedEvent);
      },
      onError: (error) {
        print("❌ STREAM ERROR: $error");
      },
      onDone: () {
        print("✅ STREAM DONE");
      },
    );
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    print("🛑 [CALL HANDLER] STOP LISTENING");
  }
  
  void dispose() {
    stopListening();
  }

  // --------------------------------------------------------------------------
  // EVENT PROCESSOR (Updated to handle 'answered' and extract 'duration')
  // --------------------------------------------------------------------------
  void _processCallEvent(Map<String, dynamic> event) {
    print('📞 RAW EVENT → $event');
    final phoneNumber = event['phoneNumber'] as String;
    final outcome = event['outcome'] as String;

    if (phoneNumber.isEmpty) {
      print("! Ignoring call event with empty phone number: $outcome");
      return;
    }

    // 🎯 INITIAL/UI TRIGGER STATES: 'ringing', 'started', 'answered'
    if (outcome == 'ringing' || outcome == 'started' || outcome == 'answered') {
      
      // We only deduplicate 'ringing' and 'started', as 'answered' must always
      // be processed to open the UI if the lead is new or existing.
      if ((outcome == 'ringing' || outcome == 'started') && _currentlyProcessingCall == phoneNumber) {
        print("! DEDUPLICATED: Skipping duplicate initial event for $phoneNumber ($outcome)");
        return;
      }
      
      // Set the tracker for initial events
      _currentlyProcessingCall = phoneNumber; 
      
      // Route to the handler that finds/creates the lead and opens the UI
      _handleCallStarted(
        phoneNumber: phoneNumber,
        direction: event['direction'] as String,
        outcome: outcome,
      );
    } 
    // 🎯 TERMINAL STATE LOGIC: 'ended', 'missed', 'rejected'
    else {
      // Clear the tracker for terminal events
      if (_currentlyProcessingCall == phoneNumber) {
          _currentlyProcessingCall = null;
      }

      // Route to the handler that only logs the event (no UI open)
      // ✅ FIX: duration is passed to handleCallUpdate
      _handleCallUpdate(
        phoneNumber: phoneNumber,
        direction: event['direction'] as String,
        outcome: outcome,
        duration: event['duration'] as int?,
      );
    }
  }


  // --------------------------------------------------------------------------
  // HANDLERS 
  // --------------------------------------------------------------------------
  void _handleCallStarted({
    required String phoneNumber,
    required String direction,
    required String outcome,
  }) async {
    try {
      // 1. Find or Create (ensures a lead exists and is saved once)
      // This step fetches/creates the lead and saves a basic update.
      await _leadService.findOrCreateLead(
        phone: phoneNumber,
        finalOutcome: 'none', 
      );

      // 2. Add Event (Logs the event and saves/returns the updated Lead object with all data)
      // This step fetches the latest data (including name/email) via getLead and updates history.
      final Lead lead = await _leadService.addCallEvent( 
        phone: phoneNumber,
        direction: direction,
        outcome: outcome,
        durationInSeconds: null, 
      );

      // 🎯 CRITICAL FIX: Only open the UI on 'ringing' or 'answered' events.
      if (outcome == 'ringing' || outcome == 'answered') {
          print('📞 New call. Opening UI with lead ID: ${lead.id}');
          // 3. Open UI: Pass the lead, which contains all pre-filled data and new history.
          _openLeadUI(lead);
      }
    } catch (e) {
      print("❌ Error handling call start: $e");
    }
  }

  void _handleCallUpdate({
    required String phoneNumber,
    required String direction,
    required String outcome,
    // ✅ NEW: duration from Android event
    int? duration, 
  }) async {
    try {
      // 1. Log the update event (ended, missed, rejected).
      await _leadService.addCallEvent(
        phone: phoneNumber,
        direction: direction,
        outcome: outcome,
        // ✅ NEW: Pass the duration to the service layer
        durationInSeconds: duration, 
      );

      // No screen update needed here.
    } catch (e) {
      print("❌ Error handling call update: $e");
    }
  }

  // --------------------------------------------------------------------------
  // UI HANDLERS
  // --------------------------------------------------------------------------
  
  void _updateLeadScreen(Lead updatedLead) {
    // This is intentionally left simple.
  }

  // ---------------------------------------------------------------------------
  // OPEN THE SCREEN SAFELY
  // ---------------------------------------------------------------------------
  void _openLeadUI(Lead lead) {
    if (_screenOpen) {
      print("⚠️ SCREEN ALREADY OPEN — skipping");
      return;
    }

    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null) {
      print("❌ NO CONTEXT — delaying open");
      Future.delayed(const Duration(milliseconds: 300), () {
        _openLeadUI(lead);
      });
      return;
    }

    _screenOpen = true;
    print("📞 OPENING UI FOR ${lead.phoneNumber}");

    navigatorKey.currentState!.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/lead-form'),
        fullscreenDialog: true,
        builder: (_) => LeadFormScreen(
          // Pass the complete lead object containing all existing data and new history
          lead: lead,
          autoOpenedFromCall: true,
        ),
      ),
    ).then((_) {
      // Allow reopen after user closes screen
      Future.delayed(const Duration(milliseconds: 250), () {
        _screenOpen = false;
      });
    });
  }
}