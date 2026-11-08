import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Honest delivery status of an arrival check-in message.
enum MessageDeliveryStatus {
  notTriggered,
  readyToSend,
  composerOpened,
  sentConfirmed,
  failed,
  userCancelled,
}

/// Abstract contract for dispatching arrival check-in messages.
abstract class MessagingService {
  Future<MessageDeliveryStatus> sendCheckInMessage({
    required String contactName,
    required String phoneNumber,
    required String stopName,
    required String customMessage,
    String? journeyName,
  });

  String formatDefaultMessage({
    required String stopName,
    String? nextStopName,
  });

  String maskPhoneNumber(String rawPhone);
}

/// Compliant Android implementation of [MessagingService] that launches
/// the native Android SMS Composer pre-populated with recipient and text.
///
/// Complies fully with Google Play SMS Permissions Policy (avoids dangerous
/// `SEND_SMS` permission). Honors user privacy and never falsely claims
/// `sentConfirmed` when only `composerOpened` was achieved.
class CompliantSmsMessagingService implements MessagingService {
  const CompliantSmsMessagingService();

  @override
  String formatDefaultMessage({
    required String stopName,
    String? nextStopName,
  }) {
    if (nextStopName != null && nextStopName.isNotEmpty) {
      return 'Hi, I have safely reached my stop: $stopName. Continuing journey towards $nextStopName. - Sent via YatraSaathi';
    }
    return 'Hi, I have safely reached my stop: $stopName. - Sent via YatraSaathi';
  }

  @override
  String maskPhoneNumber(String rawPhone) {
    final clean = rawPhone.trim();
    if (clean.length <= 4) return '****';
    final visiblePart = clean.substring(clean.length - 4);
    return '***-***-$visiblePart';
  }

  @override
  Future<MessageDeliveryStatus> sendCheckInMessage({
    required String contactName,
    required String phoneNumber,
    required String stopName,
    required String customMessage,
    String? journeyName,
  }) async {
    final trimmedPhone = phoneNumber.replaceAll(RegExp(r'\s+'), '');
    if (trimmedPhone.isEmpty) {
      debugPrint('[MessagingService] Cannot send SMS: Empty phone number.');
      return MessageDeliveryStatus.failed;
    }

    final messageText = customMessage.trim().isNotEmpty
        ? customMessage.trim()
        : formatDefaultMessage(stopName: stopName);

    // Sanitize and mask in logs to prevent PII exposure
    debugPrint(
      '[MessagingService] Opening SMS composer for contact "$contactName" (${maskPhoneNumber(trimmedPhone)}) for stop "$stopName".',
    );

    try {
      // Build compliant sms: URI scheme
      // Android SMS URI standard: sms:<phone>?body=<encodedText>
      final uri = Uri(
        scheme: 'sms',
        path: trimmedPhone,
        queryParameters: <String, String>{'body': messageText},
      );

      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          // Honest status: Composer is opened; Android OS leaves final send confirmation to the user
          debugPrint(
            '[MessagingService] Native SMS composer opened successfully.',
          );
          return MessageDeliveryStatus.composerOpened;
        } else {
          debugPrint('[MessagingService] Failed to launch SMS composer URL.');
          return MessageDeliveryStatus.failed;
        }
      } else {
        // Fallback: try raw query string if parameter encoding was rejected
        final fallbackUri = Uri.parse(
          'sms:$trimmedPhone?body=${Uri.encodeComponent(messageText)}',
        );
        if (await canLaunchUrl(fallbackUri)) {
          await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
          return MessageDeliveryStatus.composerOpened;
        }

        debugPrint('[MessagingService] Device cannot launch SMS uri: $uri');
        return MessageDeliveryStatus.failed;
      }
    } catch (e, stack) {
      debugPrint('[MessagingService] Exception launching SMS composer: $e\n$stack');
      return MessageDeliveryStatus.failed;
    }
  }
}

