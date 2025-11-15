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

  /// State tracker for call deduplication
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
  // EVENT PROCESSOR
  // --------------------------------------------------------------------------
  void _processCallEvent(Map<String, dynamic> event) {
    print('📞 RAW EVENT → $event');
    final phoneNumber = event['phoneNumber'] as String?;
    final outcome = event['outcome'] as String?;
    final direction = event['direction'] as String?;
    
    // 🔥 NEW: Extract timestamp and duration
    final timestampMs = event['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final duration = event['durationInSeconds'] as int?; 
    
    if (phoneNumber == null || phoneNumber.isEmpty || outcome == null || direction == null) {
      print("! Ignoring invalid call event.");
      return;
    }

    final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);

    // 🎯 INITIAL/UI TRIGGER STATES: 'ringing', 'started', 'answered'
    if (['ringing', 'started', 'answered'].contains(outcome)) {
      
      // Deduplicate only 'ringing' and 'started' to allow 'answered' to potentially open the UI again
      if ((outcome == 'ringing' || outcome == 'started') && _currentlyProcessingCall == phoneNumber) {
        print("! DEDUPLICATED: Skipping duplicate initial event for $phoneNumber ($outcome)");
        return;
      }
      
      _currentlyProcessingCall = phoneNumber; 
      
      _handleCallStarted(
        phoneNumber: phoneNumber,
        direction: direction,
        outcome: outcome,
        timestamp: timestamp, // Pass timestamp
      );
    } 
    // 🎯 TERMINAL STATE LOGIC: 'ended', 'missed', 'rejected'
    else if (['ended', 'missed', 'rejected'].contains(outcome)) {
      
      // Clear the tracker for terminal events
      if (_currentlyProcessingCall == phoneNumber) {
        _currentlyProcessingCall = null;
      }

      // Route to the handler that logs the final event and checks for review
      _handleCallUpdate(
        phoneNumber: phoneNumber,
        direction: direction,
        outcome: outcome,
        durationInSeconds: duration, // Pass the rich data
        timestamp: timestamp, // Pass timestamp
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
    required DateTime timestamp, 
  }) async {
    try {
      // 1. Add Event (Logs the event and saves/returns the updated Lead object with all data)
      // We rely on this method to find or create the lead first.
      final Lead lead = await _leadService.addCallEvent( 
        phone: phoneNumber,
        direction: direction,
        outcome: outcome,
        timestamp: timestamp, 
        durationInSeconds: null, 
      );

      // 🎯 CRITICAL: Only open the UI on 'ringing' or 'answered' events.
      if (outcome == 'ringing' || outcome == 'answered') {
          print('📞 New call. Opening UI with lead ID: ${lead.id}');
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
    required DateTime timestamp,
    int? durationInSeconds, 
  }) async {
    try {
      // 🔥 Use a dedicated method for final events to log the event and handle the review flag
      final Lead? updatedLead = await _leadService.addFinalCallEvent(
        phone: phoneNumber,
        direction: direction,
        outcome: outcome,
        timestamp: timestamp,
        durationInSeconds: durationInSeconds, 
      );
      
      if (updatedLead == null) return;
      
      // 🎯 CRITICAL FIX: If the service set needsManualReview (missed/rejected call), open the UI.
      if (updatedLead.needsManualReview) {
          print('📞 Final event $outcome requires review. Opening UI.');
          _openLeadUI(updatedLead);
      }
      
    } catch (e) {
      print("❌ Error handling call update: $e");
    }
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
          lead: lead,
          autoOpenedFromCall: true, // Crucial flag for LeadFormScreen.dispose() logic
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