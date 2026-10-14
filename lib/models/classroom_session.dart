/// A classroom session hosted by a teacher device on the local network.
class ClassroomSession {
  final String id;
  final String name;
  final String subject;
  final String hostIp;
  final int port;
  final DateTime createdAt;
  final bool allowAnonymous;
  final bool allowDownload;
  final bool allowStudentNav;
  final bool isActive;
  final String? documentId;
  final String? documentName;

  /// Where students fetch the file from (teacher host, local network).
  final String? documentUrl;
  final int page;
  final int totalPages;
  final String teacherKey;

  const ClassroomSession({
    required this.id,
    required this.name,
    this.subject = '',
    this.hostIp = '',
    this.port = 8080,
    required this.createdAt,
    this.allowAnonymous = true,
    this.allowDownload = false,
    this.allowStudentNav = false,
    this.isActive = false,
    this.documentId,
    this.documentName,
    this.documentUrl,
    this.page = 1,
    this.totalPages = 0,
    this.teacherKey = '',
  });

  String get joinAddress =>
      hostIp.isEmpty ? '' : 'http://$hostIp:$port/s/$id';

  ClassroomSession copyWith({
    String? id,
    String? name,
    String? subject,
    String? hostIp,
    int? port,
    DateTime? createdAt,
    bool? allowAnonymous,
    bool? allowDownload,
    bool? allowStudentNav,
    bool? isActive,
    String? Function()? documentId,
    String? Function()? documentName,
    String? Function()? documentUrl,
    int? page,
    int? totalPages,
    String? teacherKey,
  }) {
    return ClassroomSession(
      id: id ?? this.id,
      name: name ?? this.name,
      subject: subject ?? this.subject,
      hostIp: hostIp ?? this.hostIp,
      port: port ?? this.port,
      createdAt: createdAt ?? this.createdAt,
      allowAnonymous: allowAnonymous ?? this.allowAnonymous,
      allowDownload: allowDownload ?? this.allowDownload,
      allowStudentNav: allowStudentNav ?? this.allowStudentNav,
      isActive: isActive ?? this.isActive,
      documentId: documentId == null ? this.documentId : documentId(),
      documentName:
          documentName == null ? this.documentName : documentName(),
      documentUrl: documentUrl == null ? this.documentUrl : documentUrl(),
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      teacherKey: teacherKey ?? this.teacherKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subject': subject,
        'hostIp': hostIp,
        'port': port,
        'createdAt': createdAt.toIso8601String(),
        'allowAnonymous': allowAnonymous,
        'allowDownload': allowDownload,
        'allowStudentNav': allowStudentNav,
        'isActive': isActive,
        'documentId': documentId,
        'documentName': documentName,
        'documentUrl': documentUrl,
        'page': page,
        'totalPages': totalPages,
      };

  factory ClassroomSession.fromJson(Map<String, dynamic> json) {
    return ClassroomSession(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Classroom',
      subject: json['subject'] as String? ?? '',
      hostIp: json['hostIp'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 8080,
      createdAt: json['createdAt'] == null
          ? DateTime.now()
          : DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now(),
      allowAnonymous: json['allowAnonymous'] as bool? ?? true,
      allowDownload: json['allowDownload'] as bool? ?? false,
      allowStudentNav: json['allowStudentNav'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? false,
      documentId: json['documentId'] as String?,
      documentName: json['documentName'] as String?,
      documentUrl: json['documentUrl'] as String?,
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
    );
  }
}
