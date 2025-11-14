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

  // ---------------------------------------------------------------------------
  // START LISTENING
  // ---------------------------------------------------------------------------
  void startListening() {
    print("📞 [CALL HANDLER] START LISTENING");

    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        print("📞 RAW EVENT → $event");
        if (event == null) return;

        final parsed = Map<String, dynamic>.from(event);

        // Process the event
        _processCallEvent(
          parsed['phoneNumber'] as String,
          parsed['direction'] as String,
          parsed['outcome'] as String,
        );
      },
      onError: (error) {
        print("❌ EVENT CHANNEL ERROR: $error");
      },
      onDone: () {
        print("❌ EVENT CHANNEL CLOSED");
      },
    );
  }

  // ---------------------------------------------------------------------------
  // PROCESS EVENT
  // ---------------------------------------------------------------------------
  Future<void> _processCallEvent(
      String phone, String direction, String outcome) async {
    
    // ✅ FIX 1: Ignore events with empty phone numbers
    if (phone.isEmpty) {
        print("⚠️ Ignoring call event with empty phone number: $outcome");
        return;
    }

    // Logic to handle call started (ringing/outbound)
    if (outcome == "ringing" || outcome == "started") {
      await _handleCallStarted(phone, direction);
    }
    
    // Logic to handle call updates (answered, ended, missed)
    else {
      await _handleCallUpdate(phone, direction, outcome);
    }
  }

  // ---------------------------------------------------------------------------
  // HANDLE CALL STARTED (Ringing / Outbound Started)
  // ---------------------------------------------------------------------------
  Future<void> _handleCallStarted(String phone, String direction) async {
    // 1. Check if Lead exists in Firestore
    Lead? existingLead = _leadService.findByPhone(phone);

    Lead leadToPass;
    
    if (existingLead != null) {
      // Lead exists, pass the existing lead
      leadToPass = existingLead;
      print("📞 Existing lead found. Opening UI: ${leadToPass.phoneNumber}");
    } else {
      // Lead is NEW, create a transient (in-memory) Lead object.
      // 🔥 FIX 2: Added required named parameters 'lastInteraction' and 'lastUpdated'.
      leadToPass = Lead(
        id: '', // Empty ID means this is a transient lead
        phoneNumber: phone,
        name: '',
        status: 'new',
        lastCallOutcome: 'none', // Use default from model
        lastInteraction: DateTime.now(), // REQUIRED
        lastUpdated: DateTime.now(), // REQUIRED
        callHistory: [],
        notes: [],
      );
      print("📞 New call. Opening UI with transient lead: ${leadToPass.phoneNumber}");
    }

    // 2. Open the UI, passing the call direction
    _openLeadUI(leadToPass, direction);
  }

  // ---------------------------------------------------------------------------
  // HANDLE CALL UPDATE (Answered / Ended / Missed)
  // ---------------------------------------------------------------------------
  Future<void> _handleCallUpdate(
      String phone, String direction, String outcome) async {
    // 1. Find the lead (must exist from a previous save action)
    Lead? lead = _leadService.findByPhone(phone);
    if (lead == null) {
      print("⚠️ Cannot find lead for $phone to record $outcome event. (Lead not saved by user yet).");
      return;
    }

    // 2. Add the event to the lead's history
    await _leadService.addCallEvent(
      phone: phone,
      direction: direction,
      outcome: outcome,
    );
  }

  // ---------------------------------------------------------------------------
  // OPEN THE SCREEN SAFELY
  // ---------------------------------------------------------------------------
  void _openLeadUI(Lead lead, String? callDirection) {
    if (_screenOpen) {
      print("⚠️ SCREEN ALREADY OPEN — skipping");
      return;
    }

    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null) {
      print("❌ NO CONTEXT — delaying open");
      Future.delayed(const Duration(milliseconds: 300), () {
        _openLeadUI(lead, callDirection);
      });
      return;
    }

    _screenOpen = true;
    print("📞 OPENING UI FOR ${lead.phoneNumber}");

    navigatorKey.currentState!.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LeadFormScreen(
          lead: lead,
          autoOpenedFromCall: true,
          callDirection: callDirection,
        ),
      ),
    ).then((_) {
      // Allow reopen after user closes screen
      Future.delayed(const Duration(milliseconds: 250), () {
        _screenOpen = false;
      });
    });
  }

  // ---------------------------------------------------------------------------
  // CLEAN UP
  // ---------------------------------------------------------------------------
  void dispose() {
    _subscription?.cancel();
  }
}