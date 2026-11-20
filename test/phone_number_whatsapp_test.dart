import 'package:flutter_test/flutter_test.dart';
import 'package:pathsaathi/services/phone_number_helper.dart';

void main() {
  group('Issue 3: Phone Number Normalization & WhatsApp Verification Tests', () {
    test('cleans raw telephone strings removing symbols and whitespace', () {
      expect(PhoneNumberHelper.cleanRawNumber(' +91 98765-43210 '), '+919876543210');
      expect(PhoneNumberHelper.cleanRawNumber('(044) 2233 4455'), '04422334455');
      expect(PhoneNumberHelper.cleanRawNumber('98765.43210'), '9876543210');
      expect(PhoneNumberHelper.cleanRawNumber(''), '');
    });

    test('normalizes 10-digit Indian numbers starting with 6-9 to E.164', () {
      expect(PhoneNumberHelper.normalizeToE164('9876543210'), '+919876543210');
      expect(PhoneNumberHelper.normalizeToE164('6383679809'), '+916383679809');
      expect(PhoneNumberHelper.normalizeToE164('7890123456'), '+917890123456');
      expect(PhoneNumberHelper.normalizeToE164('8901234567'), '+918901234567');
    });

    test('normalizes Indian numbers with leading zero (09876543210) to E.164', () {
      expect(PhoneNumberHelper.normalizeToE164('09876543210'), '+919876543210');
      expect(PhoneNumberHelper.normalizeToE164('06383679809'), '+916383679809');
    });

    test('preserves existing E.164 numbers with country code', () {
      expect(PhoneNumberHelper.normalizeToE164('+919876543210'), '+919876543210');
      expect(PhoneNumberHelper.normalizeToE164('+91 63836 79809'), '+916383679809');
      expect(PhoneNumberHelper.normalizeToE164('+14155552671'), '+14155552671');
      expect(PhoneNumberHelper.normalizeToE164('+447911123456'), '+447911123456');
    });

    test('normalizes 12-digit Indian numbers starting with 91 to E.164', () {
      expect(PhoneNumberHelper.normalizeToE164('919876543210'), '+919876543210');
    });

    test('normalizes phone numbers specifically for WhatsApp wa.me links (digits only)', () {
      expect(PhoneNumberHelper.normalizeForWaMe('9876543210'), '919876543210');
      expect(PhoneNumberHelper.normalizeForWaMe('+91 98765 43210'), '919876543210');
      expect(PhoneNumberHelper.normalizeForWaMe('09876543210'), '919876543210');
      expect(PhoneNumberHelper.normalizeForWaMe('+1 415 555-2671'), '14155552671');
    });

    test('validates standard Indian mobile numbers accurately', () {
      expect(PhoneNumberHelper.isValidFormat('9876543210'), isTrue);
      expect(PhoneNumberHelper.isValidFormat('6383679809'), isTrue);
      expect(PhoneNumberHelper.isValidFormat('09876543210'), isTrue);
      expect(PhoneNumberHelper.isValidFormat('+919876543210'), isTrue);
      expect(PhoneNumberHelper.isValidFormat('+91 98765 43210'), isTrue);
      expect(PhoneNumberHelper.isValidFormat('919876543210'), isTrue);
    });

    test('validates international phone numbers in E.164 format', () {
      expect(PhoneNumberHelper.isValidFormat('+14155552671'), isTrue);
      expect(PhoneNumberHelper.isValidFormat('+447911123456'), isTrue);
      expect(PhoneNumberHelper.isValidFormat('+6581234567'), isTrue);
    });

    test('rejects genuinely invalid or malformed numbers', () {
      expect(PhoneNumberHelper.isValidFormat(''), isFalse);
      expect(PhoneNumberHelper.isValidFormat('123'), isFalse);
      expect(PhoneNumberHelper.isValidFormat('abcdefghij'), isFalse);
      expect(PhoneNumberHelper.isValidFormat('1234567890'), isFalse); // Invalid starting digit for India (1)
      expect(PhoneNumberHelper.isValidFormat('98765'), isFalse); // Too short
    });

    test('masks phone numbers for privacy preserving last 4 digits', () {
      expect(PhoneNumberHelper.maskPhoneNumber('+919876543210'), '***-***-3210');
      expect(PhoneNumberHelper.maskPhoneNumber('9876543210'), '***-***-3210');
      expect(PhoneNumberHelper.maskPhoneNumber('112'), '****');
      expect(PhoneNumberHelper.maskPhoneNumber(''), '****');
    });

    test('builds standard WhatsApp wa.me HTTPS click-to-chat URL', () {
      final uri = PhoneNumberHelper.buildWhatsAppUrl(
        phoneNumber: '9876543210',
        message: 'EMERGENCY ALERT: Safe check-in',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919876543210');
      expect(uri.queryParameters['text'], 'EMERGENCY ALERT: Safe check-in');
    });

    test('builds native Android WhatsApp intent scheme URI', () {
      final uri = PhoneNumberHelper.buildWhatsAppSchemeUri(
        phoneNumber: '+91 98765-43210',
        message: 'Hello WhatsApp',
      );

      expect(uri.scheme, 'whatsapp');
      expect(uri.host, 'send');
      expect(uri.queryParameters['phone'], '919876543210');
      expect(uri.queryParameters['text'], 'Hello WhatsApp');
    });
  });
}
