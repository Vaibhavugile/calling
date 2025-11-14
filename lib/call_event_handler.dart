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
  // EVENT PROCESSOR (Now includes deduplication logic)
  // --------------------------------------------------------------------------
  void _processCallEvent(Map<String, dynamic> event) {
    print('📞 RAW EVENT → $event');
    final phoneNumber = event['phoneNumber'] as String;
    // final direction = event['direction'] as String; // Not used directly here
    final outcome = event['outcome'] as String;
    // final duration = event['duration'] as int?; // Not used directly here

    if (phoneNumber.isEmpty) {
      print("! Ignoring call event with empty phone number: $outcome");
      return;
    }

    // 🎯 DEDUPLICATION LOGIC
    if (outcome == 'ringing' || outcome == 'started') {
      if (_currentlyProcessingCall == phoneNumber) {
        print("! DEDUPLICATED: Skipping duplicate initial event for $phoneNumber ($outcome)");
        return;
      }
      // If it's a new ringing/started event, set the tracker
      _currentlyProcessingCall = phoneNumber; 
      
      // Pass the event to the original handler
      _handleCallStarted(
        phoneNumber: phoneNumber,
        direction: event['direction'] as String,
        outcome: outcome,
      );
    } 
    // 🎯 TERMINAL STATE LOGIC
    else {
      // Clear the tracker for terminal events (ended, missed, rejected)
      if (_currentlyProcessingCall == phoneNumber) {
         _currentlyProcessingCall = null;
      }

      // Pass the event to the original handler
      _handleCallUpdate(
        phoneNumber: phoneNumber,
        direction: event['direction'] as String,
        outcome: outcome,
        duration: event['duration'] as int?,
      );
    }
  }


  // --------------------------------------------------------------------------
  // HANDLERS (Ensures existing lead data is preserved and updated)
  // --------------------------------------------------------------------------
  void _handleCallStarted({
    required String phoneNumber,
    required String direction,
    required String outcome,
  }) async {
    try {
      // 1. Find or Create (ensures a lead exists and is saved once)
      await _leadService.findOrCreateLead(
        phone: phoneNumber,
        // Using 'none' here as the final outcome is determined by the last event
        finalOutcome: 'none', 
      );

      // 2. Add Event (Logs the 'ringing'/'started' event and saves/returns the updated Lead)
      final Lead lead = await _leadService.addCallEvent( 
        phone: phoneNumber,
        direction: direction,
        outcome: outcome,
        durationInSeconds: null, 
      );

      print('📞 New call. Opening UI with lead ID: ${lead.id}');
      // 3. Open UI: Pass the lead, which contains all pre-filled data and new history.
      _openLeadUI(lead);
    } catch (e) {
      print("❌ Error handling call start: $e");
    }
  }

  void _handleCallUpdate({
    required String phoneNumber,
    required String direction,
    required String outcome,
    int? duration,
  }) async {
    try {
      // 1. Log the update event (answered, ended, missed, rejected).
      // This implicitly updates the existing lead in the database.
      await _leadService.addCallEvent(
        phone: phoneNumber,
        direction: direction,
        outcome: outcome,
        durationInSeconds: duration, 
      );

      // No screen update needed here; the form screen should refresh on its own if active.
      
    } catch (e) {
      print("❌ Error handling call update: $e");
    }
  }

  // --------------------------------------------------------------------------
  // UI HANDLERS
  // --------------------------------------------------------------------------
  
  // Empty implementation of a method that used to cause 'LeadFormScreenState' errors
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
          // Removed 'callDirection' parameter, as it is obsolete.
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