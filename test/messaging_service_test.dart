import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/services/messaging_service.dart';

void main() {
  group('CompliantSmsMessagingService Suite', () {
    const service = CompliantSmsMessagingService();

    test('formats default arrival message correctly when next stop is provided', () {
      final msg = service.formatDefaultMessage(
        stopName: 'Tambaram',
        nextStopName: 'Chennai Beach',
      );

      expect(msg, contains('safely reached my stop: Tambaram'));
      expect(msg, contains('Continuing journey towards Chennai Beach'));
      expect(msg, contains('YatraSaathi'));
    });

    test('formats default arrival message correctly when destination is final', () {
      final msg = service.formatDefaultMessage(
        stopName: 'Central Terminal',
      );

      expect(msg, contains('safely reached my stop: Central Terminal'));
      expect(msg, isNot(contains('Continuing journey towards')));
    });

    test('masks phone numbers safely to avoid exposing personal data in logs', () {
      expect(service.maskPhoneNumber('+91 9876543210'), equals('***-***-3210'));
      expect(service.maskPhoneNumber('9876543210'), equals('***-***-3210'));
      expect(service.maskPhoneNumber('123'), equals('****'));
      expect(service.maskPhoneNumber(''), equals('****'));
    });

    test('rejects empty phone number with failed status', () async {
      final status = await service.sendCheckInMessage(
        contactName: 'Alice',
        phoneNumber: '   ',
        stopName: 'Station A',
        customMessage: 'Reached',
      );

      expect(status, equals(MessageDeliveryStatus.failed));
    });
  });
}

