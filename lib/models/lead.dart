// lib/models/lead.dart
import 'dart:math';

/// Normalize phone to digits-only for internal canonical form.
String _normalizePhone(String? raw) {
  if (raw == null) return '';
  return raw.replaceAll(RegExp(r'\D'), '');
}

/// Entry in call history.
class CallHistoryEntry {
  final String direction; // inbound / outbound
  final String outcome; // answered / missed / rejected / ended / ringing / started / outgoing_start
  final DateTime timestamp;
  final String note;
  final int? durationInSeconds;

  CallHistoryEntry({
    required this.direction,
    required this.outcome,
    required this.timestamp,
    this.note = '',
    this.durationInSeconds,
  });

  /// Intermediate means non-terminal (we may later replace with ended)
  bool get isIntermediate {
    final o = outcome.toLowerCase();
    return o == 'ringing' || o == 'started' || o == 'outgoing_start' || o == 'answered';
  }

  factory CallHistoryEntry.fromMap(Map<String, dynamic> map) {
    final raw = map['timestamp'];
    DateTime ts;
    if (raw is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(raw);
    } else if (raw is String) {
      ts = DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      ts = DateTime.fromMillisecondsSinceEpoch(0);
    }

    int? dur;
    final durRaw = map['durationInSeconds'];
    if (durRaw is int) dur = durRaw;
    if (durRaw is String) dur = int.tryParse(durRaw);

    return CallHistoryEntry(
      direction: (map['direction'] ?? 'unknown').toString(),
      outcome: (map['outcome'] ?? 'unknown').toString(),
      timestamp: ts,
      note: (map['note'] ?? '').toString(),
      durationInSeconds: dur,
    );
  }

  Map<String, dynamic> toMap() => {
        'direction': direction,
        'outcome': outcome,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'note': note,
        'durationInSeconds': durationInSeconds,
      };
}

/// Simple note attached to a lead.
class LeadNote {
  final String text;
  final DateTime timestamp;

  LeadNote({required this.text, required this.timestamp});

  factory LeadNote.fromMap(Map<String, dynamic> map) {
    final raw = map['timestamp'];
    DateTime ts;
    if (raw is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(raw);
    } else if (raw is String) {
      ts = DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      ts = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return LeadNote(text: (map['text'] ?? '').toString(), timestamp: ts);
  }

  Map<String, dynamic> toMap() => {
        'text': text,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };
}

/// Lead model stored in Firestore.
class Lead {
  final String id;
  final String name;
  final String phoneNumber; // normalized digits-only
  final String status;
  final String lastCallOutcome;
  final DateTime lastInteraction;
  final DateTime lastUpdated;
  final List<LeadNote> notes;
  final List<CallHistoryEntry> callHistory;
  final bool needsManualReview;

  Lead({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.status,
    this.lastCallOutcome = 'none',
    required this.lastInteraction,
    required this.lastUpdated,
    this.notes = const [],
    this.callHistory = const [],
    this.needsManualReview = false,
  });

  static String generateId() => DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(1000).toString();

  factory Lead.newLead(String rawPhone) {
    final phone = _normalizePhone(rawPhone);
    final now = DateTime.now();
    return Lead(
      id: generateId(),
      name: '',
      phoneNumber: phone,
      status: 'new',
      lastCallOutcome: 'none',
      lastInteraction: now,
      lastUpdated: now,
      notes: [],
      callHistory: [],
      needsManualReview: false,
    );
  }

  Lead copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? status,
    String? lastCallOutcome,
    DateTime? lastInteraction,
    DateTime? lastUpdated,
    List<LeadNote>? notes,
    List<CallHistoryEntry>? callHistory,
    bool? needsManualReview,
  }) {
    return Lead(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber != null ? _normalizePhone(phoneNumber) : this.phoneNumber,
      status: status ?? this.status,
      lastCallOutcome: lastCallOutcome ?? this.lastCallOutcome,
      lastInteraction: lastInteraction ?? this.lastInteraction,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      notes: notes ?? this.notes,
      callHistory: callHistory ?? this.callHistory,
      needsManualReview: needsManualReview ?? this.needsManualReview,
    );
  }

  factory Lead.fromMap(Map<String, dynamic> map) {
    final lastInteractionRaw = map['lastInteraction'];
    DateTime lastInteraction;
    if (lastInteractionRaw is int) {
      lastInteraction = DateTime.fromMillisecondsSinceEpoch(lastInteractionRaw);
    } else if (lastInteractionRaw is String) {
      lastInteraction = DateTime.tryParse(lastInteractionRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      lastInteraction = DateTime.fromMillisecondsSinceEpoch(0);
    }

    final lastUpdatedRaw = map['lastUpdated'];
    DateTime lastUpdated;
    if (lastUpdatedRaw is int) {
      lastUpdated = DateTime.fromMillisecondsSinceEpoch(lastUpdatedRaw);
    } else if (lastUpdatedRaw is String) {
      lastUpdated = DateTime.tryParse(lastUpdatedRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);
    }

    final notesList = (map['notes'] as List<dynamic>?) ?? [];
    final callsList = (map['callHistory'] as List<dynamic>?) ?? [];

    final history = callsList
        .map((e) => CallHistoryEntry.fromMap(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp)); // oldest -> newest

    return Lead(
      id: (map['id'] ?? generateId()).toString(),
      name: (map['name'] ?? '').toString(),
      phoneNumber: _normalizePhone((map['phoneNumber'] ?? '').toString()),
      status: (map['status'] ?? 'new').toString(),
      lastCallOutcome: (map['lastCallOutcome'] ?? 'none').toString(),
      lastInteraction: lastInteraction,
      lastUpdated: lastUpdated,
      notes: notesList.map((e) => LeadNote.fromMap(Map<String, dynamic>.from(e))).toList(),
      callHistory: history,
      needsManualReview: (map['needsManualReview'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phoneNumber': phoneNumber,
        'status': status,
        'lastCallOutcome': lastCallOutcome,
        'lastInteraction': lastInteraction.millisecondsSinceEpoch,
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
        'notes': notes.map((e) => e.toMap()).toList(),
        'callHistory': callHistory.map((e) => e.toMap()).toList(),
        'needsManualReview': needsManualReview,
      };
}
