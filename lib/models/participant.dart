/// A student connected to a classroom session.
enum Presence { connected, reconnecting, disconnected }

class Participant {
  final String id;
  final String name;
  final String deviceType;
  final Presence status;
  final DateTime joinedAt;

  const Participant({
    required this.id,
    required this.name,
    this.deviceType = 'Android',
    this.status = Presence.connected,
    required this.joinedAt,
  });

  Participant copyWith({
    String? id,
    String? name,
    String? deviceType,
    Presence? status,
    DateTime? joinedAt,
  }) {
    return Participant(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceType: deviceType ?? this.deviceType,
      status: status ?? this.status,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'deviceType': deviceType,
        'status': status.name,
        'joinedAt': joinedAt.toIso8601String(),
      };

  factory Participant.fromJson(Map<String, dynamic> json) {
    Presence status = Presence.connected;
    final raw = json['status'] as String?;
    if (raw != null) {
      status = Presence.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => Presence.connected,
      );
    }
    return Participant(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Student',
      deviceType: json['deviceType'] as String? ?? 'Android',
      status: status,
      joinedAt: json['joinedAt'] == null
          ? DateTime.now()
          : DateTime.tryParse(json['joinedAt'] as String) ?? DateTime.now(),
    );
  }
}
