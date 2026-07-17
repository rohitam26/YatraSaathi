import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'direct_sms_service.dart';

/// Honest delivery status of an arrival check-in message.
enum MessageDeliveryStatus {
  notTriggered,
  pending,
  readyToSend,
  composerOpened,
  sentConfirmed,
  failed,
  userCancelled,
}

/// Operational messaging mode for safety check-ins.
enum MessagingMode {
  /// Launches native Android SMS composer pre-filled with recipient and message.
  /// 100% compliant with Google Play Store policies (no restricted permissions).
  composer,

  /// Directly sends SMS in background via Android SmsManager.
  /// Intended exclusively for privately distributed APK builds with explicit user consent.
  directSms,
}

/// Abstract contract for dispatching arrival check-in messages.
abstract class MessagingService {
  Future<MessageDeliveryStatus> sendCheckInMessage({
    required String contactName,
    required String phoneNumber,
    required String stopName,
    required String customMessage,
    String? journeyName,
    bool sendDirect = false,
  });

  String formatDefaultMessage({
    required String stopName,
    String? nextStopName,
  });

  String maskPhoneNumber(String rawPhone);
}

/// Comprehensive Android implementation of [MessagingService] supporting both:
/// 1. Native SMS Composer (Default, zero restricted permissions, compliant fallback).
/// 2. Direct Background SMS via [DirectSmsService] (for opted-in contacts when consent is granted).
class CompliantSmsMessagingService implements MessagingService {
  const CompliantSmsMessagingService({
    this.directSmsService = const DirectSmsService(),
  });

  final DirectSmsService directSmsService;

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
    bool sendDirect = false,
  }) async {
    final trimmedPhone = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '').trim();
    if (trimmedPhone.isEmpty || trimmedPhone.length < 5) {
      debugPrint('[MessagingService] Cannot send SMS: Invalid or empty phone number "$trimmedPhone".');
      return MessageDeliveryStatus.failed;
    }

    final messageText = customMessage.trim().isNotEmpty
        ? customMessage.trim()
        : formatDefaultMessage(stopName: stopName);

    // If Direct SMS is explicitly requested for this contact, attempt direct transmission
    if (sendDirect) {
      debugPrint(
        '[MessagingService] Attempting Direct SMS dispatch to "$contactName" (${maskPhoneNumber(trimmedPhone)}) for stop "$stopName".',
      );

      final directResult = await directSmsService.sendDirectSms(
        phoneNumber: trimmedPhone,
        message: messageText,
      );

      if (directResult.isSuccess) {
        debugPrint(
          '[MessagingService] Direct SMS transmitted confirmed by Android radio: ${directResult.message}',
        );
        return MessageDeliveryStatus.sentConfirmed;
      }

      debugPrint(
        '[MessagingService] Direct SMS failed (${directResult.errorCode}: ${directResult.message}). Falling back to Native SMS Composer.',
      );
      // Fallback to Native Composer so the user is never stranded
    }

    // Default & Fallback: Launch native Android SMS Composer
    debugPrint(
      '[MessagingService] Opening native SMS composer for contact "$contactName" (${maskPhoneNumber(trimmedPhone)}) for stop "$stopName".',
    );

    try {
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
          debugPrint('[MessagingService] Native SMS composer opened successfully.');
          return MessageDeliveryStatus.composerOpened;
        }
      }

      // Fallback URI parsing for stubborn intent filters
      final fallbackUri = Uri.parse(
        'sms:$trimmedPhone?body=${Uri.encodeComponent(messageText)}',
      );
      if (await canLaunchUrl(fallbackUri)) {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        return MessageDeliveryStatus.composerOpened;
      }

      debugPrint('[MessagingService] Device cannot launch SMS uri: $uri');
      return MessageDeliveryStatus.failed;
    } catch (e, stack) {
      debugPrint('[MessagingService] Exception launching SMS composer: $e\n$stack');
      return MessageDeliveryStatus.failed;
    }
  }
}
