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

  /// State tracker for call deduplication: maps phoneNumber -> lastTimestampMs processed
  final Map<String, int> _lastProcessedTimestampMs = {};

  /// Optional flag to mark a call being actively processed (phone -> bool)
  final Set<String> _activeCalls = {};

  /// A short dedup window (ms) to ignore near-duplicate initial events
  /// (2000 ms = 2 seconds)
  static const int _dedupWindowMs = 2000;

  CallEventHandler({required this.navigatorKey});

  // --------------------------------------------------------------------------
  // START LISTENING & CLEANUP
  // --------------------------------------------------------------------------
  void startListening() {
    print("📞 [CALL HANDLER] START LISTENING");

    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        try {
          final Map<String, dynamic> typedEvent =
              Map<String, dynamic>.from(event as Map);
          _processCallEvent(typedEvent);
        } catch (e) {
          print("❌ Error parsing incoming event: $e — raw event: $event");
        }
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
    // Improved logging
    print('📞 RAW EVENT RECEIVED → $event');

    final phoneNumber = (event['phoneNumber'] as String?)?.trim();
    final outcome = (event['outcome'] as String?)?.trim();
    final direction = (event['direction'] as String?)?.trim();

    final timestampMs =
        (event['timestamp'] is int) ? event['timestamp'] as int : null;
    final duration = (event['durationInSeconds'] is int)
        ? event['durationInSeconds'] as int
        : null;

    final int eventTimestamp =
        timestampMs ?? DateTime.now().millisecondsSinceEpoch;

    if (phoneNumber == null ||
        phoneNumber.isEmpty ||
        outcome == null ||
        direction == null) {
      print("! Ignoring invalid or incomplete call event.");
      return;
    }

    // Deduplication: ignore repeated initial events within _dedupWindowMs
    final lastTs = _lastProcessedTimestampMs[phoneNumber];
    if (lastTs != null &&
        (eventTimestamp - lastTs).abs() < _dedupWindowMs &&
        _isInitialEvent(outcome)) {
      print(
          "! DEDUPLICATED: Ignoring quick duplicate event for $phoneNumber ($outcome). Δ=${(eventTimestamp - lastTs).abs()}ms");
      return;
    }

    // Update last-processed timestamp for this phone number for any event
    _lastProcessedTimestampMs[phoneNumber] = eventTimestamp;

    // Terminal events: ended/missed/rejected
    if (_isTerminalEvent(outcome)) {
      // Clear active marker for this call (if present)
      if (_activeCalls.contains(phoneNumber)) {
        _activeCalls.remove(phoneNumber);
      }

      _handleCallUpdate(
        phoneNumber: phoneNumber,
        direction: direction,
        outcome: outcome,
        durationInSeconds: duration,
        timestamp: DateTime.fromMillisecondsSinceEpoch(eventTimestamp),
      );
      return;
    }

    // Initial / UI-trigger events: ringing, outgoing_start, answered
    if (_isInitialEvent(outcome)) {
      // If screen already open for another call, don't open again — but still record events
      if (_activeCalls.contains(phoneNumber)) {
        // We already processed a start for this call; skip UI logic but still log/state.
        print("! Already processing call for $phoneNumber — skipping repeated start event.");
        return;
      }

      // Mark as active to prevent duplicates opening UI
      _activeCalls.add(phoneNumber);

      _handleCallStarted(
        phoneNumber: phoneNumber,
        direction: direction,
        outcome: outcome,
        timestamp: DateTime.fromMillisecondsSinceEpoch(eventTimestamp),
      );

      return;
    }

    // If we reach here, the event is unknown; log it
    print("! Unhandled event outcome: $outcome for $phoneNumber");
  }

  bool _isInitialEvent(String outcome) {
    return outcome == 'ringing' ||
        outcome == 'outgoing_start' ||
        outcome == 'answered';
  }

  bool _isTerminalEvent(String outcome) {
    return outcome == 'ended' || outcome == 'missed' || outcome == 'rejected';
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
      final Lead lead = await _leadService.addCallEvent(
        phone: phoneNumber,
        direction: direction,
        outcome: outcome,
        timestamp: timestamp,
        durationInSeconds: null,
      );

      // Decide whether to open UI: ringing, answered, outgoing_start -> open
      if (outcome == 'ringing' || outcome == 'answered' || outcome == 'outgoing_start') {
        print('📞 New call. Opening UI with lead ID: ${lead.id}');
        _openLeadUI(lead);
      }
    } catch (e) {
      print("❌ Error handling call start for $phoneNumber: $e");
      // Ensure we don't leave the active marker forever if error occurs
      if (_activeCalls.contains(phoneNumber)) {
        _activeCalls.remove(phoneNumber);
      }
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
      final Lead? updatedLead = await _leadService.addFinalCallEvent(
        phone: phoneNumber,
        direction: direction,
        outcome: outcome,
        timestamp: timestamp,
        durationInSeconds: durationInSeconds,
      );

      if (updatedLead == null) {
        print("! No lead returned for final event $outcome on $phoneNumber");
        return;
      }

      // Open UI for terminal events to allow notes/followup
      print('📞 Final event $outcome finished for $phoneNumber. Opening UI for follow-up.');
      _openLeadUI(updatedLead);
    } catch (e) {
      print("❌ Error handling call update for $phoneNumber: $e");
    } finally {
      // ensure cleanup of active marker
      _activeCalls.remove(phoneNumber);
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
      print("❌ NO CONTEXT — delaying open. (Is the app fully initialized?)");
      // One retry after 500ms
      Future.delayed(const Duration(milliseconds: 500), () {
        final retryCtx = navigatorKey.currentState?.overlay?.context;
        if (retryCtx == null) {
          print("❌ STILL NO CONTEXT — aborting open.");
          return;
        }
        _openLeadUI(lead);
      });
      return;
    }

    _screenOpen = true;
    print("📞 OPENING UI FOR ${lead.phoneNumber}");

    navigatorKey.currentState!
        .push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/lead-form'),
        fullscreenDialog: true,
        builder: (_) => LeadFormScreen(
          lead: lead,
          autoOpenedFromCall: true,
        ),
      ),
    )
        .then((_) {
      // allow reopen after user closes screen
      Future.delayed(const Duration(milliseconds: 250), () {
        _screenOpen = false;
      });
    });
  }
}
