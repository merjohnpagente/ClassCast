import 'doc_types.dart';

/// A document in the teacher library or shared in a session.
class SharedDocument {
  final String id;
  final String name;
  final String extension;
  final DocKind kind;
  final int sizeBytes;
  final DateTime? lastModified;
  final DocStatus status;
  final int pageCount;
  final int currentPage;
  final String? localPath;
  final String? remoteUrl;

  const SharedDocument({
    required this.id,
    required this.name,
    required this.extension,
    required this.kind,
    this.sizeBytes = 0,
    this.lastModified,
    this.status = DocStatus.ready,
    this.pageCount = 0,
    this.currentPage = 1,
    this.localPath,
    this.remoteUrl,
  });

  bool get viewable =>
      status == DocStatus.ready || status == DocStatus.needsConversion;

  SharedDocument copyWith({
    String? id,
    String? name,
    String? extension,
    DocKind? kind,
    int? sizeBytes,
    DateTime? Function()? lastModified,
    DocStatus? status,
    int? pageCount,
    int? currentPage,
    String? Function()? localPath,
    String? Function()? remoteUrl,
  }) {
    return SharedDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      extension: extension ?? this.extension,
      kind: kind ?? this.kind,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastModified:
          lastModified == null ? this.lastModified : lastModified(),
      status: status ?? this.status,
      pageCount: pageCount ?? this.pageCount,
      currentPage: currentPage ?? this.currentPage,
      localPath: localPath == null ? this.localPath : localPath(),
      remoteUrl: remoteUrl == null ? this.remoteUrl : remoteUrl(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'extension': extension,
        'kind': kind.name,
        'sizeBytes': sizeBytes,
        'lastModified': lastModified?.toIso8601String(),
        'status': status.name,
        'pageCount': pageCount,
        'currentPage': currentPage,
        // The path is what makes a library entry mean anything after a
        // restart. Leaving it out silently empties the library on next launch.
        'localPath': localPath,
        'remoteUrl': remoteUrl,
      };

  factory SharedDocument.fromJson(Map<String, dynamic> json) {
    DocKind kind = DocKind.unknown;
    final rawKind = json['kind'] as String?;
    if (rawKind != null) {
      kind = DocKind.values.firstWhere(
        (e) => e.name == rawKind,
        orElse: () => DocKind.unknown,
      );
    }
    DocStatus status = DocStatus.ready;
    final rawStatus = json['status'] as String?;
    if (rawStatus != null) {
      status = DocStatus.values.firstWhere(
        (e) => e.name == rawStatus,
        orElse: () => DocStatus.ready,
      );
    }
    return SharedDocument(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Document',
      extension: json['extension'] as String? ?? '',
      kind: kind,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      lastModified: json['lastModified'] == null
          ? null
          : DateTime.tryParse(json['lastModified'] as String),
      status: status,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      currentPage: (json['currentPage'] as num?)?.toInt() ?? 1,
      localPath: json['localPath'] as String?,
      remoteUrl: json['remoteUrl'] as String?,
    );
  }
}
