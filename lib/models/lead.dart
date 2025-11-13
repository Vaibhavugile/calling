// lib/models/lead.dart
import 'dart:math';

/// Call history entry uses DateTime inside the app.
class CallHistoryEntry {
  final String direction; // inbound / outbound
  final String outcome; // ringing / answered / missed / ended / started
  final DateTime timestamp;
  final String note;

  CallHistoryEntry({
    required this.direction,
    required this.outcome,
    required this.timestamp,
    this.note = '',
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
    );
  }

  Map<String, dynamic> toMap() => {
        'direction': direction,
        'outcome': outcome,
        // store as milliseconds for compactness / compatibility
        'timestamp': timestamp.millisecondsSinceEpoch,
        'note': note,
      };
}

/// Note model with DateTime
class LeadNote {
  final String text;
  final DateTime timestamp;

  LeadNote({
    required this.text,
    required this.timestamp,
  });

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

/// Main Lead model
class Lead {
  final String id;
  final String name;
  final String phoneNumber;
  final String status; // e.g. new, in progress, follow up
  final DateTime lastInteraction;
  final DateTime lastUpdated;
  final List<LeadNote> notes;
  final List<CallHistoryEntry> callHistory;

  Lead({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.status,
    required this.lastInteraction,
    required this.lastUpdated,
    required this.notes,
    required this.callHistory,
  });

  static String generateId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
      Random().nextInt(9999).toString();

  Lead copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? status,
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
      lastInteraction: lastInteraction ?? this.lastInteraction,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      notes: notes ?? this.notes,
      callHistory: callHistory ?? this.callHistory,
    );
  }

  factory Lead.newLead(String phone) {
    final now = DateTime.now();
    return Lead(
      id: generateId(),
      name: '',
      phoneNumber: phone,
      status: 'new',
      lastInteraction: now,
      lastUpdated: now,
      notes: [],
      callHistory: [],
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
        'lastInteraction': lastInteraction.millisecondsSinceEpoch,
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
        'notes': notes.map((n) => n.toMap()).toList(),
        'callHistory': callHistory.map((c) => c.toMap()).toList(),
      };
}
