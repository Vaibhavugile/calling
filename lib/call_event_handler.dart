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

  // 🔥 REMOVED: MethodChannel is no longer needed to check for initial calls.
  // static const MethodChannel _methodChannel =
  //     MethodChannel("com.example.call_leads_app/initialCall");

  final LeadService _leadService = LeadService();

  StreamSubscription? _subscription;

  /// Prevents multiple screens from opening
  bool _screenOpen = false;

  // 🔥 REMOVED: Pending events are now buffered in the native CallService.kt
  // final List<Map<String, dynamic>> _pendingEvents = [];

  CallEventHandler({required this.navigatorKey});

  // ---------------------------------------------------------------------------
  // START LISTENING
  // ---------------------------------------------------------------------------
  void startListening() {
    print("📞 [CALL HANDLER] START LISTENING");

    // 🔥 REMOVED: _checkInitialCall() is obsolete
    // _checkInitialCall();
    
    // 🔥 The native side now flushes the pending event upon connection,
    // so we only need to listen for stream events.

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

  // 🔥 REMOVED: The native side now handles initial call logic
  // Future<void> _checkInitialCall() async {
  //   try {
  //     print("⏳ Checking for initial call...");
  //     final result =
  //         await _methodChannel.invokeMethod<Map<Object?, Object?>>('get');

  //     if (result != null) {
  //       final phone = result['phoneNumber'] as String?;
  //       if (phone != null) {
  //         print("📞 INITIAL CALL → $phone");
  //         await _handleCallStarted(phone);
  //       }
  //     }

  //     print("⏳ Processing pending events: ${_pendingEvents.length}");
  //     // Now that we're connected and checked initial state, process the buffer
  //     for (var event in _pendingEvents) {
  //       _processCallEvent(
  //         event['phoneNumber'] as String,
  //         event['direction'] as String,
  //         event['outcome'] as String,
  //       );
  //     }
  //     _pendingEvents.clear();
  //   } on PlatformException catch (e) {
  //     print("❌ Failed to get initial call: ${e.message}");
  //   }
  // }

  // ---------------------------------------------------------------------------
  // PROCESS EVENT
  // ---------------------------------------------------------------------------
  Future<void> _processCallEvent(
      String phone, String direction, String outcome) async {
    // 🔥 REMOVED: Pending event buffer no longer needed.
    // // If phone is empty, it's a transient state we can ignore
    // if (phone.isEmpty) return;

    // // If screen is not open yet, buffer the event
    // if (!_initDone) {
    //   _pendingEvents.add(
    //       {'phoneNumber': phone, 'direction': direction, 'outcome': outcome});
    //   return;
    // }

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
    // 1. Find or create the lead
    Lead? lead = _leadService.findByPhone(phone);
    if (lead == null) {
      lead = await _leadService.createLead(phone);
    }

    // 2. Add the initial event to the lead's history
    lead = await _leadService.addCallEvent(
      phone: phone,
      direction: direction,
      outcome: direction == "inbound" ? "ringing" : "started",
    );

    // 3. Open the UI
    _openLeadUI(lead);
  }

  // ---------------------------------------------------------------------------
  // HANDLE CALL UPDATE (Answered / Ended / Missed)
  // ---------------------------------------------------------------------------
  Future<void> _handleCallUpdate(
      String phone, String direction, String outcome) async {
    // 1. Find the lead (must exist from the 'started' event)
    Lead? lead = _leadService.findByPhone(phone);
    if (lead == null) {
      print("⚠️ Cannot find lead for $phone to record $outcome event.");
      return;
    }

    // 2. Add the event to the lead's history
    lead = await _leadService.addCallEvent(
      phone: phone,
      direction: direction,
      outcome: outcome,
    );
    
    // 3. (Optional) Check for a final event (ended/missed) to ensure UI is closed
    if (outcome == 'ended' || outcome == 'missed') {
       // Future.delayed(Duration(seconds: 1), () => _screenOpen = false);
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
        fullscreenDialog: true,
        builder: (_) => LeadFormScreen(
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

  // ---------------------------------------------------------------------------
  // CLEAN UP
  // ---------------------------------------------------------------------------
  void dispose() {
    _subscription?.cancel();
  }
}