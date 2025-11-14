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

  CallEventHandler({required this.navigatorKey});

  // --------------------------------------------------------------------------
  // START LISTENING & CLEANUP
  // --------------------------------------------------------------------------
  void startListening() {
    print("📞 [CALL HANDLER] START LISTENING");
    
    _subscription = _eventChannel
        .receiveBroadcastStream()
        // 🔥 FIX: Removed .cast<Map<String, dynamic>>() to prevent type error
        .listen(
      (event) {
        // 🔥 FIX: Explicitly create a new Map<String, dynamic> from the raw event
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
  
  // ✅ FIX: Add dispose method for cleanup in main.dart
  void dispose() {
    stopListening();
  }

  // --------------------------------------------------------------------------
  // EVENT PROCESSOR
  // --------------------------------------------------------------------------
  void _processCallEvent(Map<String, dynamic> event) {
    print('📞 RAW EVENT → $event');
    final phoneNumber = event['phoneNumber'] as String;
    final direction = event['direction'] as String;
    final outcome = event['outcome'] as String;
    final duration = event['duration'] as int?; 

    if (phoneNumber.isEmpty) {
      print("! Ignoring call event with empty phone number: $outcome");
      return;
    }

    if (outcome == 'ringing' || outcome == 'started') {
      _handleCallStarted(
        phoneNumber: phoneNumber,
        direction: direction,
        outcome: outcome,
      );
    } else {
      _handleCallUpdate(
        phoneNumber: phoneNumber,
        direction: direction,
        outcome: outcome,
        duration: duration,
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
      // 1. Ensure lead exists (creates new one if necessary) - Fixes "Lead not found"
      await _leadService.findOrCreateLead(
        phone: phoneNumber,
        finalOutcome: 'none', 
      );

      // 2. Log the initial event
      final Lead lead = await _leadService.addCallEvent( 
        phone: phoneNumber,
        direction: direction,
        outcome: outcome,
        durationInSeconds: null, 
      );

      print('📞 New call. Opening UI with transient lead: $phoneNumber');
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
      // 1. Log the update event (answered, ended, missed, rejected)
      await _leadService.addCallEvent(
        phone: phoneNumber,
        direction: direction,
        outcome: outcome,
        durationInSeconds: duration, 
      );

      // We rely on the screen refreshing itself on resume/focus.
      
    } catch (e) {
      print("❌ Error handling call update: $e");
    }
  }

  // --------------------------------------------------------------------------
  // UI HANDLERS
  // --------------------------------------------------------------------------
  
  // ✅ FIX: Empty implementation of a method that used to cause 'LeadFormScreenState' errors
  void _updateLeadScreen(Lead updatedLead) {
    // Rely on the screen refreshing itself on resume/focus.
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
          autoOpenedFromCall: true,
          // ✅ FIX: Removed the 'callDirection' parameter entirely 
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