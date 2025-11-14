// lib/models/lead.dart
import 'dart:math';

/// Call history entry uses DateTime inside the app.
class CallHistoryEntry {
  final String direction; // inbound / outbound
  // 🔥 MODIFIED: outcome now uses final statuses for history: answered / missed / rejected / ended
  final String outcome; 
  final DateTime timestamp;
  final String note;
  // 🔥 NEW: Optional field to store duration in seconds
  final int? durationInSeconds; 

  CallHistoryEntry({
    required this.direction,
    required this.outcome,
    required this.timestamp,
    this.note = '',
    this.durationInSeconds, // 🔥 NEW: Added to constructor
  });

  factory CallHistoryEntry.fromMap(Map<String, dynamic> map) {
    // Accept either an int (ms since epoch) or an ISO string; fallback to now.
    final raw = map['timestamp'];
    DateTime ts;
    if (raw is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(raw);
    } else if (raw is String) {
      ts = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    return CallHistoryEntry(
      direction: (map['direction'] ?? 'unknown').toString(),
      outcome: (map['outcome'] ?? 'unknown').toString(),
      timestamp: ts,
      note: (map['note'] ?? '').toString(),
      durationInSeconds: map['durationInSeconds'] as int?, // 🔥 NEW: Read from map
    );
  }

  Map<String, dynamic> toMap() => {
        'direction': direction,
        'outcome': outcome,
        // store as milliseconds for compactness / compatibility
        'timestamp': timestamp.millisecondsSinceEpoch,
        'note': note,
        'durationInSeconds': durationInSeconds, // 🔥 NEW: Write to map
      };
}

/// A lead that represents a phone contact.
class Lead {
  final String id;
  final String name;
  final String phoneNumber;
  final String status;
  // 🔥 NEW: Field to help filter in the list page (e.g., 'answered', 'missed')
  final String lastCallOutcome;
  final DateTime lastInteraction;
  final DateTime lastUpdated;
  final List<LeadNote> notes;
  final List<CallHistoryEntry> callHistory;

  Lead({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.status,
    // 🔥 NEW
    this.lastCallOutcome = 'none',
    required this.lastInteraction,
    required this.lastUpdated,
    this.notes = const [],
    this.callHistory = const [],
  });

  static String generateId() => DateTime.now().millisecondsSinceEpoch.toString() +
      Random().nextInt(1000).toString();

  factory Lead.newLead(String phoneNumber) {
    return Lead(
      id: generateId(),
      name: '',
      phoneNumber: phoneNumber,
      status: 'new',
      lastCallOutcome: 'none', // 🔥 NEW
      lastInteraction: DateTime.now(),
      lastUpdated: DateTime.now(),
      notes: [],
      callHistory: [],
    );
  }

  Lead copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? status,
    // 🔥 NEW
    String? lastCallOutcome,
    DateTime? lastInteraction,
    DateTime? lastUpdated,
    List<LeadNote>? notes,
    List<CallHistoryEntry>? callHistory,
  }) {
    return Lead(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      status: status ?? this.status,
      // 🔥 NEW
      lastCallOutcome: lastCallOutcome ?? this.lastCallOutcome,
      lastInteraction: lastInteraction ?? this.lastInteraction,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      notes: notes ?? this.notes,
      callHistory: callHistory ?? this.callHistory,
    );
  }

  factory Lead.fromMap(Map<String, dynamic> map) {
    final lastInteractionRaw = map['lastInteraction'];
    DateTime lastInteraction;
    if (lastInteractionRaw is int) {
      lastInteraction = DateTime.fromMillisecondsSinceEpoch(lastInteractionRaw);
    } else if (lastInteractionRaw is String) {
      lastInteraction = DateTime.tryParse(lastInteractionRaw) ?? DateTime.now();
    } else {
      lastInteraction = DateTime.now();
    }

    final lastUpdatedRaw = map['lastUpdated'];
    DateTime lastUpdated;
    if (lastUpdatedRaw is int) {
      lastUpdated = DateTime.fromMillisecondsSinceEpoch(lastUpdatedRaw);
    } else if (lastUpdatedRaw is String) {
      lastUpdated = DateTime.tryParse(lastUpdatedRaw) ?? DateTime.now();
    } else {
      lastUpdated = DateTime.now();
    }

    final notesList = (map['notes'] as List<dynamic>?) ?? [];
    final callsList = (map['callHistory'] as List<dynamic>?) ?? [];

    return Lead(
      id: (map['id'] ?? generateId()).toString(),
      name: (map['name'] ?? '').toString(),
      phoneNumber: (map['phoneNumber'] ?? '').toString(),
      status: (map['status'] ?? 'new').toString(),
      // 🔥 NEW: Set default to 'none' if missing
      lastCallOutcome: (map['lastCallOutcome'] ?? 'none').toString(),
      lastInteraction: lastInteraction,
      lastUpdated: lastUpdated,
      notes: notesList.map((e) => LeadNote.fromMap(Map<String, dynamic>.from(e))).toList(),
      callHistory: callsList.map((e) => CallHistoryEntry.fromMap(Map<String, dynamic>.from(e))).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phoneNumber': phoneNumber,
        'status': status,
        // 🔥 NEW
        'lastCallOutcome': lastCallOutcome, 
        'lastInteraction': lastInteraction.millisecondsSinceEpoch,
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
        'notes': notes.map((e) => e.toMap()).toList(),
        'callHistory': callHistory.map((e) => e.toMap()).toList(),
      };
}

/// A note entry attached to a lead.
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
      ts = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    return LeadNote(
      text: (map['text'] ?? '').toString(),
      timestamp: ts,
    );
  }

  Map<String, dynamic> toMap() => {
        'text': text,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };
}