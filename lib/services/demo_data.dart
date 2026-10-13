import '../models/classroom_session.dart';
import '../models/doc_types.dart';
import '../models/participant.dart';
import '../models/shared_document.dart';

/// Explicitly-labeled demo content. Used ONLY when [demoMode] is on
/// (role-selection footer toggle). Production builds show real data
/// or empty states — never fake students or sessions.
class DemoData {
  static List<ClassroomSession> sessions() {
    final now = DateTime.now();
    return [
      ClassroomSession(
        id: 'CLASS-101',
        name: 'Class 101',
        subject: 'Introduction to Physics',
        hostIp: '192.168.43.1',
        port: 8080,
        createdAt: now.subtract(const Duration(hours: 2)),
        isActive: true,
        documentId: 'doc-demo1',
        documentName: 'Lesson_1.pdf',
        page: 4,
        totalPages: 12,
      ),
      ClassroomSession(
        id: 'CLASS-202',
        name: 'Science Class',
        subject: 'Biology',
        createdAt: now.subtract(const Duration(hours: 4)),
        isActive: false,
      ),
      ClassroomSession(
        id: 'CLASS-303',
        name: 'Math Review',
        subject: 'Algebra',
        createdAt: now.subtract(const Duration(hours: 6)),
        isActive: false,
      ),
    ];
  }

  static List<SharedDocument> documents() {
    final now = DateTime.now();
    return [
      SharedDocument(
        id: 'doc-demo1',
        name: 'Lesson_1',
        extension: 'pdf',
        kind: DocKind.pdf,
        sizeBytes: 2400000,
        lastModified: now.subtract(const Duration(days: 1)),
        pageCount: 12,
        currentPage: 4,
      ),
      SharedDocument(
        id: 'doc-demo2',
        name: 'Introduction to Science',
        extension: 'pptx',
        kind: DocKind.powerpoint,
        sizeBytes: 5100000,
        lastModified: now.subtract(const Duration(days: 2)),
        status: DocStatus.needsConversion,
        pageCount: 18,
      ),
      SharedDocument(
        id: 'doc-demo3',
        name: 'Worksheet_3',
        extension: 'docx',
        kind: DocKind.word,
        sizeBytes: 860000,
        lastModified: now.subtract(const Duration(days: 3)),
        status: DocStatus.needsConversion,
      ),
      SharedDocument(
        id: 'doc-demo4',
        name: 'Grades_Q1',
        extension: 'xlsx',
        kind: DocKind.excel,
        sizeBytes: 320000,
        lastModified: now.subtract(const Duration(days: 4)),
        status: DocStatus.needsConversion,
      ),
      SharedDocument(
        id: 'doc-demo5',
        name: 'Diagram',
        extension: 'png',
        kind: DocKind.image,
        sizeBytes: 940000,
        lastModified: now.subtract(const Duration(days: 5)),
      ),
      SharedDocument(
        id: 'doc-demo6',
        name: 'Notes',
        extension: 'txt',
        kind: DocKind.text,
        sizeBytes: 12000,
        lastModified: now.subtract(const Duration(days: 6)),
      ),
    ];
  }

  static List<Participant> participants() {
    final now = DateTime.now();
    return List.generate(6, (i) {
      return Participant(
        id: 'stu-$i',
        name: 'Student ${i + 1}',
        deviceType: i.isEven ? 'Android' : 'Web',
        status: i == 2 ? Presence.reconnecting : Presence.connected,
        joinedAt: now.subtract(Duration(minutes: 30 - i * 3)),
      );
    });
  }
}
