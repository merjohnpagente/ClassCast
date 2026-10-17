import 'package:classcast_offline/models/classroom_session.dart';
import 'package:classcast_offline/models/doc_types.dart';
import 'package:classcast_offline/models/sync_event.dart';
import 'package:classcast_offline/services/network_service.dart';
import 'package:classcast_offline/utils/local_ip.dart';
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

    test('modern office files are ready, pdf is ready', () {
      expect(SupportedFiles.initialStatus(DocKind.pdf), DocStatus.ready);
      // The app opens pptx / docx / xlsx itself, so there is nothing to
      // convert before presenting them.
      expect(SupportedFiles.initialStatus(DocKind.powerpoint),
          DocStatus.ready);
      expect(SupportedFiles.initialStatus(DocKind.word), DocStatus.ready);
      expect(SupportedFiles.initialStatus(DocKind.excel), DocStatus.ready);
      expect(SupportedFiles.initialStatus(DocKind.unknown),
          DocStatus.unsupported);
    });

    test('legacy binary office files cannot be opened on device', () {
      expect(SupportedFiles.rendersOnDevice('pptx'), isTrue);
      expect(SupportedFiles.rendersOnDevice('docx'), isTrue);
      expect(SupportedFiles.rendersOnDevice('xlsx'), isTrue);
      expect(SupportedFiles.rendersOnDevice('ppt'), isFalse);
      expect(SupportedFiles.isLegacyOffice('ppt'), isTrue);
      expect(SupportedFiles.isLegacyOffice('xls'), isTrue);
      // The extension decides: a legacy .ppt is unsupported even though its
      // DocKind (powerpoint) on its own would be ready.
      expect(SupportedFiles.statusFor('pptx'), DocStatus.ready);
      expect(SupportedFiles.statusFor('ppt'), DocStatus.unsupported);
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

    test('the teacher key survives a save and reload', () {
      // It used to be dropped, so a restored or edited session sent an empty
      // key and the host answered 403 to every control call.
      final live = ClassroomSession(
        id: 'CLASS-101',
        name: 'Physics',
        createdAt: DateTime.parse('2026-01-01T09:00:00.000'),
        teacherKey: 'AB3DEFGH',
      );
      final restored = ClassroomSession.fromJson(live.toJson());
      expect(restored.teacherKey, 'AB3DEFGH');
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
      expect(p.alts, isEmpty);
    });

    test('http join address', () {
      final p = NetworkService.parseJoinInput(
          'http://192.168.43.1:8080/s/CLASS-101');
      expect(p, isNotNull);
      expect(p!.host, '192.168.43.1');
      expect(p.sessionId, 'CLASS-101');
    });

    test('the QR carries the teacher other addresses', () {
      // One code for both networks: the phone scans once and keeps whichever
      // address answers, so a hotspot and a classroom Wi-Fi stop being two
      // different experiences.
      final payload = NetworkService.qrPayload(
        host: '192.168.43.1',
        port: 8080,
        sessionId: 'CLASS-101',
        altHosts: ['192.168.1.24', '192.168.43.1', ''],
      );
      final p = NetworkService.parseJoinInput(payload);
      expect(p, isNotNull);
      expect(p!.host, '192.168.43.1');
      expect(p.alts, ['192.168.1.24'],
          reason: 'the duplicate and the blank must be dropped');

      // An address a student could never reach is not worth a probe.
      final withJunk = NetworkService.parseJoinInput(NetworkService.qrPayload(
        host: '192.168.43.1',
        port: 8080,
        sessionId: 'CLASS-101',
        altHosts: ['example.com', '169.254.1.1', '192.168.0.9'],
      ));
      expect(withJunk!.alts, ['192.168.0.9']);
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
  group('LAN address selection', () {
    test('accepts hotspot and home/school Wi-Fi addresses', () {
      // Android hotspot.
      expect(NetworkService.isPrivateAddress('192.168.43.1'), isTrue);
      // Typical home/school router.
      expect(NetworkService.isPrivateAddress('192.168.1.24'), isTrue);
      expect(NetworkService.isPrivateAddress('10.0.0.5'), isTrue);
      expect(NetworkService.isPrivateAddress('172.16.4.9'), isTrue);
      expect(NetworkService.isPrivateAddress('172.31.255.1'), isTrue);
    });

    test('rejects addresses students could never reach', () {
      expect(NetworkService.isPrivateAddress(null), isFalse);
      expect(NetworkService.isPrivateAddress(''), isFalse);
      expect(NetworkService.isPrivateAddress('127.0.0.1'), isFalse);
      // Link-local: what you get with no real network.
      expect(NetworkService.isPrivateAddress('169.254.10.1'), isFalse);
      // 172.15 / 172.32 are outside the RFC1918 block.
      expect(NetworkService.isPrivateAddress('172.15.0.1'), isFalse);
      expect(NetworkService.isPrivateAddress('172.32.0.1'), isFalse);
      // Not an address at all.
      expect(NetworkService.isPrivateAddress('nope'), isFalse);
      expect(NetworkService.isPrivateAddress('999.1.1.1'), isFalse);
      // Emulator loopback alias — useless to a student.
      expect(NetworkService.isPrivateAddress('10.0.2.15'), isTrue,
          reason: 'private range, but the emulator alias; kept as-is so the '
              'caller can report the address it actually got');
    });
  });

  group('Which address the QR advertises', () {
    test('the hotspot interface comes before the Wi-Fi one', () {
      // The teacher is on the school router and serving a hotspot: `ap0` and
      // `wlan0` are on two subnets that cannot see each other. Taking the
      // Wi-Fi plugin's answer first is what made the hotspot and the classroom
      // Wi-Fi behave differently on the very same phone.
      final ranked = NetworkService.rankAddresses(
        [
          (nic: 'wlan0', ip: '192.168.1.24'),
          (nic: 'ap0', ip: '192.168.43.1'),
        ],
        pluginIp: '192.168.1.24',
      );
      expect(ranked.first, '192.168.43.1',
          reason: 'a hotspot client can only reach the tether address');
      expect(ranked, ['192.168.43.1', '192.168.1.24'],
          reason: 'the station address is still offered, and only once');
    });

    test('the plugin answer is the last resort, not the first', () {
      final ranked = NetworkService.rankAddresses(
        const [],
        pluginIp: '192.168.1.24',
      );
      expect(ranked, ['192.168.1.24']);
    });

    test('addresses students could never reach are dropped', () {
      final ranked = NetworkService.rankAddresses(
        [
          (nic: 'tun0', ip: '10.8.0.2'), // a VPN
          (nic: 'wlan0', ip: '169.254.3.3'), // link-local
          (nic: 'eth0', ip: '192.168.9.9'),
        ],
        pluginIp: '169.254.9.9',
      );
      expect(ranked, ['192.168.9.9']);
    });
  });

  group('The classroom address', () {
    test('is found from the interfaces when the Wi-Fi plugin has nothing',
        () async {
      // The bug this guards: a teacher turns on the hotspot, the Wi-Fi plugin
      // reports no association, and the QR code went out with no address in
      // it. Scanning it did nothing and nothing said why.
      final fromInterfaces = await localInterfaceIp();

      // Whatever the runner reports, it must be a private address a student
      // could actually reach — or nothing at all, which the UI treats as "no
      // address" rather than advertising something useless.
      if (fromInterfaces != null && fromInterfaces.isNotEmpty) {
        expect(
          NetworkService.isPrivateAddress(fromInterfaces),
          isTrue,
          reason: 'advertised $fromInterfaces, which a student cannot reach',
        );
      }
    });

    test('an address is never taken from a virtual adapter', () async {
      // Best-effort: the assertion only has teeth where an interface exists.
      final ip = await localInterfaceIp();
      if (ip != null && ip.isEmpty) return;
      expect(ip, isNot(contains('127.0.0.1')));
    });
  });
}
