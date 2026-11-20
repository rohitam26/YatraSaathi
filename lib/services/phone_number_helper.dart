/// Utility for validating, normalizing, and formatting telephone and WhatsApp numbers.
///
/// Complies with ITU-T E.164 international numbering standards and WhatsApp Click-to-Chat (wa.me) guidelines.
class PhoneNumberHelper {
  PhoneNumberHelper._();

  /// Removes formatting characters, whitespace, hyphens, brackets, and periods.
  static String cleanRawNumber(String input) {
    return input.replaceAll(RegExp(r'[\s\-\(\)\.\,\/]+'), '').trim();
  }

  /// Normalizes a telephone number into standard international E.164 format (`+[country][national]`).
  ///
  /// Supports:
  /// - Indian 10-digit mobile numbers (6-9 prefix): `9876543210` -> `+919876543210`
  /// - Indian STD 11-digit numbers with leading 0: `09876543210` -> `+919876543210`
  /// - Indian numbers starting with country code without plus: `919876543210` -> `+919876543210`
  /// - Full international numbers with plus: `+14155552671` -> `+14155552671`
  /// - Local numbers with explicit [defaultCountryCode].
  static String normalizeToE164(
    String input, {
    String defaultCountryCode = '+91',
  }) {
    final clean = cleanRawNumber(input);
    if (clean.isEmpty) return '';

    // If already starts with '+', validate and keep
    if (clean.startsWith('+')) {
      final digits = clean.substring(1).replaceAll(RegExp(r'\D'), '');
      return '+$digits';
    }

    final digitsOnly = clean.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) return '';

    // Clean default country code
    final cleanCc = defaultCountryCode.replaceAll(RegExp(r'\D'), '');

    // Case 1: Indian 10-digit mobile starting with 6, 7, 8, 9
    if (digitsOnly.length == 10 && RegExp(r'^[6-9]').hasMatch(digitsOnly)) {
      return '+${cleanCc.isNotEmpty ? cleanCc : '91'}$digitsOnly';
    }

    // Case 2: 11-digit starting with '0' (e.g. 09876543210)
    if (digitsOnly.length == 11 && digitsOnly.startsWith('0')) {
      final stripped = digitsOnly.substring(1);
      if (RegExp(r'^[6-9]').hasMatch(stripped)) {
        return '+${cleanCc.isNotEmpty ? cleanCc : '91'}$stripped';
      }
    }

    // Case 3: 12-digit starting with '91' (e.g. 919876543210)
    if (digitsOnly.length == 12 && digitsOnly.startsWith('91')) {
      return '+$digitsOnly';
    }

    // Case 4: Any other number with at least 7 digits
    if (cleanCc.isNotEmpty && !digitsOnly.startsWith(cleanCc)) {
      return '+$cleanCc$digitsOnly';
    }

    return '+$digitsOnly';
  }

  /// Normalizes a phone number for WhatsApp wa.me links (digits only, no leading `+` or spaces).
  ///
  /// Example: `+91 98765-43210` -> `919876543210`.
  static String normalizeForWaMe(
    String input, {
    String defaultCountryCode = '+91',
  }) {
    final e164 = normalizeToE164(input, defaultCountryCode: defaultCountryCode);
    return e164.replaceAll(RegExp(r'\D'), '');
  }

  /// Validates whether a phone number string conforms to standard telephone format.
  ///
  /// Note: Validates syntax and plausible length only. Does NOT claim or test
  /// whether the destination account actually exists on WhatsApp servers.
  static bool isValidFormat(
    String input, {
    String defaultCountryCode = '+91',
  }) {
    final clean = cleanRawNumber(input);
    if (clean.isEmpty) return false;

    final e164 = normalizeToE164(input, defaultCountryCode: defaultCountryCode);
    final digits = e164.replaceAll(RegExp(r'\D'), '');

    // E.164 specifies between 8 and 15 digits total including country code
    if (digits.length < 8 || digits.length > 15) {
      return false;
    }

    // If Indian number (+91), must have exactly 10 digits after +91 starting with 6-9
    if (e164.startsWith('+91')) {
      final national = e164.substring(3);
      return national.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(national);
    }

    // General international validation (valid digits)
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(e164);
  }

  /// Returns user-friendly format: e.g. `+91 98765 43210` or `+1 (415) 555-2671`.
  static String formatForDisplay(
    String input, {
    String defaultCountryCode = '+91',
  }) {
    final e164 = normalizeToE164(input, defaultCountryCode: defaultCountryCode);
    if (e164.startsWith('+91') && e164.length == 13) {
      // +91 98765 43210
      return '+91 ${e164.substring(3, 8)} ${e164.substring(8)}';
    }
    return e164;
  }

  /// Privacy-preserving phone masking (e.g. `***-***-3210`).
  static String maskPhoneNumber(String input) {
    final clean = cleanRawNumber(input);
    if (clean.length <= 4) return '****';
    final visible = clean.substring(clean.length - 4);
    return '***-***-$visible';
  }

  /// Builds a standard WhatsApp Click-to-Chat HTTPS URL (supported on all platforms and browsers).
  ///
  /// Example: `https://wa.me/919876543210?text=Hello%20world`
  static Uri buildWhatsAppUrl({
    required String phoneNumber,
    required String message,
    String defaultCountryCode = '+91',
  }) {
    final waDigits = normalizeForWaMe(
      phoneNumber,
      defaultCountryCode: defaultCountryCode,
    );
    return Uri.https('wa.me', '/$waDigits', <String, String>{
      'text': message,
    });
  }

  /// Builds a native Android WhatsApp scheme intent URL (`whatsapp://send?phone=...`).
  static Uri buildWhatsAppSchemeUri({
    required String phoneNumber,
    required String message,
    String defaultCountryCode = '+91',
  }) {
    final waDigits = normalizeForWaMe(
      phoneNumber,
      defaultCountryCode: defaultCountryCode,
    );
    return Uri.parse(
      'whatsapp://send?phone=$waDigits&text=${Uri.encodeComponent(message)}',
    );
  }
}
