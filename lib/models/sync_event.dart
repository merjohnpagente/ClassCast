/// WebSocket sync event types shared by the teacher host and student clients.
///
/// Wire format is JSON: `{ "type": "page_changed", "sessionId": ..., ... }`.
enum SyncEventType {
  join,
  sessionState,
  documentChanged,
  pageChanged,
  sessionEnded,
  participantJoined,
  participantLeft,
  connectionStatus,

  /// A student raised their hand. Goes the other way too: student -> host ->
  /// teacher, so the teacher sees it without losing control of the page.
  handRaised,

  /// The teacher lowered a student's hand (or the student did).
  handLowered,

  /// A student turned a page on their own screen (only when the teacher
  /// allows it). The teacher sees where that student is — it does not take
  /// the class page away from them.
  studentPageChanged,

  /// The teacher pulled a student's screen back to the class page. Sent to one
  /// student, or to everyone when the teacher wants the whole class back.
  takeControl,
}

extension SyncEventTypeWire on SyncEventType {
  String get wire {
    switch (this) {
      case SyncEventType.join:
        return 'join';
      case SyncEventType.sessionState:
        return 'session_state';
      case SyncEventType.documentChanged:
        return 'document_changed';
      case SyncEventType.pageChanged:
        return 'page_changed';
      case SyncEventType.sessionEnded:
        return 'session_ended';
      case SyncEventType.participantJoined:
        return 'participant_joined';
      case SyncEventType.participantLeft:
        return 'participant_left';
      case SyncEventType.connectionStatus:
        return 'connection_status';
      case SyncEventType.handRaised:
        return 'hand_raised';
      case SyncEventType.handLowered:
        return 'hand_lowered';
      case SyncEventType.studentPageChanged:
        return 'student_page_changed';
      case SyncEventType.takeControl:
        return 'take_control';
    }
  }

  static SyncEventType? fromWire(String? raw) {
    switch (raw) {
      case 'join':
        return SyncEventType.join;
      case 'session_state':
        return SyncEventType.sessionState;
      case 'document_changed':
        return SyncEventType.documentChanged;
      case 'page_changed':
        return SyncEventType.pageChanged;
      case 'session_ended':
        return SyncEventType.sessionEnded;
      case 'participant_joined':
        return SyncEventType.participantJoined;
      case 'participant_left':
        return SyncEventType.participantLeft;
      case 'connection_status':
        return SyncEventType.connectionStatus;
      case 'hand_raised':
        return SyncEventType.handRaised;
      case 'hand_lowered':
        return SyncEventType.handLowered;
      case 'student_page_changed':
        return SyncEventType.studentPageChanged;
      case 'take_control':
        return SyncEventType.takeControl;
      default:
        return null;
    }
  }
}

/// A sync message exchanged over the classroom WebSocket.
class SyncEvent {
  final SyncEventType type;
  final String sessionId;
  final String? documentId;
  final String? documentName;

  /// Where the teacher host serves the shared document from.
  /// Without this a student who joins *before* the teacher shares anything
  /// never learns where to fetch the file.
  final String? documentUrl;

  final int? page;
  final int? totalPages;
  final bool? syncPaused;
  final String? participantId;
  final String? participantName;
  final String? message;
  final bool? teacher;

  const SyncEvent({
    required this.type,
    required this.sessionId,
    this.documentId,
    this.documentName,
    this.documentUrl,
    this.page,
    this.totalPages,
    this.syncPaused,
    this.participantId,
    this.participantName,
    this.message,
    this.teacher,
  });

  Map<String, dynamic> toJson() => {
        'type': type.wire,
        'sessionId': sessionId,
        if (documentId != null) 'documentId': documentId,
        if (documentName != null) 'documentName': documentName,
        if (documentUrl != null) 'documentUrl': documentUrl,
        if (page != null) 'page': page,
        if (totalPages != null) 'totalPages': totalPages,
        if (syncPaused != null) 'syncPaused': syncPaused,
        if (participantId != null) 'participantId': participantId,
        if (participantName != null) 'participantName': participantName,
        if (message != null) 'message': message,
        if (teacher != null) 'teacher': teacher,
      };

  factory SyncEvent.fromJson(Map<String, dynamic> json) {
    final type =
        SyncEventTypeWire.fromWire(json['type'] as String?) ??
            SyncEventType.connectionStatus;
    return SyncEvent(
      type: type,
      sessionId: json['sessionId'] as String? ?? '',
      documentId: json['documentId'] as String?,
      documentName: json['documentName'] as String?,
      documentUrl: json['documentUrl'] as String?,
      page: (json['page'] as num?)?.toInt(),
      totalPages: (json['totalPages'] as num?)?.toInt(),
      syncPaused: json['syncPaused'] as bool?,
      participantId: json['participantId'] as String?,
      participantName: json['participantName'] as String?,
      message: json['message'] as String?,
      teacher: json['teacher'] as bool?,
    );
  }
}
