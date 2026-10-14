import 'package:classcast_offline/models/classroom_session.dart';
import 'package:classcast_offline/models/doc_types.dart';
import 'package:classcast_offline/models/sync_event.dart';
import 'package:classcast_offline/services/network_service.dart';
import 'package:classcast_offline/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocKind detection', () {
    test('pdf / office / image / text / unknown', () {
      expect(SupportedFiles.kindOf('pdf'), DocKind.pdf);
      expect(SupportedFiles.kindOf('PPTX'), DocKind.powerpoint);
      expect(SupportedFiles.kindOf('doc'), DocKind.word);
      expect(SupportedFiles.kindOf('xlsx'), DocKind.excel);
      expect(SupportedFiles.kindOf('jpg'), DocKind.image);
      expect(SupportedFiles.kindOf('txt'), DocKind.text);
      expect(SupportedFiles.kindOf('zip'), DocKind.unknown);
    });

    test('office files need conversion, pdf is ready', () {
      expect(SupportedFiles.initialStatus(DocKind.pdf), DocStatus.ready);
      expect(SupportedFiles.initialStatus(DocKind.powerpoint),
          DocStatus.needsConversion);
      expect(SupportedFiles.initialStatus(DocKind.unknown),
          DocStatus.unsupported);
    });
  });

  group('SyncEvent wire format', () {
    test('page_changed round-trips with snake_case type', () {
      const e = SyncEvent(
        type: SyncEventType.pageChanged,
        sessionId: 'CLASS-101',
        page: 4,
        totalPages: 12,
      );
      final json = e.toJson();
      expect(json['type'], 'page_changed');
      final back = SyncEvent.fromJson(Map<String, dynamic>.from(json));
      expect(back.type, SyncEventType.pageChanged);
      expect(back.page, 4);
      expect(back.totalPages, 12);
    });

    test('document_url and sync_paused round-trip', () {
      const e = SyncEvent(
        type: SyncEventType.documentChanged,
        sessionId: 'CLASS-101',
        documentId: 'doc-1',
        documentName: 'Lesson.pdf',
        documentUrl: 'http://192.168.43.1:8080/files/Lesson.pdf',
        page: 1,
        totalPages: 12,
        syncPaused: true,
      );
      final back = SyncEvent.fromJson(Map<String, dynamic>.from(e.toJson()));
      expect(back.documentUrl,
          'http://192.168.43.1:8080/files/Lesson.pdf');
      expect(back.documentName, 'Lesson.pdf');
      expect(back.syncPaused, isTrue);
    });

    test('absent optional fields stay null (not defaulted)', () {
      const e = SyncEvent(
        type: SyncEventType.pageChanged,
        sessionId: 'CLASS-101',
        page: 2,
      );
      final json = e.toJson();
      expect(json.containsKey('documentUrl'), isFalse);
      expect(json.containsKey('syncPaused'), isFalse);
      expect(SyncEvent.fromJson(Map<String, dynamic>.from(json)).documentUrl,
          isNull);
    });
  });

  group('ClassroomSession snapshot', () {
    test('carries documentUrl and syncPaused from the host', () {
      final s = ClassroomSession.fromJson(const {
        'id': 'CLASS-101',
        'name': 'Physics',
        'createdAt': '2026-01-01T09:00:00.000',
        'documentUrl': 'http://10.0.0.5:8080/files/Lesson.pdf',
        'page': 3,
        'totalPages': 9,
        'syncPaused': true,
      });
      expect(s.documentUrl, 'http://10.0.0.5:8080/files/Lesson.pdf');
      expect(s.page, 3);
      expect(s.totalPages, 9);
      expect(s.syncPaused, isTrue);
    });

    test('defaults syncPaused to false when the host omits it', () {
      final s = ClassroomSession.fromJson(const {
        'id': 'CLASS-101',
        'name': 'Physics',
        'createdAt': '2026-01-01T09:00:00.000',
      });
      expect(s.syncPaused, isFalse);
      expect(s.documentUrl, isNull);
    });
  });

  group('Join parsing', () {
    test('classcast:// QR payload', () {
      final p = NetworkService.parseJoinInput(
          'classcast://join?host=192.168.43.1&port=8080&session=CLASS-101');
      expect(p, isNotNull);
      expect(p!.host, '192.168.43.1');
      expect(p.port, 8080);
      expect(p.sessionId, 'CLASS-101');
    });

    test('http join address', () {
      final p = NetworkService.parseJoinInput(
          'http://192.168.43.1:8080/s/CLASS-101');
      expect(p, isNotNull);
      expect(p!.host, '192.168.43.1');
      expect(p.sessionId, 'CLASS-101');
    });
  });

  group('Validators', () {
    test('session name + id', () {
      expect(Validators.sessionName(''), isNotNull);
      expect(Validators.sessionName('Introduction to Physics'), isNull);
      expect(Validators.sessionId(''), isNotNull);
      expect(Validators.sessionId('CLASS-101'), isNull);
      expect(
          Validators.studentName('', allowAnonymous: false), isNotNull);
      expect(Validators.studentName('', allowAnonymous: true), isNull);
    });
  });
}
